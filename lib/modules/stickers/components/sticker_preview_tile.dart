import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/helpers/emoji_helper.dart';
import '../models/sticker.dart';

class StickerPreviewTile extends StatelessWidget {
  const StickerPreviewTile({required this.sticker, super.key});

  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryEmoji = EmojiHelper.primaryOrFallback(sticker.emojis);
    final previewFile = File(sticker.filePath);
    final hasPreview = previewFile.existsSync();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.expand(
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: hasPreview
                      ? Image.file(previewFile, fit: BoxFit.cover)
                      : Icon(
                          Icons.sticky_note_2_outlined,
                          size: 28,
                          color: theme.colorScheme.primary,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(primaryEmoji, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              sticker.isAnimated ? 'Animado' : 'Estatico',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
