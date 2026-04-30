import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../../core/services/local_storage_path_service.dart';
import '../models/sticker.dart';

final stickerCreationServiceProvider = Provider<StickerCreationService>((ref) {
  return StickerCreationService(
    storagePathService: ref.read(localStoragePathServiceProvider),
  );
});

class StickerCreationPlan {
  const StickerCreationPlan({
    required this.sourcePath,
    required this.targetDimension,
    required this.outputFormat,
    required this.backgroundRemovalReady,
    required this.animatedPipelineReady,
  });

  final String sourcePath;
  final int targetDimension;
  final String outputFormat;
  final bool backgroundRemovalReady;
  final bool animatedPipelineReady;
}

class StickerCreationService {
  static const int targetDimension = 512;
  static const String outputFormat = 'webp';

  StickerCreationService({required LocalStoragePathService storagePathService})
    : _storagePathService = storagePathService;

  final LocalStoragePathService _storagePathService;
  final Uuid _uuid = const Uuid();

  bool supportsSource(String sourcePath) {
    final normalized = sourcePath.toLowerCase();
    return normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp');
  }

  StickerCreationPlan buildPlan(
    String sourcePath, {
    bool preferAnimatedOutput = false,
  }) {
    return StickerCreationPlan(
      sourcePath: sourcePath,
      targetDimension: targetDimension,
      outputFormat: outputFormat,
      backgroundRemovalReady: true,
      animatedPipelineReady: preferAnimatedOutput,
    );
  }

  Future<Sticker> createSticker({
    required String packId,
    required Uint8List sourceBytes,
    required List<String> emojis,
  }) async {
    if (kIsWeb) {
      throw const StickerCreationException(
        'Salvar stickers localmente para exportacao ao WhatsApp requer Android, iOS, Windows, Linux ou macOS.',
      );
    }

    final decodedImage = img.decodeImage(sourceBytes);
    if (decodedImage == null) {
      throw const StickerCreationException(
        'Nao foi possivel ler a imagem selecionada.',
      );
    }

    final preparedImage = _prepareImage(decodedImage);
    final pngBytes = Uint8List.fromList(img.encodePng(preparedImage, level: 6));
    final webpBytes = await FlutterImageCompress.compressWithList(
      pngBytes,
      format: CompressFormat.webp,
      minHeight: targetDimension,
      minWidth: targetDimension,
      quality: 96,
    );

    if (webpBytes.isEmpty) {
      throw const StickerCreationException(
        'Falha ao converter a imagem para WEBP.',
      );
    }

    final packDirectory = await _storagePathService.getPackStickersDirectory(
      packId,
    );

    final stickerId = _uuid.v4();
    final outputFile = File(
      '${packDirectory.path}${Platform.pathSeparator}$stickerId.webp',
    );
    await outputFile.writeAsBytes(webpBytes, flush: true);

    return Sticker(id: stickerId, filePath: outputFile.path, emojis: emojis);
  }

  img.Image _prepareImage(img.Image source) {
    final resized = _resizePreservingAspectRatio(source);
    final canvas = img.Image(
      width: targetDimension,
      height: targetDimension,
      numChannels: 4,
    );

    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    final left = ((targetDimension - resized.width) / 2).round();
    final top = ((targetDimension - resized.height) / 2).round();
    img.compositeImage(canvas, resized, dstX: left, dstY: top);

    return canvas;
  }

  img.Image _resizePreservingAspectRatio(img.Image source) {
    if (source.width == targetDimension && source.height == targetDimension) {
      return source;
    }

    if (source.width >= source.height) {
      return img.copyResize(source, width: targetDimension);
    }

    return img.copyResize(source, height: targetDimension);
  }
}

class StickerCreationException implements Exception {
  const StickerCreationException(this.message);

  final String message;

  @override
  String toString() => message;
}
