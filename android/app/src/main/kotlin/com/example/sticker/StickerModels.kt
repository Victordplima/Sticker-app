package com.example.sticker

data class StickerAsset(
    val imagePath: String,
    val emojis: List<String>,
    val accessibilityText: String? = null,
) {
    val fileName: String
        get() = imagePath.substringAfterLast('/')
}

data class StickerPackData(
    val identifier: String,
    val name: String,
    val publisher: String,
    val trayImageFile: String,
    val stickers: List<StickerAsset>,
    val publisherEmail: String = "",
    val publisherWebsite: String = "",
    val privacyPolicyWebsite: String = "",
    val licenseAgreementWebsite: String = "",
    val androidPlayStoreLink: String = "",
    val iosAppStoreLink: String = "",
    val imageDataVersion: String = "1",
    val avoidCache: Boolean = false,
    val animatedStickerPack: Boolean = false,
) {
    fun trayFileName(): String = trayImageFile.substringAfterLast('/')
}
