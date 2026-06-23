import 'package:flutter/material.dart';

import '../../../core/utils/app_spacing.dart';
import '../../../shared/widgets/skeleton_box.dart';

class PacksListSkeleton extends StatelessWidget {
  const PacksListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        return CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _CenteredSkeleton(
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
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(
                                  height: 38,
                                  width: 220,
                                  borderRadius: 8,
                                ),
                                SizedBox(height: 10),
                                SkeletonBox(height: 16, borderRadius: 8),
                                SizedBox(height: 6),
                                SkeletonBox(
                                  height: 16,
                                  width: 300,
                                  borderRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          if (isWide) ...[
                            const SizedBox(width: 16),
                            const SkeletonBox(
                              height: 46,
                              width: 136,
                              borderRadius: 8,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.section),
                      _OverviewSkeleton(isWide: isWide),
                      const SizedBox(height: AppSpacing.section),
                      Row(
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(
                                height: 28,
                                width: 150,
                                borderRadius: 8,
                              ),
                              SizedBox(height: 8),
                              SkeletonBox(
                                height: 16,
                                width: 110,
                                borderRadius: 8,
                              ),
                            ],
                          ),
                          const Spacer(),
                          SkeletonBox(height: 40, width: 40, borderRadius: 8),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                  itemCount: isWide ? 6 : 3,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isWide ? 360 : 520,
                    mainAxisExtent: 316,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemBuilder: (_, i) => const _PackCardSkeleton(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CenteredSkeleton extends StatelessWidget {
  const _CenteredSkeleton({required this.child});

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

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final hero = const SkeletonBox(height: 270, borderRadius: 8);
    final metrics = const Column(
      children: [
        SkeletonBox(height: 130, borderRadius: 8),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 128, borderRadius: 8)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 128, borderRadius: 8)),
          ],
        ),
      ],
    );

    if (isWide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 6, child: hero),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: metrics),
          ],
        ),
      );
    }

    return Column(children: [hero, const SizedBox(height: 16), metrics]);
  }
}

class _PackCardSkeleton extends StatelessWidget {
  const _PackCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: const Padding(
        padding: EdgeInsets.all(16),
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
                      SkeletonBox(height: 22, width: 160, borderRadius: 8),
                      SizedBox(height: 6),
                      SkeletonBox(height: 16, width: 100, borderRadius: 8),
                    ],
                  ),
                ),
                SkeletonBox(width: 40, height: 40, borderRadius: 8),
              ],
            ),
            SizedBox(height: 12),
            SkeletonBox(height: 112, borderRadius: 8),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SkeletonBox(height: 32, width: 58, borderRadius: 99),
                SkeletonBox(height: 32, width: 58, borderRadius: 99),
                SkeletonBox(height: 32, width: 58, borderRadius: 99),
              ],
            ),
          ],
        ),
      ),
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
