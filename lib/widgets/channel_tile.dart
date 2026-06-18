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
    this.country,
    this.isLive = true,
    this.onTap,
    // P2-3-A (6/18 老板拍): TV 端字号 14sp → 18sp 适配,  3 米可视.
    // null = 使用 IptvTypography.sansTitle 默认 16sp, TV 端可传 18.
    this.fontSizeOverride,
  });

  final String channelNumber;
  final String channelName;
  final Channel? channel;
  final String? country;
  final bool isLive;
  final VoidCallback? onTap;
  final double? fontSizeOverride;

  @override
  Widget build(BuildContext context) {
    // 老板 6/17 需求: 频道名优先用中文, 原名 (英文) 作为副标题.
    // 上层传的 channelName 可能是旧 name, 这里从 channel 重新取
    // displayName + displaySubtitle 兑底.
    final primaryName = channel?.displayName ?? channelName;
    final subtitle = channel?.displaySubtitle;
    // favorite icon 仍然要 iptv org 原名 (作 channelName)
    final favName = channel?.name ?? channelName;

    return Material(
      color: IptvColors.bgElevated,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: IptvColors.dividerWarm, width: 1),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  channelNumber,
                  style: IptvTypography.serifTitle.copyWith(
                    color: IptvColors.accentTerracotta,
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
                      style: IptvTypography.sansTitle.copyWith(
                        // P2-3-A: TV 端 16sp → 18sp,  3 米可视.
                        fontSize: fontSizeOverride ?? 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 原名作为副标题 (有差异才显示)
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: IptvTypography.caption.copyWith(
                          color: IptvColors.textSecondary,
                          // P2-3-A: TV 端 12sp → 14sp,  跟主标题比例一致.
                          fontSize: fontSizeOverride != null
                              ? fontSizeOverride! - 4
                              : 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (country != null && country!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        country!,
                        style: IptvTypography.caption.copyWith(
                          fontSize: fontSizeOverride != null
                              ? fontSizeOverride! - 4
                              : 12,
                        ),
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
                    color: IptvColors.accentTerracotta,
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
