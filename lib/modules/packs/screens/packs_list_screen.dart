import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/app_spacing.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../components/pack_card.dart';
import '../models/sticker_pack.dart';
import '../services/packs_controller.dart';

class PacksListScreen extends ConsumerWidget {
  const PacksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsControllerProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/packs/create'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo pack'),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCE7D6), Color(0xFFF7F1E8)],
          ),
        ),
        child: SafeArea(
          child: packsAsync.when(
            data: (packs) => _PacksListContent(packs: packs),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Padding(
                padding: AppSpacing.pageInsets,
                child: AppEmptyState(
                  title: 'Nao foi possivel carregar seus packs',
                  message: 'Revise o estado local e tente novamente.',
                  actionLabel: 'Tentar de novo',
                  onAction: () => ref.invalidate(packsControllerProvider),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PacksListContent extends ConsumerWidget {
  const _PacksListContent({required this.packs});

  final List<StickerPack> packs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalStickers = packs.fold<int>(0, (count, pack) => count + pack.stickerCount);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: AppSpacing.pageInsets,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sticker Studio', style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 8),
                Text(
                  'Monte colecoes prontas para exportar ao WhatsApp com uma base preparada para stickers estaticos e animados.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.section),
                _HeroSummary(totalPacks: packs.length, totalStickers: totalStickers),
                const SizedBox(height: AppSpacing.section),
                Row(
                  children: [
                    Expanded(
                      child: Text('Seus packs', style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    TextButton.icon(
                      onPressed: () => context.go('/packs/create'),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('Criar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (packs.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.pageInsets,
              child: AppEmptyState(
                title: 'Seu primeiro pack comeca aqui',
                message: 'Crie uma colecao, depois conectamos a etapa de recorte e exportacao.',
                actionLabel: 'Criar pack',
                onAction: () => context.go('/packs/create'),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 96),
            sliver: SliverList.separated(
              itemCount: packs.length,
              itemBuilder: (context, index) {
                final pack = packs[index];

                return PackCard(
                  pack: pack,
                  onOpen: () => context.go('/packs/${pack.id}'),
                  onDelete: () async {
                    await ref.read(packsControllerProvider.notifier).removePack(pack.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Pack ${pack.name} removido.')),
                      );
                    }
                  },
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 16),
            ),
          ),
      ],
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({required this.totalPacks, required this.totalStickers});

  final int totalPacks;
  final int totalStickers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF241C17), Color(0xFF574338)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Painel criativo',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'A estrutura do MVP ja separa packs, stickers, servicos e widgets compartilhados.',
            style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFF3E9DE)),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryPill(label: 'Packs', value: '$totalPacks'),
              _SummaryPill(label: 'Stickers', value: '$totalStickers'),
              const _SummaryPill(label: 'Exportacao', value: 'Android-ready'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFF3E9DE))),
        ],
      ),
    );
  }
}