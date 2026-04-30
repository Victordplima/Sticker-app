import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../../core/services/local_storage_path_service.dart';
import '../../stickers/models/sticker.dart';
import '../models/sticker_pack.dart';

class PacksRepository {
  PacksRepository({
    LocalStoragePathService? storagePathService,
    List<StickerPack> initialPacks = const [],
    bool persist = true,
  }) : _storagePathService = storagePathService,
       _persist = persist,
       _packs = List<StickerPack>.from(initialPacks);

  PacksRepository.inMemory({List<StickerPack> initialPacks = const []})
    : this(initialPacks: initialPacks, persist: false);

  final Uuid _uuid = const Uuid();
  final LocalStoragePathService? _storagePathService;
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
      await _storagePathService!.deletePackDirectory(packId);
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
    final packsDirectory = await _storagePathService!.getPacksDirectory();
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

    final metadataFile = await _storagePathService!.getPackMetadataFile(
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
    final metadataFile = await _storagePathService!.getPackMetadataFile(packId);
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

    final contentsFile = await _storagePathService!.getPackContentsFile(
      pack.id,
    );
    final trayFileName = pack.trayImagePath == null
        ? ''
        : _fileName(pack.trayImagePath!);
    final contents = {
      'identifier': pack.id,
      'name': pack.name,
      'publisher': pack.author,
      'tray_image_file': trayFileName,
      'image_data_version': DateTime.now().millisecondsSinceEpoch.toString(),
      'avoid_cache': false,
      'animated_sticker_pack': pack.stickers.any(
        (sticker) => sticker.isAnimated,
      ),
      'stickers': [
        for (final sticker in pack.stickers)
          {
            'image_file': 'stickers/${_fileName(sticker.filePath)}',
            'emojis': sticker.emojis,
          },
      ],
    };

    await contentsFile.writeAsString(jsonEncode(contents), flush: true);
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

    final tray = img.copyResizeCropSquare(image, size: 96);
    final trayFile = await _storagePathService!.getPackTrayImageFile(pack.id);
    await trayFile.writeAsBytes(img.encodePng(tray), flush: true);
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

    final trayFile = await _storagePathService!.getPackTrayImageFile(packId);
    await trayFile.writeAsBytes(img.encodePng(image), flush: true);
    return trayFile.path;
  }

  String _fileName(String filePath) {
    final separator = Platform.pathSeparator;
    final index = filePath.lastIndexOf(separator);
    return index == -1 ? filePath : filePath.substring(index + 1);
  }
}
