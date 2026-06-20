import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/typography.dart';
import '../../core/tv/tv_focus.dart';
import '../../data/channel_filter.dart';
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
        // v0.3.8+108 (6/20 老板反馈): 删 _CctvUnavailableBanner.
        // 之前 v0.3.7+62 加这个 banner 是为了告诉老板 CCTV 公开源难搞.
        // 但老板今天说 "去掉吧" — 看到就烦.  现在直接进频道列表,
        // 播放页 failover 多个候选源尝试.
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else
          Builder(
            builder: (context) {
              // 6/17 v0.2.3 P1-5: TV 端 TvFocus 套住 ChannelTile
              final isTv = context.deviceTier == DeviceTier.tv;
              // v0.3.8+101 (6/20 15:02 老板反馈): ChannelTile 现在是独立
              // 容器 (浅一档米色 + 圆角 12),  list 加左右 16 padding + 上
              // 8 下 24 padding,  item 间插 SizedBox(10) 让容器之间有间隔.
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
                      country: ch.country,
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

  List<Channel> _filter(List<Channel> all) {
    switch (categoryId) {
      case 'cctv':
        return ChannelFilter.cctv(all);
      case 'satellite':
        return ChannelFilter.satellite(all);
      case 'local':
        return ChannelFilter.local(all);
      // v0.3.8+110 (6/20 老板加国际频道):  i18n = 非中文区 country
      case 'international':
        return ChannelFilter.international(all);
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
      // v0.3.8+110 (6/20 老板加国际频道):  i18n 中文名
      case 'international':
        return '国际';
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
            // 6/18 v0.3.6.1 hotfix: textPrimary → onSurface
            color: Theme.of(context).colorScheme.onSurface,
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
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              // 6/18 v0.3.6.1 hotfix: textSecondary → onSurfaceVariant
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

// v0.3.8+108 (6/20 老板反馈): 删 _CctvUnavailableBanner class.
// 之前 v0.3.6+49 加这个 banner 是为了告诉老板 CCTV 公开源难搞.
// 但老板今天说 "去掉吧" — 看到就烦.  直接进频道列表,
// 播放页 failover 多个候选源尝试.
