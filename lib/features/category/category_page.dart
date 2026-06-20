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
        if (categoryId == 'cctv')
          const SliverToBoxAdapter(
            child: _CctvUnavailableBanner(),
          ),
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
              return SliverList.builder(
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
                  if (!isTv) return tile;
                  return TvFocus(
                    autofocus: i == 0,
                    onTap: () => context.push('/player/${ch.id}'),
                    borderRadius: 0,
                    child: tile,
                  );
                },
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

/// v0.3.6+49: CCTV 源不可用提示 — 公开网络上找不到长期稳定的明文 HLS 源.
/// 在 CCTV 分类页顶部显示一个 card, 说明现状 + 下一步.
class _CctvUnavailableBanner extends StatelessWidget {
  const _CctvUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          // v0.3.8+99 (6/20 14:03 老板反馈): 删边框线,  靠 surfaceContainerHigh
          // 背景色 + 圆角 区分,  不要线.
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                color: scheme.onSurfaceVariant, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('暂无可用 CCTV 源',
                      style: IptvTypography.sansTitle.copyWith(
                          color: scheme.onSurface, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    '央视源在公开网络上很少有长期稳定的明文流（多需 DRM 密钥）。\n'
                    '当前可点频道会多源切换尝试, 大部分会失败。',
                    style: IptvTypography.caption
                        .copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
