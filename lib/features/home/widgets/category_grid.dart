import 'package:flutter/material.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../widgets/category_card.dart';

/// 主页 3 大分类卡片的自适应网格
///   - 手机 (≤600dp)  : 2 列 (1 张独占 + 2 列布局) — 实际上 3 卡 → 顶部 1 张 + 下方 2 列
///   - 平板 (601-1024dp): 3 列
///   - TV  (>1024dp) : 5 列 (1 张大 + 4 张小, 或全部 5 列, 由条目数决定)
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.items,
    this.onItemTap,
  });

  final List<CategoryItem> items;
  final void Function(CategoryItem item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    final tier = context.deviceTier;
    final crossAxisCount = _columnsFor(tier, items.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: _spacingFor(tier),
            crossAxisSpacing: _spacingFor(tier),
            // 手机给卡片更高一些, 容纳 subtitle; TV/平板可以更扁
            childAspectRatio: _aspectRatioFor(tier),
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            return CategoryCard(
              title: item.title,
              subtitle: item.subtitle,
              icon: item.icon,
              onTap: onItemTap == null ? null : () => onItemTap!(item),
            );
          },
        );
      },
    );
  }

  /// 3 张卡片:
  ///   - phone  → 2 (顶部 1 + 底部 2 列, 视觉更平衡; 但 grid 强制 N 列, 我们用 1 + 2 行用 Wrap 模拟)
  ///   - tablet → 3
  ///   - tv     → 3
  /// 为简化, 我们在 phone 模式特殊处理: 用 Column 1+2 而不是 GridView.
  int _columnsFor(DeviceTier tier, int count) {
    switch (tier) {
      case DeviceTier.phone:
        return 2;
      case DeviceTier.tablet:
        return 3;
      case DeviceTier.tv:
        return count >= 5 ? 5 : 3;
    }
  }

  double _spacingFor(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.phone:
        return 12;
      case DeviceTier.tablet:
        return 16;
      case DeviceTier.tv:
        return 20;
    }
  }

  double _aspectRatioFor(DeviceTier tier) {
    // 高/宽比例; 值越小 → 卡片越扁宽
    switch (tier) {
      case DeviceTier.phone:
        return 1.3; // 竖屏手机 2 列: 每张卡片稍矮以容纳 subtitle
      case DeviceTier.tablet:
        return 1.3; // 平板 3 列, 卡片较扁, 远距离看也清晰
      case DeviceTier.tv:
        return 1.2; // TV 远距离观看, 卡片更宽矮
    }
  }
}

/// 分类条目数据 (纯数据, 主页 3 大分类用)
class CategoryItem {
  const CategoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  /// 路由参数: cctv / satellite / local
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

/// 顶部 banner / 上次观看 CTA 卡片
/// 独立组件, 不属于 grid.
class ContinueWatchingCard extends StatelessWidget {
  const ContinueWatchingCard({
    super.key,
    required this.channelName,
    required this.channelLogo,
    this.subtitle,
    this.onTap,
    this.onClear,
  });

  final String channelName;
  final String? channelLogo;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: IptvColors.accentTerracotta,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // 左侧 logo / 播放图标
                SizedBox(
                  width: 56,
                  height: 56,
                  child: channelLogo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          // FIX 容器超出: 限定 logo 最大尺寸, 防止上游传超大 URL
                          // 撑爆布局.  Fit cover + 固定 box.
                          child: Image.network(
                            channelLogo!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultIcon(),
                          ),
                        )
                      : _defaultIcon(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '继续观看',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        channelName,
                        style: IptvTypography.serifTitle.copyWith(
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Flexible(
                          child: Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: onClear,
                    tooltip: '清除记录',
                    // FIX 容器超出: 限定 IconButton padding, 默认 48dp
                    // 会挤压文字.  用 visualDensity 缩减, 保留可点击区.
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _defaultIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 32,
      ),
    );
  }
}
