import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

import '../../../core/services/local_storage_path_service.dart';
import '../../../shared/helpers/emoji_helper.dart';
import '../../stickers/models/sticker.dart';
import '../models/sticker_pack.dart';

class PacksRepository {
  PacksRepository({
    LocalStoragePathService? storagePathService,
    List<StickerPack> initialPacks = const [],
    bool persist = true,
  }) : _storagePathService = storagePathService ?? const LocalStoragePathService(),
       _persist = persist,
       _packs = List<StickerPack>.from(initialPacks);

  PacksRepository.inMemory({List<StickerPack> initialPacks = const []})
    : this(initialPacks: initialPacks, persist: false);

  final Uuid _uuid = const Uuid();
  final LocalStoragePathService _storagePathService;
  final bool _persist;
  final List<StickerPack> _packs;
  bool _isLoaded = false;

  Future<List<StickerPack>> fetchPacks() async {
    await _ensureLoaded();
    return List<StickerPack>.unmodifiable(_packs);
  }

  Future<StickerPack> createPack({
    required String name,
    required String author,
  }) async {
    await _ensureLoaded();
    final packId = _uuid.v4();
    final trayImagePath = await _writePlaceholderTrayImage(packId);
    final newPack = StickerPack(
      id: packId,
      name: name,
      author: author,
      stickers: const [],
      trayImagePath: trayImagePath,
    );

    _packs.insert(0, newPack);
    await _persistPack(newPack);
    return newPack;
  }

  Future<StickerPack> addSticker({
    required String packId,
    required Sticker sticker,
  }) async {
    await _ensureLoaded();
    final index = _packs.indexWhere((pack) => pack.id == packId);
    if (index == -1) {
      throw StateError('Pack nao encontrado: $packId');
    }

    final pack = _packs[index];
    var updatedPack = pack.copyWith(stickers: [...pack.stickers, sticker]);
    final trayImagePath = await _writeTrayImageFromPack(updatedPack);
    updatedPack = updatedPack.copyWith(trayImagePath: trayImagePath);
    _packs[index] = updatedPack;
    await _persistPack(updatedPack);
    return updatedPack;
  }

  Future<void> deletePack(String packId) async {
    await _ensureLoaded();
    _packs.removeWhere((pack) => pack.id == packId);

    if (_persist) {
      await _storagePathService.deletePackDirectory(packId);
    }
  }

  Future<StickerPack?> findById(String packId) async {
    await _ensureLoaded();
    try {
      return _packs.firstWhere((pack) => pack.id == packId);
    } on StateError {
      return null;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_isLoaded) {
      return;
    }

    if (_persist) {
      final persistedPacks = await _loadPersistedPacks();
      _packs
        ..clear()
        ..addAll(persistedPacks);
    }

    _isLoaded = true;
  }

  Future<List<StickerPack>> _loadPersistedPacks() async {
    final packsDirectory = await _storagePathService.getPacksDirectory();
    final children = await packsDirectory.list().toList();
    final packDirectories = children.whereType<Directory>().toList()
      ..sort((left, right) => right.path.compareTo(left.path));

    final result = <StickerPack>[];
    for (final directory in packDirectories) {
      final metadataFile = File(
        '${directory.path}${Platform.pathSeparator}pack.json',
      );
      if (!await metadataFile.exists()) {
        continue;
      }

      final raw = await metadataFile.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      result.add(StickerPack.fromMap(decoded));
    }

    return result;
  }

  Future<void> _persistPack(StickerPack pack) async {
    if (!_persist) {
      return;
    }

    final metadataFile = await _storagePathService.getPackMetadataFile(
      pack.id,
    );
    await metadataFile.writeAsString(jsonEncode(pack.toMap()), flush: true);
    // Do not write WhatsApp-specific contents here; export will be explicit.
  }

  /// Explicitly generate WhatsApp-compatible files (contents.json and tray image).
  /// This is invoked when the user requests export for the pack.
  Future<void> exportPackForWhatsApp(String packId) async {
    if (!_persist) {
      throw StateError('Export nao suportado em repositório em memoria (Web).');
    }

    final pack = await findById(packId);
    if (pack == null) {
      throw StateError('Pack nao encontrado: $packId');
    }

    // Ensure tray image is up-to-date and persisted
    final trayImagePath = await _writeTrayImageFromPack(pack);
    final updatedPack = pack.copyWith(trayImagePath: trayImagePath);
    final index = _packs.indexWhere((item) => item.id == packId);
    if (index != -1) {
      _packs[index] = updatedPack;
    }
    // Persist metadata and contents
    final metadataFile = await _storagePathService.getPackMetadataFile(packId);
    await metadataFile.writeAsString(
      jsonEncode(updatedPack.toMap()),
      flush: true,
    );
    await _writeWhatsAppContents(updatedPack);
  }

