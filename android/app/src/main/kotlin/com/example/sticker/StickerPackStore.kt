package com.example.sticker

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class StickerPackStore(private val context: Context) {
    private val packsRoot: File
        get() {
            // Typical native path: <filesDir>/sticker_studio/packs
            val candidate1 = File(context.filesDir, "sticker_studio/packs")

            // Flutter's getApplicationSupportDirectory on Android commonly returns
            // <dataDir>/app_flutter. The packages may write into
            // <dataDir>/app_flutter/sticker_studio/packs. Try this as a fallback.
            val candidate2 = context.filesDir.parentFile?.let { File(it, "app_flutter/sticker_studio/packs") }

            // Another possible location under filesDir/app_flutter
            val candidate3 = File(context.filesDir, "app_flutter/sticker_studio/packs")

            return listOfNotNull(candidate1, candidate2, candidate3).firstOrNull { it.exists() } ?: candidate1
        }

    fun getStickerPacks(): List<StickerPackData> {
        val result = mutableListOf<StickerPackData>()

        // 1) Try persisted packs on disk
        val root = packsRoot
        if (root.exists() && root.isDirectory) {
            val filePacks = root.listFiles()
                ?.filter { it.isDirectory }
                ?.sortedByDescending { it.name }
                ?.mapNotNull { parsePackDirectory(it) }
                ?: emptyList()
            result.addAll(filePacks)
        }

        // 2) Try bundled packs inside APK assets (e.g. assets/<packId>/contents.json)
        try {
            val assetManager = context.assets
            val topLevel = assetManager.list("") ?: arrayOf()
            for (name in topLevel) {
                // Avoid duplicates with on-disk packs
                if (result.any { it.identifier == name }) continue

                try {
                    val path = "$name/contents.json"
                    assetManager.open(path).use { input ->
                        val rawJson = input.bufferedReader().use { it.readText() }
                        val json = JSONObject(rawJson)
                        val packJson = if (json.has("sticker_packs")) {
                            val stickerPacks = json.optJSONArray("sticker_packs") ?: JSONArray()
                            if (stickerPacks.length() == 0) continue
                            stickerPacks.getJSONObject(0)
                        } else {
                            json
                        }

                        val pack = parsePackJson(packJson)
                        if (pack != null) {
                            result.add(pack)
                        }
                    }
                } catch (_: Exception) {
                    // not an asset pack
                }
            }
        } catch (_: Exception) {
            // ignore asset inspection errors
        }

        return result
    }

    fun findStickerPack(identifier: String): StickerPackData? {
        return getStickerPacks().firstOrNull { it.identifier == identifier }
    }

    fun getPackDirectory(identifier: String): File {
        return File(packsRoot, identifier)
    }

    private fun parsePackDirectory(packDirectory: File): StickerPackData? {
        val contentsFile = File(packDirectory, "contents.json")
        if (!contentsFile.exists()) {
            return null
        }

        val rawJson = contentsFile.readText()
        val json = JSONObject(rawJson)
        val packJson = if (json.has("sticker_packs")) {
            val stickerPacks = json.optJSONArray("sticker_packs") ?: JSONArray()
            if (stickerPacks.length() == 0) {
                return null
            }
            stickerPacks.getJSONObject(0)
        } else {
            json
        }

        val pack = parsePackJson(packJson)
        // Prefer using the file's last modified as the image data version if not provided
        return pack?.copy(imageDataVersion = packJson.optString("image_data_version").ifBlank { contentsFile.lastModified().toString() })
    }

    private fun parsePackJson(packJson: JSONObject): StickerPackData? {
        val identifier = packJson.optString("identifier")
        val name = packJson.optString("name")
        val publisher = packJson.optString("publisher")
        val trayImageFile = packJson.optString("tray_image_file")
        if (identifier.isBlank() || trayImageFile.isBlank()) {
            return null
        }

        val stickersJson = packJson.optJSONArray("stickers") ?: JSONArray()
        val stickers = buildList {
            for (index in 0 until stickersJson.length()) {
                val stickerJson = stickersJson.optJSONObject(index) ?: continue
                val imagePath = stickerJson.optString("image_file")
                if (imagePath.isBlank()) {
                    continue
                }
                val emojisArray = stickerJson.optJSONArray("emojis") ?: JSONArray()
                val emojis = buildList {
                    for (emojiIndex in 0 until emojisArray.length()) {
                        add(emojisArray.optString(emojiIndex))
                    }
                }
                add(
                    StickerAsset(
                        imagePath = imagePath,
                        emojis = emojis,
                        accessibilityText = stickerJson.optString("accessibility_text").ifBlank { null },
                    ),
                )
            }
        }

        return StickerPackData(
            identifier = identifier,
            name = name,
            publisher = publisher,
            trayImageFile = trayImageFile,
            stickers = stickers,
            publisherEmail = packJson.optString("publisher_email"),
            publisherWebsite = packJson.optString("publisher_website"),
            privacyPolicyWebsite = packJson.optString("privacy_policy_website"),
            licenseAgreementWebsite = packJson.optString("license_agreement_website"),
            androidPlayStoreLink = packJson.optString("android_play_store_link"),
            iosAppStoreLink = packJson.optString("ios_app_store_link"),
            imageDataVersion = packJson.optString("image_data_version").ifBlank { "1" },
            avoidCache = packJson.optBoolean("avoid_cache", false),
            animatedStickerPack = packJson.optBoolean("animated_sticker_pack", false),
        )
    }
}
