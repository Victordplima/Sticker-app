import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../stickers/components/sticker_preview_tile.dart';
import '../components/pack_details_skeleton.dart';
import '../services/packs_controller.dart';

class PackDetailsScreen extends ConsumerWidget {
  const PackDetailsScreen({required this.packId, super.key});

  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsControllerProvider);
    final pack = ref.watch(packByIdProvider(packId));

    // Enquanto os packs ainda estão sendo carregados do disco, exibe skeleton.
    if (packsAsync.isLoading) {
      return const PackDetailsSkeleton();
    }

    if (pack == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pack nao encontrado.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Voltar para a lista'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pack.name),
        actions: [
          IconButton(
            tooltip: 'Adicionar stickers',
            onPressed: () => context.push('/packs/$packId/stickers/create'),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              const Color(0xFFE9F2FF),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (pack.author.trim().isNotEmpty) ...[
                Text(
                  'por ${pack.author}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
              ],
              Text(
                pack.stickerCount == 1
                    ? '1 sticker'
                    : '${pack.stickerCount} stickers',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _PackActions(packId: packId),
              const SizedBox(height: 24),
              Text(
                'Stickers',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              if (pack.stickers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text('Ainda nao ha stickers neste pack.'),
                )
              else
                GridView.builder(
                  itemCount: pack.stickers.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.9,
                  ),
                  itemBuilder: (context, index) {
                    final sticker = pack.stickers[index];
                    return StickerPreviewTile(sticker: sticker);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackActions extends ConsumerWidget {
  const _PackActions({required this.packId});

  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final createButton = SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: () => context.push('/packs/$packId/stickers/create'),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Criar sticker'),
      ),
    );

    final exportButton = SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: () async {
          try {
            await ref
                .read(packsControllerProvider.notifier)
                .exportPackForWhatsApp(packId);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pack adicionado ao WhatsApp com sucesso.'),
                ),
              );
            }
          } catch (err) {
            if (context.mounted) {
              final message = err is PlatformException && err.message != null
                  ? err.message!
                  : err.toString();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Falha ao adicionar pack no WhatsApp: $message'),
                ),
              );
            }
          }
        },
        icon: const Icon(Icons.share_outlined),
        label: const Text(
          'Adicionar ao WhatsApp',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [createButton, const SizedBox(height: 12), exportButton],
          );
        }

        return Row(
          children: [
            Expanded(child: createButton),
            const SizedBox(width: 12),
            Expanded(child: exportButton),
          ],
        );
      },
    );
  }
}

