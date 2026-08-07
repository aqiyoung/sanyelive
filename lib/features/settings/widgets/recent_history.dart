// 最近浏览记录组件.
//
// 横向滚动的卡片列表, 每张卡片显示缩略图 + 标题 + 类型标签 (直播/视频).
// 数据来自 playHistoryProvider.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanyelive/widgets/liquid_glass_container.dart';
import '../../../core/theme/colors.dart';
import '../../../services/playback_history_service.dart';

/// 最近浏览记录: 横向滚动卡片列表.
class RecentHistory extends ConsumerWidget {
  const RecentHistory({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(playHistoryProvider);

    return historyAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return _buildEmptyState(context);
        }

        final display = entries.take(10).toList();

        return Container(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: display.length,
            itemBuilder: (context, index) {
              final entry = display[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _HistoryCard(entry: entry),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      height: 130,
      alignment: Alignment.center,
      child: Text(
        '暂无浏览记录',
        style: TextStyle(
          fontSize: 14,
          color: context.fgMain.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 单张历史记录卡片.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final PlaybackHistoryEntry entry;

  /// 判断记录类型: URL 含直播相关关键词则视为直播, 否则视频.
  bool _isLive(String url) {
    final lower = url.toLowerCase();
    return lower.contains('live') ||
        lower.contains('m3u8') ||
        lower.contains('hls') ||
        lower.contains('rtmp') ||
        lower.contains('migu') ||
        lower.contains('cctv') ||
        lower.contains('iptv');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLive = _isLive(entry.url);
    final typeColor = isLive ? scheme.primary : scheme.error;

    return LiquidGlassContainer(
      variant: LiquidGlassVariant.light,
      borderRadius: 8,
      width: 80,
      specular: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 缩略图.
          Container(
            width: 80,
            height: 64,
            color: context.bgBase.withValues(alpha: 0.3),
            child: entry.posterUrl != null && entry.posterUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: entry.posterUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        _defaultThumbnail(context, typeColor),
                    placeholder: (_, __) =>
                        _defaultThumbnail(context, typeColor),
                  )
                : _defaultThumbnail(context, typeColor),
          ),
          // 标题文字.
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: context.fgMain,
              ),
            ),
          ),
          // 类型标签.
          Container(
            width: 80,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                isLive ? '直播' : '视频',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: typeColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultThumbnail(BuildContext context, Color color) {
    return Center(
      child: Icon(
        Icons.play_circle_outline,
        size: 28,
        color: color.withValues(alpha: 0.4),
      ),
    );
  }
}
