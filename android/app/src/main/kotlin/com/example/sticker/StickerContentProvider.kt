package com.example.sticker

import android.content.ContentProvider
import android.content.ContentResolver
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File

class StickerContentProvider : ContentProvider() {
    companion object {
        const val STICKER_PACK_IDENTIFIER_IN_QUERY = "sticker_pack_identifier"
        const val STICKER_PACK_NAME_IN_QUERY = "sticker_pack_name"
        const val STICKER_PACK_PUBLISHER_IN_QUERY = "sticker_pack_publisher"
        const val STICKER_PACK_ICON_IN_QUERY = "sticker_pack_icon"
        const val ANDROID_APP_DOWNLOAD_LINK_IN_QUERY = "android_play_store_link"
        const val IOS_APP_DOWNLOAD_LINK_IN_QUERY = "ios_app_download_link"
        const val PUBLISHER_EMAIL = "sticker_pack_publisher_email"
        const val PUBLISHER_WEBSITE = "sticker_pack_publisher_website"
        const val PRIVACY_POLICY_WEBSITE = "sticker_pack_privacy_policy_website"
        const val LICENSE_AGREEMENT_WEBSITE = "sticker_pack_license_agreement_website"
        const val IMAGE_DATA_VERSION = "image_data_version"
        const val AVOID_CACHE = "avoid_cache"
        const val ANIMATED_STICKER_PACK = "animated_sticker_pack"

        const val STICKER_FILE_NAME_IN_QUERY = "sticker_file_name"
        const val STICKER_FILE_EMOJI_IN_QUERY = "sticker_emoji"
        const val STICKER_FILE_ACCESSIBILITY_TEXT_IN_QUERY = "sticker_file_accessibility_text"

        private const val METADATA = "metadata"
        private const val METADATA_CODE = 1
        private const val METADATA_SINGLE_CODE = 2
        private const val STICKERS = "stickers"
        private const val STICKERS_CODE = 3
        private const val STICKERS_ASSET = "stickers_asset"
        private const val STICKERS_ASSET_CODE = 4

        private val matcher = UriMatcher(UriMatcher.NO_MATCH)
    }

    private val store by lazy {
        StickerPackStore(requireNotNull(context))
    }

