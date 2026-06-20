import 'package:flutter/material.dart';

import '../../../core/theme/typography.dart';
// v0.3.8+105 (6/20): 删硬编颜色常量 import (改用 Theme token,  跟
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
        // v0.3.8+104 (6/20 15:36 老板反馈): chip 宽度 116→108,  让
        // 02/03 频道名能显示完整.  之前 116px 装下 "CCTV+ 1 (1.0)" 还够,
        // 但 "CCTV-1 综合" 被截.  现在 108 + 字号 12,  80% 频道能装下.
        width: 108,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          // v0.3.8+104: 统一所有 chip bg,  选中和非选中区别靠 bg 色.
          // 之前选中: surfaceContainerHighest (白,  跟黑底 scaffold 获眼
          // "白卡浮起");  非选中: surface (米色,  跟黑底反差小).
          // 现在所有 chip = bgElevated 浅一档米色 (#FFFCF6) — 统一
          // 容器.  选中加 accent 0.12α 浅红 overlay 表示"下一频道".
          // v0.3.8+105 (6/20 老板反馈 CI 红了): 改用 Theme token.
          // 之前 v0.3.8+104 用硬编颜色常量, 触发
          // theme_tokens_test.dart (v0.3.7+50) fail.  bgElevated 在
          // ColorScheme 里对应的 token 是 surfaceContainerHighest
          // (theme.dart: 16 行).  走 token 后主题变化能自动联动.
          color: isNext
              ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  // 截到 chip 边缘外造成"超出容器"错觉
                  maxLines: 1,
                  softWrap: false,
                  // v0.3.8+104: 数字全部 primary + w700 统一,  不靠 isNext
                  // 区分.  选中态靠 chip bg (accent 0.12α) 区分.
                  style: IptvTypography.caption.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    channel.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // v0.3.8+104: 字号 13→12 让 02/03 频道名装下.
                    // 之前 13 字号 108 宽 chip 装不下 "CCTV-1 综合" (5 汉字).
                    style: IptvTypography.body.copyWith(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
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
