import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/helpers/emoji_helper.dart';
import '../models/sticker.dart';

class StickerPreviewTile extends StatelessWidget {
  const StickerPreviewTile({required this.sticker, super.key});

  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final primaryEmoji = EmojiHelper.primaryOrFallback(sticker.emojis);
    final previewFile = File(sticker.filePath);
    final hasPreview = previewFile.existsSync();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.expand(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: hasPreview
                      ? Image.file(previewFile, fit: BoxFit.cover)
                      : const Icon(Icons.sticky_note_2_outlined, size: 28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(primaryEmoji, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            sticker.isAnimated ? 'Animado' : 'Estatico',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
