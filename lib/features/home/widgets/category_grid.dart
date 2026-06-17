import 'package:flutter/material.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/tv/tv_focus.dart';
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
            // 6/17 v0.2.3 P1-5: TV 端套 TvFocus 拿焦点环,  手机端原
            // InkWell 不受影响 (TvFocus 内部是 Focus + GestureDetector,  不
            // 拦截 touch 事件).
            final isTv = context.deviceTier == DeviceTier.tv;
            final card = CategoryCard(
              title: item.title,
              subtitle: item.subtitle,
              icon: item.icon,
              onTap: onItemTap == null ? null : () => onItemTap!(item),
            );
            if (!isTv) return card;
            return TvFocus(
              // 6/17: 第一个卡片 autofocus,  TV 端进去就高亮
              autofocus: i == 0,
              onTap: onItemTap == null ? null : () => onItemTap!(item),
              borderRadius: 16,
              child: card,
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
    // 6/17 (UI 优化) 原 1/6 屏高, 厊 logo 56 + padding 20 + 3 行文字
    // 显得太抢眼.  厊到 1/8 屏高: logo 40, padding 14,
    // 删掉 subtitle 文字, 'continue watching' label 和 channelName 合并到
    // 一行 (用 ' · ' 分隔).
    // 6/17 v0.2.3 P1-5: TV 端套 TvFocus 拿焦点环,  手机端原 InkWell 不变.
    final isTv = context.deviceTier == DeviceTier.tv;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: isTv
          ? TvFocus(
              onTap: onTap,
              borderRadius: 14,
              child: _buildContent(),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Material(
      color: IptvColors.accentTerracotta,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: channelLogo != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          channelLogo!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _defaultIcon(),
                        ),
                      )
                    : _defaultIcon(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '继续观看  ·  $channelName',
                  style: IptvTypography.sansTitle.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClear != null)
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 18,
                  ),
                  onPressed: onClear,
                  tooltip: '清除记录',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
  }
}
