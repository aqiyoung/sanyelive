import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../widgets/serif_headline.dart';
import 'widgets/category_grid.dart';

/// 主页 — 3 大分类 (央视/卫视/地方) + 上次观看 CTA
class HomePage extends ConsumerWidget {
  const HomePage({super.key, this.lastChannelId, this.onClearLastWatched});

  /// 上次观看的频道 ID — 由卡 6 注入 (此处只展示 CTA, 不持久化)
  final String? lastChannelId;
  final VoidCallback? onClearLastWatched;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncChannels = ref.watch(channelsProvider);

    return Scaffold(
      body: SafeArea(
        child: asyncChannels.when(
          loading: () => const _LoadingState(),
          error: (e, _) => _ErrorState(message: e.toString()),
          data: (channels) => _buildContent(context, channels),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Channel> all) {
    // 派生 3 大分类 — 主页是「容器」, 分类页是「真实列表」
    // 卡 6 会做收藏/历史; 此处只读 lastChannelId
    final cctv = _filterCctv(all).length;
    final satellite = _filterSatellite(all).length;
    final local = all.length - cctv - satellite;

    const items = [
      CategoryItem(
        id: 'cctv',
        title: '央视',
        subtitle: 'CCTV-1 ~ CCTV-16',
        icon: Icons.tv,
      ),
      CategoryItem(
        id: 'satellite',
        title: '卫视',
        subtitle: '省级卫视 + 上星频道',
        icon: Icons.public,
      ),
      CategoryItem(
        id: 'local',
        title: '地方',
        subtitle: '省市地方台',
        icon: Icons.location_city,
      ),
    ];

    // 找上次的频道 (轻量查找, 500 条不算多)
    final lastChannel = lastChannelId == null
        ? null
        : all.where((c) => c.id == lastChannelId).cast<Channel?>().firstOrNull;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AppHeader(),
              // 上次观看 (有记录才显示)
              if (lastChannel != null) ...[
                ContinueWatchingCard(
                  channelName: lastChannel.name,
                  channelLogo: lastChannel.logoUrl,
                  subtitle: '继续播放',
                  onTap: () => context.push('/player/${lastChannel.id}'),
                  onClear: onClearLastWatched,
                ),
                const SizedBox(height: 24),
              ],
              const SerifHeadline(
                '频道分类',
                subtitle: '7,800+ 频道 · iptv-org 数据源',
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: CategoryGrid(
            items: items,
            onItemTap: (item) {
              final count = switch (item.id) {
                'cctv' => cctv,
                'satellite' => satellite,
                'local' => local,
                _ => 0,
              };
              context.push(
                '/category/${item.id}?title=${Uri.encodeComponent(item.title)}',
                extra: count,
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '设计系统: 新中式 · 暖米 · 衬线标题',
              style: IptvTypography.caption,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // 央视: id 以 CCTV 开头 (CCTV1.cn, CCTVPlus1.cn, CCTVBilliards.cn 等)
  static List<Channel> _filterCctv(List<Channel> all) {
    return all
        .where((c) => c.id.startsWith(RegExp(r'CCTV', caseSensitive: false)))
        .toList();
  }

  // 卫视: id 包含 SatelliteTV / TVInternational
  static List<Channel> _filterSatellite(List<Channel> all) {
    const patterns = ['SatelliteTV', 'TVInternational'];
    return all.where((c) {
      for (final p in patterns) {
        if (c.id.contains(p)) return true;
      }
      return false;
    }).toList();
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: IptvColors.accentTerracotta,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.live_tv,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '三页直播',
            style: IptvTypography.serifTitle,
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(
          color: IptvColors.accentTerracotta,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: IptvColors.accentTerracotta,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            '加载频道失败',
            style: IptvTypography.serifTitle,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: IptvTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
