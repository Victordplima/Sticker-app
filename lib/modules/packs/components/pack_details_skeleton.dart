import 'package:flutter/material.dart';

import '../../../shared/widgets/skeleton_box.dart';

/// Exibido na [PackDetailsScreen] enquanto os dados do pack ainda estão
/// sendo carregados pelo [packsControllerProvider].
class PackDetailsSkeleton extends StatelessWidget {
  const PackDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SkeletonBox(height: 20, width: 140, borderRadius: 8),
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
              // Hero card do pack
              _HeroCardSkeleton(),
              const SizedBox(height: 24),
              // Botões de ação
              const _ActionButtonsSkeleton(),
              const SizedBox(height: 24),
              // Título "Preview do pack"
              SkeletonBox(height: 26, width: 180, borderRadius: 8),
              const SizedBox(height: 12),
              // Grid de sticker tiles skeleton
              GridView.builder(
                itemCount: 6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (_, i) => const _StickerTileSkeleton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButtonsSkeleton extends StatelessWidget {
  const _ActionButtonsSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return const Column(
            children: [
              SkeletonBox(height: 54, borderRadius: 16),
              SizedBox(height: 12),
              SkeletonBox(height: 54, borderRadius: 16),
            ],
          );
        }

        return const Row(
          children: [
            Expanded(child: SkeletonBox(height: 54, borderRadius: 16)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 54, borderRadius: 16)),
          ],
        );
      },
    );
  }
}

class _HeroCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
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
          SkeletonBox(height: 30, width: 200, borderRadius: 8),
          const SizedBox(height: 10),
          SkeletonBox(height: 16, width: 160, borderRadius: 6),
          const SizedBox(height: 20),
          SkeletonBox(height: 36, width: 110, borderRadius: 99),
        ],
      ),
    );
  }
}

class _StickerTileSkeleton extends StatelessWidget {
  const _StickerTileSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          Expanded(child: SkeletonBox(borderRadius: 16)),
          const SizedBox(height: 10),
          SkeletonBox(height: 28, width: 28, borderRadius: 8),
          const SizedBox(height: 8),
          SkeletonBox(height: 22, width: 60, borderRadius: 99),
        ],
      ),
    );
  }
}
