import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/app_spacing.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../components/pack_card.dart';
import '../components/packs_list_skeleton.dart';
import '../models/sticker_pack.dart';
import '../services/packs_controller.dart';

class PacksListScreen extends ConsumerWidget {
  const PacksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsControllerProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 760;

    return Scaffold(
      floatingActionButton: isWide
          ? null
          : FloatingActionButton.extended(
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
              const Color(0xFFEFF6F4),
            ],
          ),
        ),
        child: SafeArea(
          child: packsAsync.when(
            data: (packs) => _PacksListContent(packs: packs),
            loading: () => const PacksListSkeleton(),
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
    final averageStickers = packs.isEmpty ? 0.0 : totalStickers / packs.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _CenteredContent(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    isWide ? 28 : 16,
                    AppSpacing.page,
                    AppSpacing.section,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HomeHeader(
                        isWide: isWide,
                        onCreate: () => context.go('/packs/create'),
                      ),
                      const SizedBox(height: AppSpacing.section),
                      _HomeOverview(
                        isWide: isWide,
                        totalPacks: packs.length,
                        totalStickers: totalStickers,
                        averageStickers: averageStickers,
                        onCreate: () => context.go('/packs/create'),
                      ),
                      const SizedBox(height: AppSpacing.section),
                      _PacksSectionHeader(
                        packCount: packs.length,
                        onCreate: () => context.go('/packs/create'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (packs.isEmpty)
              SliverToBoxAdapter(
                child: _CenteredContent(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      0,
                      AppSpacing.page,
                      96,
                    ),
                    child: AppEmptyState(
                      title: 'Seu primeiro pack comeca aqui',
                      message:
                          'Crie um pack para comecar a organizar seus stickers.',
                      actionLabel: 'Criar pack',
                      onAction: () => context.go('/packs/create'),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 28 : AppSpacing.page,
                  0,
                  isWide ? 28 : AppSpacing.page,
                  96,
                ),
                sliver: _SliverConstrainedCrossAxis(
                  maxExtent: 1180,
                  sliver: SliverGrid.builder(
                    itemCount: packs.length,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: isWide ? 360 : 520,
                      mainAxisExtent: 316,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
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
                              const SnackBar(content: Text('Pack removido.')),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CenteredContent extends StatelessWidget {
  const _CenteredContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: child,
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.isWide, required this.onCreate});

  final bool isWide;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sticker Studio', style: theme.textTheme.displayMedium),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Packs organizados, prontos para crescer e ir para o WhatsApp.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
        if (isWide) ...[
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Novo pack'),
          ),
        ],
      ],
    );
  }
}

class _HomeOverview extends StatelessWidget {
  const _HomeOverview({
    required this.isWide,
    required this.totalPacks,
    required this.totalStickers,
    required this.averageStickers,
    required this.onCreate,
  });

  final bool isWide;
  final int totalPacks;
  final int totalStickers;
  final double averageStickers;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: _HeroPanel(totalPacks: totalPacks, onCreate: onCreate),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: _MetricsPanel(
                totalPacks: totalPacks,
                totalStickers: totalStickers,
                averageStickers: averageStickers,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _HeroPanel(totalPacks: totalPacks, onCreate: onCreate),
        const SizedBox(height: 16),
        _MetricsPanel(
          totalPacks: totalPacks,
          totalStickers: totalStickers,
          averageStickers: averageStickers,
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.totalPacks, required this.onCreate});

  final int totalPacks;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF184E77), Color(0xFF35A7A0)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F16425F),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_motion_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              _StatusBadge(
                icon: Icons.inventory_2_outlined,
                label: '$totalPacks packs',
              ),
            ],
          ),
          const SizedBox(height: 28),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'Sua colecao de stickers, com os packs em primeiro plano.',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                height: 1.08,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            totalPacks == 0
                ? 'Comece criando um pack base.'
                : 'Continue lapidando os packs que ja estao no ar.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Criar pack'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF184E77),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({
    required this.totalPacks,
    required this.totalStickers,
    required this.averageStickers,
  });

  final int totalPacks;
  final int totalStickers;
  final double averageStickers;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MetricTile(
          icon: Icons.collections_bookmark_outlined,
          label: 'Packs',
          value: '$totalPacks',
          accentColor: const Color(0xFFFFB703),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: Icons.emoji_emotions_outlined,
                label: 'Stickers',
                value: '$totalStickers',
                accentColor: const Color(0xFF35A7A0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                icon: Icons.query_stats_rounded,
                label: 'Media',
                value: averageStickers.toStringAsFixed(1),
                accentColor: const Color(0xFFFF6B6B),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1A4E93),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 21),
          ),
          const SizedBox(height: 18),
          Text(value, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PacksSectionHeader extends StatelessWidget {
  const _PacksSectionHeader({required this.packCount, required this.onCreate});

  final int packCount;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Biblioteca', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                packCount == 1 ? '1 pack salvo' : '$packCount packs salvos',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Criar pack',
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _SliverConstrainedCrossAxis extends StatelessWidget {
  const _SliverConstrainedCrossAxis({
    required this.maxExtent,
    required this.sliver,
  });

  final double maxExtent;
  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final overflow = constraints.crossAxisExtent - maxExtent;
        final sideInset = overflow > 0 ? overflow / 2 : 0.0;

        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: sideInset),
          sliver: sliver,
        );
      },
    );
  }
}
