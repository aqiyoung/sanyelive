import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
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
    final filtered = _filter(all);
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
        else
          SliverList.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final ch = filtered[i];
              return ChannelTile(
                channelNumber: (i + 1).toString().padLeft(2, '0'),
                channelName: ch.name,
                country: ch.country,
                isLive: ch.sources.isNotEmpty,
                onTap: () => context.push('/player/${ch.id}'),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Channel> _filter(List<Channel> all) {
    switch (categoryId) {
      case 'cctv':
        return HomePageFilter.cctv(all);
      case 'satellite':
        return HomePageFilter.satellite(all);
      case 'local':
        return HomePageFilter.local(all);
      default:
        return all;
    }
  }

  String _defaultTitle() {
    switch (categoryId) {
      case 'cctv':
        return '央视';
      case 'satellite':
        return '卫视';
      case 'local':
        return '地方';
      default:
        return '频道';
    }
  }
}

/// 把 HomePage 的私有 filter 暴露给 CategoryPage 用
/// (避免循环 import: home → category_grid → home)
class HomePageFilter {
  HomePageFilter._();

  static List<Channel> cctv(List<Channel> all) {
    return all
        .where((c) => c.id.startsWith(RegExp(r'CCTV', caseSensitive: false)))
        .toList();
  }

  static List<Channel> satellite(List<Channel> all) {
    // iptv-org 模式: 省级卫视的 id 都包含 SatelliteTV / TVInternational
    // 例: BeijingSatelliteTV.cn, HunanTVInternational.cn
    const patterns = ['SatelliteTV', 'TVInternational'];
    return all.where((c) {
      for (final p in patterns) {
        if (c.id.contains(p)) return true;
      }
      return false;
    }).toList();
  }

  static List<Channel> local(List<Channel> all) {
    final sat = satellite(all).map((e) => e.id).toSet();
    final cctvIds = cctv(all).map((e) => e.id).toSet();
    return all
        .where((c) => !sat.contains(c.id) && !cctvIds.contains(c.id))
        .toList();
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
            color: IptvColors.textPrimary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: IptvTypography.serifHeadline),
                Text(
                  '共 $count 个频道',
                  style: IptvTypography.caption,
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
    return const Center(
      child: CircularProgressIndicator(
        color: IptvColors.accentTerracotta,
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
            const Icon(
              Icons.error_outline,
              color: IptvColors.accentTerracotta,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text('加载失败', style: IptvTypography.serifTitle),
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
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: IptvColors.textSecondary,
            ),
            SizedBox(height: 16),
            Text('该分类暂无频道', style: IptvTypography.serifTitle),
          ],
        ),
      ),
    );
  }
}
