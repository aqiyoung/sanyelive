import 'package:flutter/material.dart';

import 'package:sanyelive/widgets/channel_logo.dart';
import 'package:sanyelive/widgets/liquid_glass_container.dart';
import '../../../core/theme/typography.dart';
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
        // 纯台标卡片: 高度与卡片高度一致 (88), 包 ClipRect + Material 防 ripple 漏出.
        ClipRect(
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              height: 88,
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
      borderRadius: BorderRadius.circular(16),
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.light,
        borderRadius: 16,
        width: 88,
        padding: const EdgeInsets.all(14),
        tint: isNext ? Theme.of(context).colorScheme.primary : null,
        child: Center(
          child: ChannelLogo(
            channel: channel,
            size: 52,
            shadow: true,
          ),
        ),
      ),
    );
  }
}
