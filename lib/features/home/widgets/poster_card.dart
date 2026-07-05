import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/colors.dart';

/// 海报卡片 — 用于海报墙展示
///
/// 支持两种尺寸模式:
/// - 标准 (grid): 16:9 竖版海报, 用于分类网格
/// - 大屏 (featured): 2:3 / 大海报, 用于轮播
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.rating,
    this.width = 100,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final double? rating;
  final double width;
  final VoidCallback? onTap;

  double get _aspectRatio => 2 / 3; // 标准海报比例

  @override
  Widget build(BuildContext context) {
    final height = width / _aspectRatio;
    final scheme = Theme.of(context).colorScheme;
    final tier = context.deviceTier;
    final double titleSize = tier == DeviceTier.tv ? 14 : 12;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 海报图片
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: width,
                height: height,
                color: IptvColors.bgElevated,
                child: (imageUrl != null && imageUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: IptvColors.bgElevated,
                          child: Center(
                            child: Icon(
                              Icons.movie_outlined,
                              size: 32,
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => _Placeholder(),
                      )
                    : _Placeholder(),
              ),
            ),
            const SizedBox(height: 4),
            // 标题
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            // 评分或副标题
            if (rating != null && rating! > 0) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text(
                    rating!.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ] else if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: IptvColors.bgElevated,
      child: Center(
        child: Icon(
          Icons.live_tv,
          size: 28,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// 直播频道专用海报 (带当前节目 EPG)
class LivePosterCard extends StatelessWidget {
  const LivePosterCard({
    super.key,
    required this.title,
    this.logoUrl,
    this.currentProgram,
    this.width = 100,
    this.onTap,
  });

  final String title;
  final String? logoUrl;
  final String? currentProgram;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final height = width / (16 / 9); // 直播用 16:9
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withOpacity(0.3),
                      scheme.primary.withOpacity(0.1),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (logoUrl != null && logoUrl!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: logoUrl!,
                          width: width * 0.4,
                          height: height * 0.4,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => Icon(
                            Icons.tv,
                            size: 32,
                            color: scheme.primary,
                          ),
                        )
                      else
                        Icon(Icons.tv, size: 32, color: scheme.primary),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (currentProgram != null) ...[
              const SizedBox(height: 2),
              Text(
                currentProgram!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
