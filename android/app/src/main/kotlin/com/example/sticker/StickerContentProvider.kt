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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import java.io.FileOutputStream
import android.graphics.Canvas
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
        const val AVOID_CACHE = "whatsapp_will_not_cache_stickers"
        const val ANIMATED_STICKER_PACK = "animated_sticker_pack"

        const val STICKER_FILE_NAME_IN_QUERY = "sticker_file_name"
        const val STICKER_FILE_EMOJI_IN_QUERY = "sticker_emoji"
        const val STICKER_FILE_ACCESSIBILITY_TEXT_IN_QUERY = "sticker_accessibility_text"

        private const val METADATA = "metadata"
        private const val METADATA_CODE = 1
        private const val METADATA_SINGLE_CODE = 2
        private const val STICKERS = "stickers"
        private const val STICKERS_CODE = 3
        private const val STICKERS_ASSET = "stickers_asset"
        private const val STICKERS_ASSET_CODE = 4
    }

    private val store by lazy {
        StickerPackStore(requireNotNull(context))
    }

    private lateinit var matcher: UriMatcher

    override fun onCreate(): Boolean {
        val authority = requireNotNull(context).packageName + ".stickercontentprovider"
        matcher = UriMatcher(UriMatcher.NO_MATCH)
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

        // Log file size and header bytes to help diagnose decode failures
        try {
            val exists = fileToServe.exists()
            val length = if (exists) fileToServe.length() else -1L
            var headerHex = ""
            if (exists && length > 0) {
                fileToServe.inputStream().use { input ->
                    val header = ByteArray(minOf(16, length.toInt()))
                    val read = input.read(header)
                    if (read > 0) {
                        headerHex = header.take(read).joinToString("") { String.format("%02X", it) }
                    }
                }
            }
            Log.d("StickerContentProvider", "openAssetFile: file exists=$exists, length=$length, header=$headerHex")
        } catch (e: Exception) {
            Log.w("StickerContentProvider", "openAssetFile: erro ao inspecionar arquivo ${fileToServe.absolutePath}", e)
        }

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
                    // attempt to optimize image if needed
                    val optimized = optimizeImageFile(outFile, requestedFileName, identifier)
                    return optimized ?: outFile
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

            // Invalidate stale cache: if source changed, delete old cache
            if (outFile.exists() && outFile.length() != source.length()) {
                outFile.delete()
            }

            if (outFile.exists() && outFile.length() > 0) {
                // Cache is valid; apply optimization if needed
                val optimizedExisting = optimizeImageFile(outFile, requestedFileName, identifier)
                return optimizedExisting ?: outFile
            }

            source.inputStream().use { input ->
                outFile.outputStream().use { output ->
                    input.copyTo(output)
                    try { output.fd.sync() } catch (_: Exception) { }
                }
            }
            outFile.setReadable(true, false)
            Log.d("StickerContentProvider", "copyToCache: copied to ${outFile.absolutePath}")
            val optimized = optimizeImageFile(outFile, requestedFileName, identifier)
            return optimized ?: outFile
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

    private fun optimizeImageFile(file: File, requestedFileName: String, identifier: String): File? {
        try {
            val nameLower = requestedFileName.lowercase()
            val ext = requestedFileName.substringAfterLast('.', "").lowercase()
            val isTray = ext == "png"
            val isSticker = ext == "webp"
            val targetWidth = if (isTray) 96 else 512
            val targetHeight = if (isTray) 96 else 512
            val maxBytes = if (isTray) (80 * 1024) else (200 * 1024)

            val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
            val bitmap = BitmapFactory.decodeFile(file.absolutePath, options) ?: return file
            val width = bitmap.width
            val height = bitmap.height
            val extension = file.extension.lowercase()
            val formatOk = extension == ext
            val sizeOk = width == targetWidth && height == targetHeight && formatOk && file.length() <= maxBytes
            if (sizeOk) {
                bitmap.recycle()
                return file
            }

            if (width == 0 || height == 0) {
                bitmap.recycle()
                Log.w("StickerContentProvider", "optimizeImageFile: invalid image dimensions for ${file.absolutePath}")
                return file
            }

            val ctx = requireNotNull(context)
            val cacheDir = ctx.externalCacheDir ?: ctx.cacheDir ?: run {
                bitmap.recycle()
                return file
            }

            val outFile = file
            val tmpOut = File(outFile.parentFile, outFile.name + ".tmp")

            // Preserve aspect ratio when scaling and center on transparent canvas
            var scaledWidth: Int
            var scaledHeight: Int
            if (width >= height) {
                scaledWidth = targetWidth
                scaledHeight = ((height.toDouble() * targetWidth) / width.toDouble()).toInt().coerceAtLeast(1)
            } else {
                scaledHeight = targetHeight
                scaledWidth = ((width.toDouble() * targetHeight) / height.toDouble()).toInt().coerceAtLeast(1)
            }

            val scaledBitmap = if (scaledWidth != width || scaledHeight != height) {
                Bitmap.createScaledBitmap(bitmap, scaledWidth, scaledHeight, true)
            } else {
                bitmap
            }

            val finalBitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
            finalBitmap.eraseColor(android.graphics.Color.TRANSPARENT)
            val canvas = Canvas(finalBitmap)
            val left = ((targetWidth - scaledWidth) / 2).toFloat()
            val top = ((targetHeight - scaledHeight) / 2).toFloat()
            canvas.drawBitmap(scaledBitmap, left, top, null)

            // Recycle intermediate bitmaps (not the finalBitmap yet)
            if (scaledBitmap !== bitmap && !scaledBitmap.isRecycled) scaledBitmap.recycle()
            if (!bitmap.isRecycled) bitmap.recycle()

            if (ext == "png") {
                FileOutputStream(tmpOut).use { fos ->
                    finalBitmap.compress(Bitmap.CompressFormat.PNG, 100, fos)
                    try { fos.fd.sync() } catch (_: Exception) { }
                }
            } else if (ext == "webp") {
                val hasAlpha = finalBitmap.hasAlpha()
                if (hasAlpha && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // try lossless first, fallback to lossy loop if size too large
                    FileOutputStream(tmpOut).use { fos ->
                        finalBitmap.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, fos)
                        try { fos.fd.sync() } catch (_: Exception) { }
                    }
                    if (tmpOut.exists() && tmpOut.length() > maxBytes) {
                        var quality = 90
                        val compressFormat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
                        while (quality >= 40) {
                            FileOutputStream(tmpOut).use { fos ->
                                finalBitmap.compress(compressFormat, quality, fos)
                                try { fos.fd.sync() } catch (_: Exception) { }
                            }
                            if (tmpOut.exists() && tmpOut.length() <= maxBytes) break
                            quality -= 10
                        }
                    }
                } else {
                    var quality = 90
                    val compressFormat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
                    while (quality >= 40) {
                        FileOutputStream(tmpOut).use { fos ->
                            finalBitmap.compress(compressFormat, quality, fos)
                            try { fos.fd.sync() } catch (_: Exception) { }
                        }
                        if (tmpOut.exists() && tmpOut.length() <= maxBytes) break
                        quality -= 10
                    }
                }
            } else {
                // Unknown extension: write PNG
                FileOutputStream(tmpOut).use { fos ->
                    finalBitmap.compress(Bitmap.CompressFormat.PNG, 100, fos)
                    try { fos.fd.sync() } catch (_: Exception) { }
                }
            }

            // Recycle the final bitmap now that we're done writing
            if (!finalBitmap.isRecycled) finalBitmap.recycle()

            if (tmpOut.exists()) {
                // replace the cached file atomically
                try {
                    if (outFile.exists()) {
                        outFile.delete()
                    }
                    if (tmpOut.renameTo(outFile)) {
                        outFile.setReadable(true, false)
                        return outFile
                    } else {
                        // fallback: copy bytes
                        tmpOut.inputStream().use { input ->
                            outFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        tmpOut.delete()
                        outFile.setReadable(true, false)
                        return outFile
                    }
                } catch (e: Exception) {
                    Log.w("StickerContentProvider", "optimizeImageFile: could not replace outFile", e)
                    return tmpOut
                }
            }
            return file
        } catch (e: Exception) {
            Log.w("StickerContentProvider", "optimizeImageFile: error optimizing ${file.absolutePath}", e)
            return file
        }
    }
}
