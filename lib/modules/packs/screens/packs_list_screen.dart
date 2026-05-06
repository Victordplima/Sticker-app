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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              const Color(0xFFE8F1FF),
            ],
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
    final totalStickers = packs.fold<int>(
      0,
      (count, pack) => count + pack.stickerCount,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: AppSpacing.pageInsets,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sticker Studio',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Organize seus packs e acompanhe seus stickers em um unico lugar.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.section),
                _HeroSummary(
                  totalPacks: packs.length,
                  totalStickers: totalStickers,
                ),
                const SizedBox(height: AppSpacing.section),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Seus packs',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
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
                message: 'Crie um pack para comecar a organizar seus stickers.',
                actionLabel: 'Criar pack',
                onAction: () => context.go('/packs/create'),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              96,
            ),
            sliver: SliverList.separated(
              itemCount: packs.length,
              itemBuilder: (context, index) {
                final pack = packs[index];

                return PackCard(
                  pack: pack,
                  onOpen: () => context.go('/packs/${pack.id}'),
                  onDelete: () async {
                    await ref
                        .read(packsControllerProvider.notifier)
                        .removePack(pack.id);
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
          colors: [Color(0xFF0F4FCB), Color(0xFF67A4FF)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1A5EBA),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Resumo',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Visualize rapidamente a quantidade de packs e stickers cadastrados.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFE7F1FF),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryPill(label: 'Packs', value: '$totalPacks'),
              _SummaryPill(label: 'Stickers', value: '$totalStickers'),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFE7F1FF)),
          ),
        ],
      ),
    );
  }
}
