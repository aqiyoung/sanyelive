import 'package:flutter/material.dart';

import 'package:sanyelive/widgets/channel_logo.dart';
import 'package:sanyelive/widgets/liquid_glass_container.dart';
import '../../../core/theme/typography.dart';
// 主题联动).  theme_tokens_test.dart 严格 grep 不许硬编颜色常量.
import '../../../data/category_zh.dart';
import '../../../data/models/channel.dart';

/// "下一频道" 横滑条
///   - 列出当前播放频道之后的 10 个频道 (按列表顺序)
///   - 点击切台 (调用 onChannelTap)
///   - 第一个高亮 "下一频道" 角标
class NextChannelsStrip extends StatelessWidget {
  const NextChannelsStrip({
    super.key,
    required this.currentChannelId,
    required this.allChannels,
    required this.onChannelTap,
    this.max = 10,
  });

  final String currentChannelId;
  final List<Channel> allChannels;
  final void Function(Channel channel) onChannelTap;
  final int max;

  @override
  Widget build(BuildContext context) {
    // 找到当前位置, 之后的频道
    final idx = allChannels.indexWhere((c) => c.id == currentChannelId);
    final after = idx >= 0 ? allChannels.sublist(idx + 1) : const <Channel>[];

    // 如果后续不够 max, 拼上开头的循环 (避免空条)
    final List<Channel> next = [...after];
    final seenIds = <String>{for (final c in next) c.id, currentChannelId};
    var i = 0;
    while (next.length < max && i < allChannels.length) {
      final c = allChannels[i];
      if (seenIds.add(c.id)) {
        next.add(c);
      }
      i++;
    }
    final visible = next.take(max).toList();

    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            '下一频道',
            style: IptvTypography.caption.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 6/17 修容器超出: 包一层 ClipRect + Material 防止 InkWell ripple
        // 漏到 strip 外面 / chip 内部文字被截断时闪出 container 边界.
        //  高度从 78 → 84 防止双行文字+padding 在某些字号下被压到.
        ClipRect(
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                // physics: BouncingScrollPhysics 让横滑手感跟 iOS 一致,
                // 不被夹在 SingleChildScrollView 里变成无弹性的拖动
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final ch = visible[i];
                  return _ChannelChip(
                    channel: ch,
                    isNext: i == 0,
                    onTap: () => onChannelTap(ch),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.channel,
    required this.isNext,
    required this.onTap,
  });

  final Channel channel;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.light,
        borderRadius: 10,
        width: 118,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tint: isNext ? Theme.of(context).colorScheme.primary : null,
        child: Row(
          children: [
            // 频道台标：带形状投影，与首页卡片风格一致
            ChannelLogo(
              channel: channel,
              size: 28,
              shadow: true,
              bright: false,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    channel.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IptvTypography.body.copyWith(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: channel.sources.isNotEmpty
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          categoryZh(channel.primaryCategory),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IptvTypography.caption.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
