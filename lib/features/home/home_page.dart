import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/channel_filter.dart';
import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../services/startup_service.dart';
import '../../widgets/serif_headline.dart';
import 'widgets/category_grid.dart';

/// 主页 — 3 大分类 (央视/卫视/地方) + 上次观看 CTA + 搜索入口
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.onClearLastWatched});

  /// 清除上次观看的回调 (留给父级实现)
  final VoidCallback? onClearLastWatched;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String? _lastChannelId;

  @override
  void initState() {
    super.initState();
    _loadLastChannel();
  }

  Future<void> _loadLastChannel() async {
    final svc = ref.read(startupServiceProvider);
    final id = await svc.loadLastChannel();
    if (mounted) setState(() => _lastChannelId = id);
  }

  Future<void> _clearLast() async {
    final svc = ref.read(startupServiceProvider);
    await svc.clearLastChannel();
    if (mounted) setState(() => _lastChannelId = null);
    widget.onClearLastWatched?.call();
  }

  @override
  Widget build(BuildContext context) {
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
    final cctv = ChannelFilter.cctv(all).length;
    final satellite = ChannelFilter.satellite(all).length;
    final local = all.length - cctv - satellite;

    const items = [
      CategoryItem(
        id: 'cctv',
        title: '央视',
        subtitle: 'CCTV 频道',
        icon: Icons.tv,
      ),
      CategoryItem(
        id: 'satellite',
        title: '卫视',
        subtitle: '省级卫视',
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
    final lastChannel = _lastChannelId == null
        ? null
        : all.where((c) => c.id == _lastChannelId).cast<Channel?>().firstOrNull;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AppHeader(
                onSearchTap: () => context.go('/search'),
              ),
              // 上次观看 (有记录才显示)
              if (lastChannel != null) ...[
                ContinueWatchingCard(
                  channelName: lastChannel.displayName,
                  channelLogo: lastChannel.logoUrl,
                  subtitle: '继续播放',
                  onTap: () => context.push('/player/${lastChannel.id}'),
                  onClear: _clearLast,
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
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({this.onSearchTap});

  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
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
            'Threelive',
            style: IptvTypography.serifTitle,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search),
            color: IptvColors.textPrimary,
            tooltip: '搜索频道',
            onPressed: onSearchTap,
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
