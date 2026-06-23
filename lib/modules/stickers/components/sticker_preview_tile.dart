import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/widgets/skeleton_box.dart';
import '../models/sticker.dart';

class StickerPreviewTile extends StatelessWidget {
  const StickerPreviewTile({required this.sticker, super.key});

  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewFile = File(sticker.filePath);
    final hasPreview = previewFile.existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: hasPreview
            ? Image.file(
                previewFile,
                fit: BoxFit.cover,
                frameBuilder: (
                  context,
                  child,
                  frame,
                  wasSynchronouslyLoaded,
                ) {
                  if (wasSynchronouslyLoaded || frame != null) {
                    return child;
                  }
                  return const SkeletonBox(borderRadius: 16);
                },
              )
            : Center(
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
              ),
      ),
    );
  }
}

