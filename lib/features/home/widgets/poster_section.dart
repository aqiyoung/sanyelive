import 'package:flutter/material.dart';

import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/theme/typography.dart';

/// 海报分类段 — 横向滑动列表 + 分类标题
class PosterSection extends StatelessWidget {
  const PosterSection({
    super.key,
    required this.title,
    required this.items,
    this.onSeeAll,
    this.itemWidth = 100,
  });

  final String title;
  final List<Widget> items;
  final VoidCallback? onSeeAll;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final tier = context.deviceTier;
    final crossAxisCount = switch (tier) {
      DeviceTier.phone => 4,
      DeviceTier.tablet => 6,
      DeviceTier.tv => 8,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: IptvTypography.serifTitle.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Row(
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 横滑列表
        SizedBox(
          height: itemWidth / (16 / 9) + 40, // 图片高度 + 文字高度
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: itemWidth,
              child: items[i],
            ),
          ),
        ),
      ],
    );
  }
}

/// 海报网格 (非横滑, 用 GridView)
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.items,
    this.crossAxisCount = 4,
    this.childAspectRatio = 0.7,
  });

  final List<Widget> items;
  final int crossAxisCount;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}
