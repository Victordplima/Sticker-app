import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'dart:developer' as developer;
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
  static const int maxStaticStickerBytes = 100 * 1024;
  static const int maxAnimatedStickerBytes = 500 * 1024;

  static const List<String> _animatedSourceExtensions = [
    '.gif',
    '.mp4',
    '.mov',
    '.m4v',
    '.webm',
    '.3gp',
    '.avi',
    '.mkv',
  ];

  static const List<_AnimatedEncodingProfile> _animatedProfiles = [
    _AnimatedEncodingProfile(fps: 12, durationSeconds: 6),
    _AnimatedEncodingProfile(fps: 10, durationSeconds: 6),
    _AnimatedEncodingProfile(fps: 8, durationSeconds: 5),
    _AnimatedEncodingProfile(fps: 6, durationSeconds: 4),
  ];

  static const List<int> _animatedQualities = [70, 60, 50, 42, 34, 26, 18];
  static const List<String> _animatedEncoders = ['libwebp_anim', 'libwebp'];

  StickerCreationService({required LocalStoragePathService storagePathService})
    : _storagePathService = storagePathService;

  final LocalStoragePathService _storagePathService;
  final Uuid _uuid = const Uuid();

  bool supportsSource(String sourcePath) {
    final normalized = sourcePath.toLowerCase();
    return normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp') ||
        supportsAnimatedSource(sourcePath);
  }

  bool supportsAnimatedSource(String sourcePath) {
    final normalized = sourcePath.toLowerCase();
    return _animatedSourceExtensions.any(normalized.endsWith);
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
    final pngList = img.encodePng(preparedImage, level: 6);
    final pngBytes = Uint8List.fromList(pngList);
    if (pngBytes.isEmpty) {
      throw const StickerCreationException(
        'Falha ao gerar PNG interno antes de converter para WEBP.',
      );
    }

    // WhatsApp limits static stickers to 100 KB. Start at quality 80 and
    // reduce if the output exceeds the budget.
    Uint8List webpBytes = Uint8List(0);
    int quality = 80;

    while (quality >= 30) {
      try {
        final compressedResult = await FlutterImageCompress.compressWithList(
          pngBytes,
          format: CompressFormat.webp,
          minHeight: targetDimension,
          minWidth: targetDimension,
          quality: quality,
        );
        webpBytes = Uint8List.fromList(compressedResult);
      } catch (e, st) {
        developer.log('erro ao comprimir para WEBP (quality=$quality): $e',
            name: 'StickerCreationService', error: e, stackTrace: st);
        if (quality <= 30) {
          throw StickerCreationException(
              'Falha ao converter a imagem para WEBP: $e');
        }
      }

      if (webpBytes.isNotEmpty &&
          webpBytes.lengthInBytes <= maxStaticStickerBytes) {
        break;
      }

      quality -= 10;
    }

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

    // Validate written file
    final writtenLength = await outputFile.length();
    if (writtenLength == 0) {
      throw const StickerCreationException(
        'O arquivo WEBP foi escrito com 0 bytes. Tente novamente.',
      );
    }

    return Sticker(id: stickerId, filePath: outputFile.path, emojis: emojis);
  }

  Future<Sticker> createAnimatedSticker({
    required String packId,
    required String sourcePath,
    String? sourceName,
    required List<String> emojis,
  }) async {
    if (kIsWeb) {
      throw const StickerCreationException(
        'Salvar stickers animados localmente para exportacao ao WhatsApp requer Android, iOS ou macOS.',
      );
    }

    if (!supportsAnimatedSource(sourcePath) &&
        !supportsAnimatedSource(sourceName ?? '')) {
      throw const StickerCreationException(
        'Selecione um GIF ou video para gerar sticker animado.',
      );
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StickerCreationException(
        'Arquivo de origem nao encontrado: $sourcePath',
      );
    }

    final packDirectory = await _storagePathService.getPackStickersDirectory(
      packId,
    );

    final stickerId = _uuid.v4();
    final outputFile = File(
      '${packDirectory.path}${Platform.pathSeparator}$stickerId.webp',
    );

    await _convertAnimatedSourceToWebp(
      sourcePath: sourceFile.path,
      outputPath: outputFile.path,
    );

    final writtenLength = await outputFile.length();
    if (writtenLength == 0) {
      throw const StickerCreationException(
        'O sticker animado foi gerado com 0 bytes. Tente outro arquivo.',
      );
    }

    if (writtenLength > maxAnimatedStickerBytes) {
      throw StickerCreationException(
        'O sticker animado ficou acima de 500 KB (${(writtenLength / 1024).ceil()} KB). Tente um video mais curto ou simples.',
      );
    }

    return Sticker(
      id: stickerId,
      filePath: outputFile.path,
      emojis: emojis,
      isAnimated: true,
    );
  }

  Future<void> _convertAnimatedSourceToWebp({
    required String sourcePath,
    required String outputPath,
  }) async {
    String? lastError;

    for (final profile in _animatedProfiles) {
      for (final quality in _animatedQualities) {
        for (final encoder in _animatedEncoders) {
          final outputFile = File(outputPath);
          if (await outputFile.exists()) {
            await outputFile.delete();
          }

          final session = await FFmpegKit.executeWithArguments(
            _buildAnimatedWebpArguments(
              sourcePath: sourcePath,
              outputPath: outputPath,
              profile: profile,
              quality: quality,
              encoder: encoder,
            ),
          );
          final returnCode = await session.getReturnCode();

          if (!ReturnCode.isSuccess(returnCode)) {
            final output = await session.getOutput();
            lastError = output?.trim().isNotEmpty == true
                ? output!.trim()
                : 'FFmpeg retornou codigo $returnCode.';
            continue;
          }

          if (!await outputFile.exists()) {
            lastError = 'FFmpeg finalizou sem criar o arquivo WEBP.';
            continue;
          }

          final outputLength = await outputFile.length();
          if (outputLength > 0 && outputLength <= maxAnimatedStickerBytes) {
            return;
          }

          lastError =
              'Saida com ${(outputLength / 1024).ceil()} KB, acima do limite de 500 KB.';
        }
      }
    }

    throw StickerCreationException(
      'Falha ao converter GIF/video para sticker animado compativel com WhatsApp. ${lastError ?? ''}'.trim(),
    );
  }

  List<String> _buildAnimatedWebpArguments({
    required String sourcePath,
    required String outputPath,
    required _AnimatedEncodingProfile profile,
    required int quality,
    required String encoder,
  }) {
    final filter =
        'fps=${profile.fps},'
        'scale=$targetDimension:$targetDimension:force_original_aspect_ratio=decrease,'
        'pad=$targetDimension:$targetDimension:(ow-iw)/2:(oh-ih)/2:color=0x00000000,'
        'format=rgba';

    return [
      '-y',
      '-i',
      sourcePath,
      '-t',
      profile.durationSeconds.toString(),
      '-an',
      '-vf',
      filter,
      '-loop',
      '0',
      '-c:v',
      encoder,
      '-preset',
      'default',
      '-lossless',
      '0',
      '-compression_level',
      '6',
      '-q:v',
      quality.toString(),
      outputPath,
    ];
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

class _AnimatedEncodingProfile {
  const _AnimatedEncodingProfile({
    required this.fps,
    required this.durationSeconds,
  });

  final int fps;
  final int durationSeconds;
}

class StickerCreationException implements Exception {
  const StickerCreationException(this.message);

  final String message;

  @override
  String toString() => message;
}
