package com.example.sticker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL = "whatsapp_stickers"
		private const val ADD_STICKER_PACK_ACTION = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
		private const val CONSUMER_WHATSAPP_PACKAGE = "com.whatsapp"
		private const val BUSINESS_WHATSAPP_PACKAGE = "com.whatsapp.w4b"
		private const val ADD_PACK_REQUEST_CODE = 200
		private const val VALIDATION_ERROR_EXTRA = "validation_error"
		private const val MAX_TRAY_BYTES = 50 * 1024
		private const val MAX_STATIC_STICKER_BYTES = 100 * 1024
		private const val MAX_ANIMATED_STICKER_BYTES = 500 * 1024
	}

	private var pendingResult: MethodChannel.Result? = null

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

					if (pendingResult != null) {
						result.error("busy", "Ja existe uma adicao de pack em andamento.", null)
						return@setMethodCallHandler
					}

					try {
						val packData = parsePackData(rawPackData)
						validatePackData(packData)
						pendingResult = result
						launchAddStickerPackIntent(packData)
					} catch (exception: Exception) {
						Log.e("MainActivity", "Erro ao adicionar pack ao WhatsApp", exception)
						pendingResult = null
						result.error("whatsapp_add_failed", exception.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	@Deprecated("Deprecated in Java")
	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)

		if (requestCode != ADD_PACK_REQUEST_CODE) {
			return
		}

		val result = pendingResult ?: return
		pendingResult = null

		if (resultCode == Activity.RESULT_OK) {
			result.success(null)
			return
		}

		val validationError = data?.getStringExtra(VALIDATION_ERROR_EXTRA)
		if (!validationError.isNullOrBlank()) {
			Log.e("MainActivity", "WhatsApp rejeitou o pack: $validationError")
			result.error("whatsapp_validation_failed", validationError, null)
		} else {
			result.error("whatsapp_add_cancelled", "Adicao do pack cancelada no WhatsApp.", null)
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

		val store = StickerPackStore(this)
		val stickerPack = store.findStickerPack(packData.identifier)
			?: throw IllegalStateException("Pack exportado nao encontrado no armazenamento local.")

		if (stickerPack.stickers.size < 3) {
			throw IllegalArgumentException("O WhatsApp exige pelo menos 3 stickers por pack.")
		}
		if (stickerPack.stickers.size > 30) {
			throw IllegalArgumentException("O WhatsApp permite no maximo 30 stickers por pack.")
		}

		if (stickerPack.name.isBlank()) {
			throw IllegalStateException("O pack precisa de um nome antes de ser enviado ao WhatsApp.")
		}
		if (stickerPack.publisher.isBlank()) {
			throw IllegalStateException("O pack precisa de um autor/publicador antes de ser enviado ao WhatsApp.")
		}

		if (stickerPack.trayFileName() != packData.trayImageFile.substringAfterLast('/')) {
			throw IllegalStateException("Tray icon exportado nao corresponde ao pack informado.")
		}

		val packDirectory = store.getPackDirectory(packData.identifier)
		val trayFile = File(packDirectory, stickerPack.trayImageFile)
		if (!trayFile.exists() || trayFile.length() == 0L) {
			throw IllegalStateException("Tray icon nao encontrado ou vazio.")
		}
		if (trayFile.length() > MAX_TRAY_BYTES) {
			throw IllegalStateException(
				"Tray icon acima de 50 KB (${trayFile.length() / 1024} KB).",
			)
		}

		val maxStickerBytes = if (stickerPack.animatedStickerPack) {
			MAX_ANIMATED_STICKER_BYTES
		} else {
			MAX_STATIC_STICKER_BYTES
		}

		for (sticker in stickerPack.stickers) {
			val stickerFile = File(packDirectory, sticker.imagePath)
			if (!stickerFile.exists() || stickerFile.length() == 0L) {
				throw IllegalStateException("Sticker ausente ou vazio: ${sticker.fileName}")
			}
			if (stickerFile.length() > maxStickerBytes) {
				throw IllegalStateException(
					"Sticker ${sticker.fileName} acima do limite do WhatsApp (${stickerFile.length() / 1024} KB).",
				)
			}
			if (sticker.emojis.isEmpty()) {
				throw IllegalStateException("Sticker ${sticker.fileName} precisa de pelo menos 1 emoji.")
			}
		}
	}

	private fun launchAddStickerPackIntent(packData: StickerPackData) {
		val authority = "$packageName.stickercontentprovider"
		val intent = Intent().apply {
			action = ADD_STICKER_PACK_ACTION
			putExtra("sticker_pack_id", packData.identifier)
			putExtra("sticker_pack_authority", authority)
			putExtra("sticker_pack_name", packData.name)
		}

		// Verify the ContentProvider exposes metadata for this pack
		val metadataUri = Uri.parse("content://$authority/metadata/${packData.identifier}")
		val resolver = applicationContext.contentResolver
		resolver.query(metadataUri, null, null, null, null)?.use { cursor ->
			if (cursor.count == 0) {
				throw IllegalStateException("Provider nao expõe metadata para o pack ${packData.identifier}")
			}
		} ?: throw IllegalStateException("Provider nao encontrado: $authority")

		// Try WhatsApp consumer first, then business
		val possibleTargets = listOfNotNull(
			if (isPackageInstalled(CONSUMER_WHATSAPP_PACKAGE)) CONSUMER_WHATSAPP_PACKAGE else null,
			if (isPackageInstalled(BUSINESS_WHATSAPP_PACKAGE)) BUSINESS_WHATSAPP_PACKAGE else null,
		)

		var started = false

		for (pkg in possibleTargets) {
			intent.`package` = pkg
			try {
				@Suppress("DEPRECATION")
				startActivityForResult(intent, ADD_PACK_REQUEST_CODE)
				started = true
				break
			} catch (e: ActivityNotFoundException) {
				Log.w("MainActivity", "ActivityNotFoundException for $pkg", e)
			} catch (e: Exception) {
				Log.w("MainActivity", "Exception starting activity for $pkg", e)
			}
		}

		if (!started) {
			intent.`package` = null
			try {
				@Suppress("DEPRECATION")
				startActivityForResult(intent, ADD_PACK_REQUEST_CODE)
				started = true
			} catch (e: Exception) {
				Log.e("MainActivity", "Fallback startActivityForResult failed", e)
			}
		}

		if (!started) {
			pendingResult = null
			throw IllegalStateException(
				"Nao foi possivel abrir o WhatsApp para adicionar o pack. Nenhuma atividade encontrada para a intent.",
			)
		}
	}

	private fun isWhatsAppInstalled(): Boolean {
		return isPackageInstalled(CONSUMER_WHATSAPP_PACKAGE) || isPackageInstalled(BUSINESS_WHATSAPP_PACKAGE)
	}

	private fun checkTrayImageUri(uri: Uri): String? {
		return try {
			val resolver = applicationContext.contentResolver
			var width = -1
			var height = -1

			// First attempt: bounds-only decode (fast)
			resolver.openInputStream(uri)?.use { input ->
				val options = android.graphics.BitmapFactory.Options()
				options.inJustDecodeBounds = true
				android.graphics.BitmapFactory.decodeStream(input, null, options)
				width = options.outWidth
				height = options.outHeight
			} ?: return "nao foi possivel abrir stream"

			// Fallback: full decode if bounds-only failed
			if (width <= 0 || height <= 0) {
				resolver.openInputStream(uri)?.use { input ->
					val bitmap = android.graphics.BitmapFactory.decodeStream(input)
					if (bitmap != null) {
						width = bitmap.width
						height = bitmap.height
						bitmap.recycle()
					}
				}
			}

			if (width <= 0 || height <= 0) return "nao foi possivel decodificar imagem"
			if (width != 96 || height != 96) return "tamanho invalido: ${width}x${height}"

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
			var width = -1
			var height = -1

			// First attempt: bounds-only decode (fast)
			resolver.openInputStream(uri)?.use { input ->
				val options = android.graphics.BitmapFactory.Options()
				options.inJustDecodeBounds = true
				android.graphics.BitmapFactory.decodeStream(input, null, options)
				width = options.outWidth
				height = options.outHeight
			} ?: return "nao foi possivel abrir stream"

			// Fallback: some valid WebP files (especially with alpha) return -1
			// from inJustDecodeBounds. Do a full decode to verify.
			if (width <= 0 || height <= 0) {
				resolver.openInputStream(uri)?.use { input ->
					val bitmap = android.graphics.BitmapFactory.decodeStream(input)
					if (bitmap != null) {
						width = bitmap.width
						height = bitmap.height
						bitmap.recycle()
					}
				}
			}

			if (width <= 0 || height <= 0) return "nao foi possivel decodificar imagem"
			if (width != 512 || height != 512) return "tamanho invalido: ${width}x${height}"

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
