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
                  child: _PacksSectionHeader(
                    packCount: packs.length,
                    isWide: isWide,
                    onCreate: () => context.go('/packs/create'),
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
                      mainAxisExtent: 260,
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

class _PacksSectionHeader extends StatelessWidget {
  const _PacksSectionHeader({
    required this.packCount,
    required this.isWide,
    required this.onCreate,
  });

  final int packCount;
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
              Text('Biblioteca', style: theme.textTheme.displayMedium),
              const SizedBox(height: 4),
              Text(
                packCount == 0
                    ? 'Nenhum pack salvo'
                    : packCount == 1
                    ? '1 pack salvo'
                    : '$packCount packs salvos',
                style: theme.textTheme.bodyMedium,
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
