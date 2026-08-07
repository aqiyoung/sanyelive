import 'package:flutter/material.dart';

import 'package:sanyelive/widgets/liquid_glass_container.dart';
import '../core/theme/typography.dart';
// 没有装饰).  改用 bgElevated 浅一档米色 + 圆角 16 显出容器.

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
    return LiquidGlassContainer(
      variant: LiquidGlassVariant.light,
      borderRadius: 16,
      padding: const EdgeInsets.all(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
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
    );
  }
}
