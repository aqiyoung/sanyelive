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
  });

  final String channelNumber;
  final String channelName;
  final Channel? channel;
  final String? country;
  final bool isLive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
                    Text(channelName, style: IptvTypography.sansTitle),
                    if (country != null && country!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(country!, style: IptvTypography.caption),
                    ],
                  ],
                ),
              ),
              if (channel != null)
                FavoriteIcon(
                  channelId: channel!.id,
                  channelName: channel!.name,
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
