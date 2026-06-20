import 'package:flutter/material.dart';

import '../../../core/theme/typography.dart';
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
              // 6/18 v0.3.6.1 hotfix: textSecondary → onSurfaceVariant
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
                    index: i,
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
    required this.index,
    required this.isNext,
    required this.onTap,
  });

  final Channel channel;
  final int index;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 116,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          // 6/17 (反色看不清): 之前 isNext 用 terracotta.withOpacity(0.12)
          // 配 textPrimary,  在 player 页 (黑底 Scaffold) 上实际渲染成
          // 近黑底 + 深棕字,  对比度严重不足 (WCAG AA 需 4.5:1).
          // 改为 bgElevated 暖米底 + 2dp 砖红边框 + 砖红数字/源点 +
          // 文字保持 textPrimary,  整 chip 跟非选中态区分靠边框粗细 + 数字
          // 颜色 + 字重,  选中态对比度 ≥ 4.5:1 (黑字 #2A2520 on 暖米 #FFFCF6
          // ≈ 13:1).
          // v0.3.8+99 (6/20 14:03 老板反馈): 删边框线.
          // 之前选中态用 2dp primary 边框区分,  非选中用 0.5dp outlineVariant.
          // 现在改成靠背景色区分:
          //   - 选中 (isNext): bgElevated + primary 数字 + bold
          //   - 非选中: surface + outline 数字 + regular
          // 效果跟有边框等价但更极简.
          color: isNext
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(
                  (index + 1).toString().padLeft(2, '0'),
                  // 6/17 修: 软包禁 + maxLines=1, 防止 01 在某些字体下被
                  // 截到 chip 边缘外造成“超出容器”错觉
                  maxLines: 1,
                  softWrap: false,
                  style: IptvTypography.caption.copyWith(
                    color: isNext
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    channel.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IptvTypography.body.copyWith(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: isNext ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (channel.sources.isNotEmpty)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    );
  }
}
