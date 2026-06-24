import 'package:flutter/material.dart';

import '../../stickers/components/sticker_preview_tile.dart';
import '../models/sticker_pack.dart';

class PackCard extends StatelessWidget {
  const PackCard({
    required this.pack,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  final StickerPack pack;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previews = pack.stickers.take(4).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.name.trim().isEmpty ? 'Pack sem nome' : pack.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (pack.author.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'por ${pack.author}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remover pack',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 112,
                child: previews.isEmpty
                    ? _EmptyPreview(theme: theme)
                    : Row(
                        children: [
                          for (var index = 0; index < previews.length; index++) ...[
                            if (index > 0) const SizedBox(width: 8),
                            Expanded(
                              child: StickerPreviewTile(sticker: previews[index]),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                pack.stickerCount == 1
                    ? '1 sticker'
                    : '${pack.stickerCount} stickers',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.add_photo_alternate_outlined,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
