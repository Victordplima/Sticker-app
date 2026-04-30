import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sticker_pack.dart';

final whatsappExportServiceProvider = Provider<WhatsAppExportService>((ref) {
  return const WhatsAppExportService();
});

class WhatsAppExportService {
  const WhatsAppExportService();

  static const MethodChannel _channel = MethodChannel('whatsapp_stickers');

  Future<void> addStickerPack(StickerPack pack) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw const WhatsAppExportException(
        'Adicionar packs ao WhatsApp so esta disponivel no Android.',
      );
    }

    _validatePack(pack);

    await _channel.invokeMethod<void>('addStickerPack', {
      'packData': {
        'identifier': pack.id,
        'name': pack.name,
        'publisher': pack.author,
        'trayImageFile': _fileName(pack.trayImagePath!),
        'stickers': [
          for (final sticker in pack.stickers) _fileName(sticker.filePath),
        ],
      },
    });
  }

  void _validatePack(StickerPack pack) {
    if (pack.stickers.length < 3) {
      throw const WhatsAppExportException(
        'O WhatsApp exige pelo menos 3 stickers por pack.',
      );
    }

    if (pack.stickers.length > 30) {
      throw const WhatsAppExportException(
        'O WhatsApp permite no maximo 30 stickers por pack.',
      );
    }

    if (pack.trayImagePath == null || pack.trayImagePath!.isEmpty) {
      throw const WhatsAppExportException(
        'O pack precisa de um tray icon antes de ser enviado ao WhatsApp.',
      );
    }

    final trayFile = File(pack.trayImagePath!);
    if (!trayFile.existsSync()) {
      throw const WhatsAppExportException(
        'O tray icon do pack nao foi encontrado no armazenamento local.',
      );
    }

    final containsAnimated = pack.stickers.any((sticker) => sticker.isAnimated);
    final containsStatic = pack.stickers.any((sticker) => !sticker.isAnimated);
    if (containsAnimated && containsStatic) {
      throw const WhatsAppExportException(
        'O pack nao pode misturar stickers estaticos e animados.',
      );
    }

    for (final sticker in pack.stickers) {
      final file = File(sticker.filePath);
      if (!file.existsSync()) {
        throw WhatsAppExportException(
          'Sticker nao encontrado: ${sticker.filePath}',
        );
      }

      if (!sticker.filePath.toLowerCase().endsWith('.webp')) {
        throw WhatsAppExportException(
          'Sticker invalido para WhatsApp: ${sticker.filePath}. O formato deve ser WEBP.',
        );
      }
    }
  }

  String _fileName(String filePath) {
    final separator = Platform.pathSeparator;
    final normalized = filePath
        .replaceAll('\\', separator)
        .replaceAll('/', separator);
    final index = normalized.lastIndexOf(separator);
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

class WhatsAppExportException implements Exception {
  const WhatsAppExportException(this.message);

  final String message;

  @override
  String toString() => message;
}