  Future<void> _writeWhatsAppContents(StickerPack pack) async {
    if (!_persist) {
      return;
    }

    final contentsFile = await _storagePathService.getPackContentsFile(
      pack.id,
    );
    final trayFileName = pack.trayImagePath == null
      ? ''
      : _fileName(pack.trayImagePath!);
    // We'll build the contents after exporting/converting sticker files
    final exportedStickerEntries = <Map<String, dynamic>>[];

    // Ensure stickers are exported into the pack directory (convert when needed)
    final stickersDir = await _storagePathService.getPackStickersDirectory(pack.id);
    for (final sticker in pack.stickers) {
      try {
        final source = File(sticker.filePath);
        if (!await source.exists()) {
          developer.log('sticker nao encontrado, pulando: ${sticker.filePath}', name: 'PacksRepository');
          continue;
        }

        final sourceLen = await source.length();
        if (sourceLen == 0) {
          developer.log('sticker vazio, pulando: ${sticker.filePath}', name: 'PacksRepository');
          continue;
        }

        final originalFileName = _fileName(sticker.filePath);
        final baseName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;

        // Decide desired extension: prefer webp for static stickers, keep original for animated
        final sourceExt = sticker.filePath.contains('.') ? sticker.filePath.split('.').last.toLowerCase() : '';
        final desiredExt = sticker.isAnimated ? sourceExt : 'webp';

        final destFileName = '$baseName.$desiredExt';
        final dest = File('${stickersDir.path}${Platform.pathSeparator}$destFileName');

        // CRITICAL: If source and dest are the same file, skip copy to avoid
        // truncating the file to 0 bytes (self-copy is destructive on some systems).
        final isSameFile = source.path == dest.path;

        if (isSameFile) {
          exportedStickerEntries.add({
            'image_file': 'stickers/$destFileName',
            'emojis': _exportEmojis(sticker.emojis),
          });
          continue;
        }

        // If animated or already same extension, just copy original
        if (sticker.isAnimated || sourceExt == desiredExt) {
          await source.copy(dest.path);
          exportedStickerEntries.add({
            'image_file': 'stickers/$destFileName',
            'emojis': _exportEmojis(sticker.emojis),
          });
          continue;
        }

        // Source needs conversion to desiredExt — try to decode and re-encode
        final bytes = await source.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          // fallback: copy as-is
          await source.copy(dest.path);
          exportedStickerEntries.add({
            'image_file': 'stickers/$destFileName',
            'emojis': _exportEmojis(sticker.emojis),
          });
          continue;
        }

        // Prepare image: center on square canvas with transparent background, target 512
        final targetDim = 512;
        final resized = _resizePreservingAspectRatioForExport(decoded, targetDim);
        final canvas = img.Image(width: targetDim, height: targetDim, numChannels: 4);
        img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
        final left = ((targetDim - resized.width) / 2).round();
        final top = ((targetDim - resized.height) / 2).round();
        img.compositeImage(canvas, resized, dstX: left, dstY: top);

        if (desiredExt == 'webp') {
          final pngBytes = img.encodePng(canvas);
          if (pngBytes.isEmpty) {
            developer.log('encodePng retornou bytes vazios para ${source.path}', name: 'PacksRepository');
            await source.copy(dest.path);
          } else {
            try {
              final webpBytes = await FlutterImageCompress.compressWithList(
                Uint8List.fromList(pngBytes),
                format: CompressFormat.webp,
                minHeight: targetDim,
                minWidth: targetDim,
                quality: 96,
              );
              if (webpBytes.isNotEmpty) {
                await dest.writeAsBytes(webpBytes, flush: true);
              } else {
                await source.copy(dest.path);
              }
            } catch (e, st) {
              developer.log('erro ao comprimir $destFileName: $e', name: 'PacksRepository', error: e, stackTrace: st);
              await source.copy(dest.path);
            }
          }
        } else if (desiredExt == 'png') {
          final pngBytes = img.encodePng(canvas);
          await dest.writeAsBytes(pngBytes, flush: true);
        } else {
          final pngBytes = img.encodePng(canvas);
          await dest.writeAsBytes(pngBytes, flush: true);
        }

        // Final sanity check: ensure dest is non-empty
        try {
          if (!await dest.exists() || await dest.length() == 0) {
            developer.log('destino vazio/inexistente apos escrita, fazendo fallback copy: ${source.path} -> ${dest.path}', name: 'PacksRepository');
            await source.copy(dest.path);
          }
        } catch (e, st) {
          developer.log('falha no fallback copy: $e', name: 'PacksRepository', error: e, stackTrace: st);
        }

        exportedStickerEntries.add({
          'image_file': 'stickers/$destFileName',
          'emojis': _exportEmojis(sticker.emojis),
        });
      } catch (e, st) {
        developer.log('erro processando sticker ${sticker.filePath}: $e', name: 'PacksRepository', error: e, stackTrace: st);
      }
    }

