import 'package:flutter/material.dart';

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
    final colors = _paletteFor(pack.id);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${pack.stickerCount} stickers',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF1E1612),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 16,
                      bottom: 16,
                      child: Icon(
                        Icons.photo_library_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pack.name, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          'por ${pack.author}',
                          style: theme.textTheme.bodyMedium,
                        ),
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
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final emoji in pack.previewEmojis)
                    Chip(
                      label: Text(emoji),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (pack.previewEmojis.isEmpty)
                    const Chip(label: Text('Pack vazio')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _paletteFor(String seed) {
    const palettes = [
      [Color(0xFFFF8A5B), Color(0xFFFFD166)],
      [Color(0xFF2A9D8F), Color(0xFF7FD1B9)],
      [Color(0xFF457B9D), Color(0xFFA8DADC)],
      [Color(0xFFB56576), Color(0xFFEBC3DB)],
    ];

    return palettes[seed.hashCode.abs() % palettes.length];
  }
}
