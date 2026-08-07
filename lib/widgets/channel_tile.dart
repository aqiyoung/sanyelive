import 'package:flutter/material.dart';

import 'package:sanyelive/widgets/liquid_glass_container.dart';
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

    return LiquidGlassContainer(
      variant: LiquidGlassVariant.light,
      borderRadius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