    if (exportedStickerEntries.length < 3) {
      throw StateError(
        'O WhatsApp exige pelo menos 3 stickers validos. Apenas ${exportedStickerEntries.length} foram exportados.',
      );
    }

    final packName = pack.name.trim().isEmpty ? 'Meu Pack' : pack.name.trim();
    final packPublisher =
        pack.author.trim().isEmpty ? 'Sticker Studio' : pack.author.trim();

    final contents = {
      'identifier': pack.id,
      'name': packName,
      'publisher': packPublisher,
      'tray_image_file': trayFileName,
      'image_data_version': DateTime.now().millisecondsSinceEpoch.toString(),
      'avoid_cache': false,
      'animated_sticker_pack': pack.stickers.any((sticker) => sticker.isAnimated),
      'stickers': exportedStickerEntries,
    };

    await contentsFile.writeAsString(jsonEncode(contents), flush: true);
  }

  img.Image _resizePreservingAspectRatioForExport(img.Image source, int target) {
    if (source.width == target && source.height == target) {
      return source;
    }

    if (source.width >= source.height) {
      return img.copyResize(source, width: target);
    }

    return img.copyResize(source, height: target);
  }

  Future<String?> _writeTrayImageFromPack(StickerPack pack) async {
    if (!_persist || pack.stickers.isEmpty) {
      return pack.trayImagePath;
    }

    final firstStickerFile = File(pack.stickers.first.filePath);
    if (!await firstStickerFile.exists()) {
      return pack.trayImagePath;
    }

    final bytes = await firstStickerFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      return pack.trayImagePath;
    }

    final targetDim = 96;
    final resized = _resizePreservingAspectRatioForExport(image, targetDim);
    final canvas = img.Image(width: targetDim, height: targetDim, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    final left = ((targetDim - resized.width) / 2).round();
    final top = ((targetDim - resized.height) / 2).round();
    img.compositeImage(canvas, resized, dstX: left, dstY: top);
    final trayFile = await _storagePathService.getPackTrayImageFile(pack.id);
    await trayFile.writeAsBytes(img.encodePng(canvas), flush: true);
    return trayFile.path;
  }

  Future<String?> _writePlaceholderTrayImage(String packId) async {
    if (!_persist) {
      return null;
    }

    final image = img.Image(width: 96, height: 96, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 107, 53, 255));
    img.fillCircle(
      image,
      x: 72,
      y: 24,
      radius: 16,
      color: img.ColorRgba8(255, 209, 102, 255),
    );
    img.fillRect(
      image,
      x1: 10,
      y1: 58,
      x2: 86,
      y2: 84,
      color: img.ColorRgba8(36, 28, 23, 255),
    );

    final trayFile = await _storagePathService.getPackTrayImageFile(packId);
    await trayFile.writeAsBytes(img.encodePng(image), flush: true);
    return trayFile.path;
  }

  String _fileName(String filePath) {
    final separator = Platform.pathSeparator;
    final index = filePath.lastIndexOf(separator);
    return index == -1 ? filePath : filePath.substring(index + 1);
  }

  List<String> _exportEmojis(List<String> emojis) {
    final sanitized = EmojiHelper.sanitize(emojis);
    if (sanitized.isEmpty) {
      return const [EmojiHelper.defaultStickerEmoji];
    }
    return sanitized.take(3).toList();
  }
}