    override fun onCreate(): Boolean {
        val authority = requireNotNull(context).packageName + ".stickercontentprovider"
        matcher.addURI(authority, METADATA, METADATA_CODE)
        matcher.addURI(authority, "$METADATA/*", METADATA_SINGLE_CODE)
        matcher.addURI(authority, "$STICKERS/*", STICKERS_CODE)
        matcher.addURI(authority, "$STICKERS_ASSET/*/*", STICKERS_ASSET_CODE)
        Log.d("StickerContentProvider", "onCreate: authority=$authority")
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        Log.d("StickerContentProvider", "query: uri=$uri")
        return when (matcher.match(uri)) {
            METADATA_CODE -> getPackInfo(uri, store.getStickerPacks())
            METADATA_SINGLE_CODE -> {
                val identifier = uri.lastPathSegment.orEmpty()
                Log.d("StickerContentProvider", "query: metadata single identifier=$identifier")
                val pack = store.findStickerPack(identifier)
                getPackInfo(uri, pack?.let(::listOf) ?: emptyList())
            }
            STICKERS_CODE -> getStickersForPack(uri)
            else -> throw IllegalArgumentException("Unknown URI: $uri")
        }
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        if (matcher.match(uri) != STICKERS_ASSET_CODE) {
            return null
        }

        Log.d("StickerContentProvider", "openAssetFile: uri=$uri, mode=$mode")

        val pathSegments = uri.pathSegments
        if (pathSegments.size != 3) {
            throw IllegalArgumentException("Invalid asset URI: $uri")
        }

        val identifier = pathSegments[1]
        val requestedFileName = pathSegments[2]
        Log.d("StickerContentProvider", "openAssetFile: identifier=$identifier, requestedFileName=$requestedFileName")
        val pack = store.findStickerPack(identifier)
            ?: throw IllegalArgumentException("Pack nao encontrado: $identifier")
        val packDirectory = store.getPackDirectory(identifier)

        val trayFileName = pack.trayFileName()
        val sourceFile = when {
            trayFileName == requestedFileName -> File(packDirectory, pack.trayImageFile)
            else -> {
                val sticker = pack.stickers.firstOrNull { it.fileName == requestedFileName }
                    ?: throw IllegalArgumentException("Sticker nao encontrado: $requestedFileName")
                File(packDirectory, sticker.imagePath)
            }
        }

        Log.d("StickerContentProvider", "openAssetFile: resolved sourceFile=${sourceFile.absolutePath}")

        // Always copy to cache before serving as a robust fallback (helps when assets are stored
        // in APK or internal storage and WhatsApp has trouble accessing them directly).
        var cachedFile: File? = null
        try {
            cachedFile = if (sourceFile.exists()) {
                copyToCache(sourceFile, requestedFileName, identifier)
            } else {
                // Try to copy from APK assets: assets/<identifier>/<requestedFileName>
                copyAssetToCache("$identifier/$requestedFileName", requestedFileName, identifier)
            }
        } catch (e: Exception) {
            Log.e("StickerContentProvider", "Falha ao copiar para cache", e)
            cachedFile = null
        }

        val fileToServe = when {
            cachedFile != null && cachedFile.exists() -> cachedFile
            sourceFile.exists() -> sourceFile
            else -> throw IllegalArgumentException("Arquivo nao encontrado: ${sourceFile.absolutePath}")
        }

        Log.d("StickerContentProvider", "openAssetFile: serving file=${fileToServe.absolutePath}")

        val descriptor = ParcelFileDescriptor.open(fileToServe, ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(descriptor, 0, fileToServe.length())
    }

    private fun copyAssetToCache(assetPath: String, requestedFileName: String, identifier: String): File? {
        try {
            val ctx = requireNotNull(context)
            val cacheDir = ctx.externalCacheDir ?: ctx.cacheDir
            if (cacheDir == null) {
                Log.w("StickerContentProvider", "copyAssetToCache: no cache dir available")
                return null
            }

            if (!cacheDir.exists()) {
                cacheDir.mkdirs()
            }

            val outFile = File(cacheDir, "sticker_${identifier}_$requestedFileName")
            if (outFile.exists()) {
                return outFile
            }

            // Try a few candidate asset paths: provided assetPath, identifier/filename, identifier/stickers/filename
            val candidates = listOf(assetPath, "$identifier/$requestedFileName", "$identifier/stickers/$requestedFileName")
            for (p in candidates) {
                try {
                    ctx.assets.open(p).use { input ->
                        outFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    outFile.setReadable(true, false)
                    Log.d("StickerContentProvider", "copyAssetToCache: copied asset $p to ${outFile.absolutePath}")
                    return outFile
                } catch (_: Exception) {
                    // try next candidate
                }
            }

            Log.w("StickerContentProvider", "copyAssetToCache: asset not found among candidates for $assetPath")
            return null
        } catch (e: Exception) {
            Log.w("StickerContentProvider", "copyAssetToCache: error copying asset", e)
            return null
        }
    }

    private fun copyToCache(source: File, requestedFileName: String, identifier: String): File? {
        try {
            if (!source.exists()) {
                Log.w("StickerContentProvider", "copyToCache: source does not exist: ${source.absolutePath}")
                return null
            }

            val ctx = requireNotNull(context)
            val cacheDir = ctx.externalCacheDir ?: ctx.cacheDir
            if (cacheDir == null) {
                Log.w("StickerContentProvider", "copyToCache: no cache dir available")
                return null
            }

            if (!cacheDir.exists()) {
                cacheDir.mkdirs()
            }

            val outFile = File(cacheDir, "sticker_${identifier}_$requestedFileName")
            if (outFile.exists() && outFile.length() == source.length()) {
                return outFile
            }

            source.inputStream().use { input ->
                outFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            outFile.setReadable(true, false)
            Log.d("StickerContentProvider", "copyToCache: copied to ${outFile.absolutePath}")
            return outFile
        } catch (e: Exception) {
            Log.e("StickerContentProvider", "copyToCache: error", e)
            return null
        }
    }

    override fun getType(uri: Uri): String {
        Log.d("StickerContentProvider", "getType: uri=$uri")
        return when (matcher.match(uri)) {
            METADATA_CODE -> "vnd.android.cursor.dir/vnd.${requireNotNull(context).packageName}.metadata"
            METADATA_SINGLE_CODE -> "vnd.android.cursor.item/vnd.${requireNotNull(context).packageName}.metadata"
            STICKERS_CODE -> "vnd.android.cursor.dir/vnd.${requireNotNull(context).packageName}.stickers"
            STICKERS_ASSET_CODE -> {
                val requestedFileName = uri.lastPathSegment.orEmpty().lowercase()
                if (requestedFileName.endsWith(".png")) "image/png" else "image/webp"
            }
            else -> throw IllegalArgumentException("Unknown URI: $uri")
        }
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        throw UnsupportedOperationException("Not supported")
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri {
        throw UnsupportedOperationException("Not supported")
    }

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int {
        throw UnsupportedOperationException("Not supported")
    }

    private fun getPackInfo(uri: Uri, packs: List<StickerPackData>): Cursor {
        val cursor = MatrixCursor(
            arrayOf(
                STICKER_PACK_IDENTIFIER_IN_QUERY,
                STICKER_PACK_NAME_IN_QUERY,
                STICKER_PACK_PUBLISHER_IN_QUERY,
                STICKER_PACK_ICON_IN_QUERY,
                ANDROID_APP_DOWNLOAD_LINK_IN_QUERY,
                IOS_APP_DOWNLOAD_LINK_IN_QUERY,
                PUBLISHER_EMAIL,
                PUBLISHER_WEBSITE,
                PRIVACY_POLICY_WEBSITE,
                LICENSE_AGREEMENT_WEBSITE,
                IMAGE_DATA_VERSION,
                AVOID_CACHE,
                ANIMATED_STICKER_PACK,
            ),
        )

        for (pack in packs) {
            cursor.addRow(
                arrayOf(
                    pack.identifier,
                    pack.name,
                    pack.publisher,
                    pack.trayFileName(),
                    pack.androidPlayStoreLink,
                    pack.iosAppStoreLink,
                    pack.publisherEmail,
                    pack.publisherWebsite,
                    pack.privacyPolicyWebsite,
                    pack.licenseAgreementWebsite,
                    pack.imageDataVersion,
                    if (pack.avoidCache) 1 else 0,
                    if (pack.animatedStickerPack) 1 else 0,
                ),
            )
        }

        cursor.setNotificationUri(requireNotNull(context).contentResolver, uri)
        return cursor
    }

    private fun getStickersForPack(uri: Uri): Cursor {
        val identifier = uri.lastPathSegment.orEmpty()
        val cursor = MatrixCursor(
            arrayOf(
                STICKER_FILE_NAME_IN_QUERY,
                STICKER_FILE_EMOJI_IN_QUERY,
                STICKER_FILE_ACCESSIBILITY_TEXT_IN_QUERY,
            ),
        )

        val pack = store.findStickerPack(identifier)
        if (pack != null) {
            for (sticker in pack.stickers) {
                cursor.addRow(
                    arrayOf(
                        sticker.fileName,
                        sticker.emojis.joinToString(","),
                        sticker.accessibilityText,
                    ),
                )
            }
        }

        cursor.setNotificationUri(requireNotNull(context).contentResolver, uri)
        return cursor
    }
}
