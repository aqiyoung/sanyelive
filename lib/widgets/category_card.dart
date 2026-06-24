import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/typography.dart';
// v0.3.8+103 (6/20 15:46 老板反馈): 不用 GlassCardBorder (只画背景色,
// 没有装饰).  改用 bgElevated 浅一档米色 + 圆角 16 显出容器.

/// 主页大分类卡片 — 大圆角 + Terracotta 渐变背景 + 轻玻璃白边 (P1-1)
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      // v0.3.8+103 (6/20 15:46 老板反馈): CategoryCard bg 改 bgElevated.
      // 之前 +99/+100 删了 border, 但 CategoryCard bg 跟 Scaffold 同色
      // (surface = bgParchment),  老板装 +101 看到 "平面显示看不出来".
      // 现在跟 ChannelTile 同样模式: 浅一档米色 + 圆角 16 让"一眼能看出
      // 是独立容器".
      color: IptvColors.bgElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: Theme.of(context).colorScheme.primary, size: 22),
              ),
              const SizedBox(height: 12),
              Text(title, style: IptvTypography.serifTitle),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: IptvTypography.caption.copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
