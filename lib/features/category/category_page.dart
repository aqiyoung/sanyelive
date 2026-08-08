import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/typography.dart';
import '../../core/tv/tv_focus.dart';
import '../../data/channel_filter.dart';
import '../../data/province_util.dart' show sortSatelliteByProvince;
import '../../features/settings/province_provider.dart' show provinceProvider;
import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../widgets/channel_tile.dart';

/// 分类页 — 显示某分类下所有频道 (整行 tile 列表)
class CategoryPage extends ConsumerWidget {
  const CategoryPage({
    super.key,
    required this.categoryId,
    this.title,
  });

  /// 路由参数: cctv / satellite / local
  final String categoryId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncChannels = ref.watch(channelsStreamProvider);

    return Scaffold(
      body: SafeArea(
        child: asyncChannels.when(
          loading: () => const _LoadingState(),
          error: (e, _) => _ErrorState(message: e.toString()),
          data: (channels) => _buildContent(context, ref, channels),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, List<Channel> all) {
    final province = ref.watch(provinceProvider);
    final filtered = _filter(all, province);
    final displayTitle = title ?? _defaultTitle();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackBar(
                title: displayTitle,
                count: filtered.length,
                onBack: () => context.pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else if (categoryId == 'live')
          ..._buildGroupedSections(context, filtered)
        else
          Builder(
            builder: (context) {
              final isTv = context.deviceTier == DeviceTier.tv;
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final ch = filtered[i];
                    final tile = ChannelTile(
                      channel: ch,
                      channelNumber: (i + 1).toString().padLeft(2, '0'),
                      channelName: ch.name,
                      isLive: ch.sources.isNotEmpty,
                      onTap: () => context.push('/player/${ch.id}'),
                    );
                    final wrapped = Padding(
                      padding: EdgeInsets.only(
                        bottom: i == filtered.length - 1 ? 0 : 10,
                      ),
                      child: tile,
                    );
                    if (!isTv) return wrapped;
                    return TvFocus(
                      autofocus: i == 0,
                      onTap: () => context.push('/player/${ch.id}'),
                      borderRadius: 12,
                      child: wrapped,
                    );
                  },
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _buildGroupedSections(BuildContext context, List<Channel> all) {
    // 按 primaryCategory 分组, 保持插入顺序
    final order = <String>[];
    final groups = <String, List<Channel>>{};
    for (final ch in all) {
      final cat = ch.primaryCategory;
      if (!groups.containsKey(cat)) {
        order.add(cat);
        groups[cat] = [];
      }
      groups[cat]!.add(ch);
    }

    final isTv = context.deviceTier == DeviceTier.tv;
    final slivers = <Widget>[];

    for (final cat in order) {
      final items = groups[cat]!;
      // 分组标题
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              cat,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      );
      // 分组频道列表
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final ch = items[i];
              final tile = ChannelTile(
                channel: ch,
                channelNumber: (i + 1).toString().padLeft(2, '0'),
                channelName: ch.name,
                isLive: ch.sources.isNotEmpty,
                onTap: () => context.push('/player/${ch.id}'),
              );
              final wrapped = Padding(
                padding: EdgeInsets.only(
                  bottom: i == items.length - 1 ? 0 : 10,
                ),
                child: tile,
              );
              if (!isTv) return wrapped;
              return TvFocus(
                autofocus: i == 0,
                onTap: () => context.push('/player/${ch.id}'),
                borderRadius: 12,
                child: wrapped,
              );
            },
          ),
        ),
      );
    }

    return slivers;
  }

  List<Channel> _filter(List<Channel> all, String? province) {
    switch (categoryId) {
      case 'live':
        return all
            .where((ch) =>
                ch.sources.isNotEmpty &&
                (ch.primaryCategory == '央视' ||
                    ch.primaryCategory == '卫视' ||
                    ch.primaryCategory == '体育' ||
                    ch.primaryCategory == '地方' ||
                    ch.primaryCategory == '影视' ||
                    ch.primaryCategory == '新闻' ||
                    ch.primaryCategory == '娱乐'))
            .toList();
      case 'cctv':
        return ChannelFilter.cctv(all);
      case 'satellite':
        // 定位: 当前省份的卫视排到最前.
        return sortSatelliteByProvince(ChannelFilter.satellite(all), province);
      case 'local':
        return ChannelFilter.local(all);
      case 'international':
        return ChannelFilter.international(all);
      default:
        return ChannelFilter.byCategory(all, categoryId);
    }
  }

  String _defaultTitle() {
    switch (categoryId) {
      case 'live':
        return '电视直播';
      case 'cctv':
        return '央视';
      case 'satellite':
        return '卫视';
      case 'local':
        return '地方';
      case 'international':
        return '国际';
      case '新闻':
        return '新闻';
      case '影视':
        return '影视';
      case '少儿':
        return '少儿';
      case '体育':
        return '体育';
      case '科教':
        return '科教';
      case '娱乐':
        return '娱乐';
      case '财经':
        return '财经';
      default:
        return '频道';
    }
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({
    required this.title,
    required this.count,
    required this.onBack,
  });

  final String title;
  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                )),
                Text(
                  '共 $count 个频道',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
    return Center(
      child: CircularProgressIndicator(
        color: Theme.of(context).colorScheme.primary,
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
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text('加载失败', style: IptvTypography.serifTitle),
            const SizedBox(height: 8),
            Text(message,
                style: IptvTypography.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text('该分类暂无频道', style: IptvTypography.serifTitle),
          ],
        ),
      ),
    );
  }
}

// 播放页 failover 多个候选源尝试.
