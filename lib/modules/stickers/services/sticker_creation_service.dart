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

  const StickerCreationService();

  bool supportsSource(String sourcePath) {
    final normalized = sourcePath.toLowerCase();
    return normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp');
  }

  StickerCreationPlan buildPlan(String sourcePath, {bool preferAnimatedOutput = false}) {
    return StickerCreationPlan(
      sourcePath: sourcePath,
      targetDimension: targetDimension,
      outputFormat: outputFormat,
      backgroundRemovalReady: true,
      animatedPipelineReady: preferAnimatedOutput,
    );
  }
}