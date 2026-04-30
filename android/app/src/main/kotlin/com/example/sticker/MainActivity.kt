package com.example.sticker

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.ClipData
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL = "whatsapp_stickers"
		private const val ADD_STICKER_PACK_ACTION = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
		private const val CONSUMER_WHATSAPP_PACKAGE = "com.whatsapp"
		private const val BUSINESS_WHATSAPP_PACKAGE = "com.whatsapp.w4b"
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"addStickerPack" -> {
					val rawPackData = call.argument<Map<String, Any?>>("packData")
					if (rawPackData == null) {
						result.error("invalid_args", "packData nao informado.", null)
						return@setMethodCallHandler
					}

					try {
						val packData = parsePackData(rawPackData)
						validatePackData(packData)
						addStickerPack(packData)
						result.success(null)
					} catch (exception: Exception) {
						Log.e("MainActivity", "Erro ao adicionar pack ao WhatsApp", exception)
						result.error("whatsapp_add_failed", exception.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun parsePackData(data: Map<String, Any?>): StickerPackData {
		val identifier = data["identifier"] as? String ?: throw IllegalArgumentException("identifier ausente")
		val name = data["name"] as? String ?: throw IllegalArgumentException("name ausente")
		val publisher = data["publisher"] as? String ?: throw IllegalArgumentException("publisher ausente")
		val trayImageFile = data["trayImageFile"] as? String
			?: throw IllegalArgumentException("trayImageFile ausente")
		val stickerFileNames = data["stickers"] as? List<*>
			?: throw IllegalArgumentException("stickers ausente")

		val stickers = stickerFileNames.map { fileName ->
			val value = fileName as? String ?: throw IllegalArgumentException("arquivo de sticker invalido")
			StickerAsset(imagePath = "stickers/$value", emojis = emptyList())
		}

		return StickerPackData(
			identifier = identifier,
			name = name,
			publisher = publisher,
			trayImageFile = trayImageFile,
			stickers = stickers,
		)
	}

	private fun validatePackData(packData: StickerPackData) {
		if (!isWhatsAppInstalled()) {
			throw IllegalStateException("WhatsApp nao esta instalado no dispositivo.")
		}
		if (packData.stickers.size < 3) {
			throw IllegalArgumentException("O WhatsApp exige pelo menos 3 stickers por pack.")
		}
		if (packData.stickers.size > 30) {
			throw IllegalArgumentException("O WhatsApp permite no maximo 30 stickers por pack.")
		}

		val stickerPack = StickerPackStore(this).findStickerPack(packData.identifier)
			?: throw IllegalStateException("Pack exportado nao encontrado no armazenamento local.")

		// Normalize ambos os valores para comparar apenas o nome do arquivo
		if (stickerPack.trayFileName() != packData.trayImageFile.substringAfterLast('/')) {
			throw IllegalStateException("Tray icon exportado nao corresponde ao pack informado.")
		}
	}

	private fun addStickerPack(packData: StickerPackData) {
		val authority = "$packageName.stickercontentprovider"
		val intent = Intent(ADD_STICKER_PACK_ACTION).apply {
			putExtra("sticker_pack_id", packData.identifier)
			putExtra("sticker_pack_authority", authority)
			putExtra("sticker_pack_name", packData.name)
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
		}

		// Verifica se o provider expõe metadata para este pack
		// Encode path segments to avoid issues with spaces/charset in identifiers/names
		val encodedId = Uri.encode(packData.identifier)
		val metadataUri = Uri.parse("content://$authority/metadata/$encodedId")
		val resolver = applicationContext.contentResolver
		resolver.query(metadataUri, null, null, null, null)?.use { cursor ->
			if (cursor.count == 0) {
				throw IllegalStateException("Provider nao expõe metadata para o pack ${packData.identifier}")
			}
		} ?: throw IllegalStateException("Provider nao encontrado: $authority")

		// Prepara ClipData com metadata, tray e todos os stickers para transferir permissões
		val clip = ClipData.newUri(resolver, "sticker_pack_metadata", metadataUri)

		// adiciona tray icon (codificando segmentos)
		val trayFileName = packData.trayImageFile.substringAfterLast('/')
		val trayUri = Uri.parse("content://$authority/stickers_asset/$encodedId/${Uri.encode(trayFileName)}")
		clip.addItem(ClipData.Item(trayUri))

		// adiciona cada sticker asset (codificando segmentos)
		for (sticker in packData.stickers) {
			val stickerUri = Uri.parse("content://$authority/stickers_asset/$encodedId/${Uri.encode(sticker.fileName)}")
			clip.addItem(ClipData.Item(stickerUri))
		}

		intent.clipData = clip
		intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

		// Pre-check: certificar que o ContentResolver consegue abrir os assets localmente
		try {
			// metadata
			resolver.openAssetFileDescriptor(metadataUri, "r")?.close()

			// tray
			resolver.openAssetFileDescriptor(trayUri, "r")?.close()

			// stickers
			for (sticker in packData.stickers) {
				val stickerUri = Uri.parse("content://$authority/stickers_asset/$encodedId/${Uri.encode(sticker.fileName)}")
				resolver.openAssetFileDescriptor(stickerUri, "r")?.close()
			}
		} catch (e: Exception) {
			throw IllegalStateException("Falha ao preparar stickers para o WhatsApp: ${e.message}")
		}

		// Validação de formato/tamanho das imagens
		val invalids = mutableListOf<String>()
		checkTrayImageUri(trayUri)?.let { invalids.add("tray: $it") }
		for (sticker in packData.stickers) {
			val stickerUri = Uri.parse("content://$authority/stickers_asset/$encodedId/${Uri.encode(sticker.fileName)}")
			checkStickerImageUri(stickerUri)?.let { invalids.add("${sticker.fileName}: $it") }
		}
		if (invalids.isNotEmpty()) {
			throw IllegalStateException("Imagens de stickers inválidas: ${invalids.joinToString("; ")}")
		}

		// Direciona preferencialmente para o pacote WhatsApp instalado
		val possibleTargets = listOfNotNull(
			if (isPackageInstalled(CONSUMER_WHATSAPP_PACKAGE)) CONSUMER_WHATSAPP_PACKAGE else null,
			if (isPackageInstalled(BUSINESS_WHATSAPP_PACKAGE)) BUSINESS_WHATSAPP_PACKAGE else null,
		)

		var started = false

		// Tenta com cada pacote preferido; concede permissão explícita como fallback
		for (pkg in possibleTargets) {
			intent.`package` = pkg
			try {
				applicationContext.grantUriPermission(pkg, metadataUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
				applicationContext.grantUriPermission(pkg, trayUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
				for (sticker in packData.stickers) {
					val stickerUri = Uri.parse("content://$authority/stickers_asset/$encodedId/${Uri.encode(sticker.fileName)}")
					applicationContext.grantUriPermission(pkg, stickerUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
				}
			} catch (_: Exception) {
				// ignore grant failures; fallback via ClipData + flags
			}

			val matches = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
			if (matches.isNotEmpty()) {
				try {
					startActivity(intent)
					started = true
					break
				} catch (e: Exception) {
					// continue to next
				}
			}
		}

		if (!started) {
			// fallback: try without specifying a package
			intent.`package` = null
			val matches = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
			if (matches.isNotEmpty()) {
				try {
					startActivity(intent)
					started = true
				} catch (e: Exception) {
					// will throw below
				}
			}
		}

		if (!started) {
			throw IllegalStateException("Nao foi possivel abrir o WhatsApp para adicionar o pack. Nenhuma atividade encontrada para a intent.")
		}
	}

	private fun isWhatsAppInstalled(): Boolean {
		return isPackageInstalled(CONSUMER_WHATSAPP_PACKAGE) || isPackageInstalled(BUSINESS_WHATSAPP_PACKAGE)
	}

	private fun checkTrayImageUri(uri: Uri): String? {
		return try {
			val resolver = applicationContext.contentResolver
			resolver.openInputStream(uri)?.use { input ->
				val options = android.graphics.BitmapFactory.Options()
				options.inJustDecodeBounds = true
				android.graphics.BitmapFactory.decodeStream(input, null, options)
				val width = options.outWidth
				val height = options.outHeight
				if (width <= 0 || height <= 0) return "nao foi possivel decodificar imagem"
				if (width != 96 || height != 96) return "tamanho invalido: ${width}x${height}"
			} ?: return "nao foi possivel abrir stream"
			val name = uri.lastPathSegment?.lowercase() ?: ""
			if (!name.endsWith(".png")) return "formato invalido: esperado .png"
			null
		} catch (e: Exception) {
			"erro ao validar imagem: ${e.message}"
		}
	}

	private fun checkStickerImageUri(uri: Uri): String? {
		return try {
			val resolver = applicationContext.contentResolver
			resolver.openInputStream(uri)?.use { input ->
				val options = android.graphics.BitmapFactory.Options()
				options.inJustDecodeBounds = true
				android.graphics.BitmapFactory.decodeStream(input, null, options)
				val width = options.outWidth
				val height = options.outHeight
				if (width <= 0 || height <= 0) return "nao foi possivel decodificar imagem"
				if (width != 512 || height != 512) return "tamanho invalido: ${width}x${height}"
			} ?: return "nao foi possivel abrir stream"
			val name = uri.lastPathSegment?.lowercase() ?: ""
			if (!name.endsWith(".webp")) return "formato invalido: esperado .webp"
			null
		} catch (e: Exception) {
			"erro ao validar imagem: ${e.message}"
		}
	}

	private fun isPackageInstalled(packageName: String): Boolean {
		return try {
			val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
			applicationInfo.enabled
		} catch (_: PackageManager.NameNotFoundException) {
			false
		}
	}
}
