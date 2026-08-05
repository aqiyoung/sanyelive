import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/typography.dart';
import '../data/models/channel.dart';
import '../features/favorites/favorite_button.dart';

/// 频道整行 tile — 用于频道列表
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channelNumber,
    required this.channelName,
    this.channel,
    this.isLive = true,
    this.onTap,
  });

  final String channelNumber;
  final String channelName;
  final Channel? channel;
  final bool isLive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 上层传的 channelName 可能是旧 name, 这里从 channel 重新取
    // displayName + displaySubtitle 兑底.
    final primaryName = channel?.displayName ?? channelName;
    final subtitle = channel?.displaySubtitle;
    // favorite icon 仍然要 iptv org 原名 (作 channelName)
    final favName = channel?.name ?? channelName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          // (浅一档米色 + 圆角 12),  外层 list 用 SizedBox 间隔.  之前是 list+
          // divider 风格,  +99/+100 删了 border 和 Divider,  但视觉上
          // Scaffold 背景 (bgParchment #F5F4ED) 区分,  让用户"看得出来是
          // 容器".  跟 settings page 的 _SettingsCard 是同一套语言.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? IptvColors.darkSurface
                : IptvColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  channelNumber,
                  style: IptvTypography.serifTitle.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryName,
                      style: Theme.of(context).textTheme.titleMedium ?? IptvTypography.sansTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 副标题: 显示分类名 (中文)
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: IptvTypography.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (channel != null)
                FavoriteIcon(
                  channelId: channel!.id,
                  channelName: favName,
                  size: 20,
                ),
              if (isLive)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
