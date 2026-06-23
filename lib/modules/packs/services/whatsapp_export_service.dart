import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_storage_path_service.dart';
import '../models/sticker_pack.dart';

final whatsappExportServiceProvider = Provider<WhatsAppExportService>((ref) {
  return WhatsAppExportService(
    storagePathService: ref.read(localStoragePathServiceProvider),
  );
});

class WhatsAppExportService {
  const WhatsAppExportService({
    LocalStoragePathService? storagePathService,
  }) : _storagePathService = storagePathService ?? const LocalStoragePathService();

  static const MethodChannel _channel = MethodChannel('whatsapp_stickers');
  static const int _maxTrayBytes = 50 * 1024;
  static const int _maxStaticStickerBytes = 100 * 1024;
  static const int _maxAnimatedStickerBytes = 500 * 1024;

  final LocalStoragePathService _storagePathService;

  Future<void> addStickerPack(StickerPack pack) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw const WhatsAppExportException(
        'Adicionar packs ao WhatsApp so esta disponivel no Android.',
      );
    }

    final exportedPack = await _loadExportedPack(pack);
    _validateExportedPack(exportedPack);

    await _channel.invokeMethod<void>('addStickerPack', {
      'packData': {
        'identifier': pack.id,
        'name': exportedPack.name,
        'publisher': exportedPack.publisher,
        'trayImageFile': exportedPack.trayImageFile,
        'stickers': exportedPack.stickerFileNames,
      },
    });
  }

  Future<_ExportedPackData> _loadExportedPack(StickerPack pack) async {
    final contentsFile = await _storagePathService.getPackContentsFile(pack.id);
    if (!await contentsFile.exists()) {
      throw const WhatsAppExportException(
        'O pack ainda nao foi exportado para o WhatsApp.',
      );
    }

    final decoded = jsonDecode(await contentsFile.readAsString()) as Map<String, dynamic>;
    final stickersJson = decoded['stickers'] as List<dynamic>? ?? const [];
    final stickerFileNames = <String>[];

    for (final entry in stickersJson) {
      final stickerMap = entry as Map<String, dynamic>;
      final imageFile = stickerMap['image_file'] as String? ?? '';
      if (imageFile.isEmpty) {
        continue;
      }
      stickerFileNames.add(_fileName(imageFile));
    }

    final trayImageFile = decoded['tray_image_file'] as String? ?? '';
    if (trayImageFile.isEmpty) {
      throw const WhatsAppExportException(
        'O tray icon do pack exportado esta ausente.',
      );
    }

    return _ExportedPackData(
      name: (decoded['name'] as String? ?? pack.name).trim(),
      publisher: (decoded['publisher'] as String? ?? pack.author).trim(),
      trayImageFile: _fileName(trayImageFile),
      stickerFileNames: stickerFileNames,
      animatedStickerPack: decoded['animated_sticker_pack'] as bool? ?? false,
      packDirectory: await _storagePathService.getPackDirectory(pack.id),
    );
  }

  void _validateExportedPack(_ExportedPackData exportedPack) {
    if (exportedPack.stickerFileNames.length < 3) {
      throw WhatsAppExportException(
        'O WhatsApp exige pelo menos 3 stickers por pack. Apenas ${exportedPack.stickerFileNames.length} foram exportados.',
      );
    }

    if (exportedPack.stickerFileNames.length > 30) {
      throw const WhatsAppExportException(
        'O WhatsApp permite no maximo 30 stickers por pack.',
      );
    }

    if (exportedPack.name.isEmpty) {
      throw const WhatsAppExportException(
        'O pack precisa de um nome antes de ser enviado ao WhatsApp.',
      );
    }

    if (exportedPack.publisher.isEmpty) {
      throw const WhatsAppExportException(
        'O pack precisa de um autor/publicador antes de ser enviado ao WhatsApp.',
      );
    }

    final trayFile = File(
      '${exportedPack.packDirectory.path}${Platform.pathSeparator}${exportedPack.trayImageFile}',
    );
    if (!trayFile.existsSync()) {
      throw const WhatsAppExportException(
        'O tray icon do pack nao foi encontrado no armazenamento local.',
      );
    }
    if (trayFile.lengthSync() > _maxTrayBytes) {
      throw WhatsAppExportException(
        'O tray icon precisa ter no maximo 50 KB (atual: ${(trayFile.lengthSync() / 1024).ceil()} KB).',
      );
    }

    final maxStickerBytes = exportedPack.animatedStickerPack
        ? _maxAnimatedStickerBytes
        : _maxStaticStickerBytes;

    for (final stickerFileName in exportedPack.stickerFileNames) {
      final stickerFile = File(
        '${exportedPack.packDirectory.path}${Platform.pathSeparator}stickers${Platform.pathSeparator}$stickerFileName',
      );
      if (!stickerFile.existsSync()) {
        throw WhatsAppExportException(
          'Sticker exportado nao encontrado: $stickerFileName',
        );
      }
      if (stickerFile.lengthSync() == 0) {
        throw WhatsAppExportException(
          'Sticker exportado esta vazio: $stickerFileName',
        );
      }
      if (stickerFile.lengthSync() > maxStickerBytes) {
        throw WhatsAppExportException(
          'Sticker $stickerFileName excede o limite do WhatsApp (${(stickerFile.lengthSync() / 1024).ceil()} KB).',
        );
      }
      if (!stickerFileName.toLowerCase().endsWith('.webp')) {
        throw WhatsAppExportException(
          'Sticker invalido para WhatsApp: $stickerFileName. O formato deve ser WEBP.',
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

class _ExportedPackData {
  const _ExportedPackData({
    required this.name,
    required this.publisher,
    required this.trayImageFile,
    required this.stickerFileNames,
    required this.animatedStickerPack,
    required this.packDirectory,
  });

  final String name;
  final String publisher;
  final String trayImageFile;
  final List<String> stickerFileNames;
  final bool animatedStickerPack;
  final Directory packDirectory;
}

class WhatsAppExportException implements Exception {
  const WhatsAppExportException(this.message);

  final String message;

  @override
  String toString() => message;
}
