import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/tv/tv_focus.dart';
import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../features/favorites/favorites_service.dart';
import '../../widgets/channel_tile.dart';

/// 6/17 v0.2.3 P1-2: 收藏页 — 列出所有已收藏的频道.
/// - 读 favoritesProvider (List<String> ids)
/// - 反查 channelsProvider → Channel
/// - 长按 ChannelTile → 弹底部 sheet 确认删除
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncFavs = ref.watch(favoritesProvider);
    final asyncChannels = ref.watch(channelsProvider);

    return Scaffold(
      // 6/18 v0.3.6.1 hotfix: 删 scaffold 硬编码 bgParchment,
      // 让 colorScheme.surface (light=bgParchment / dark=darkBg) 生效.
      // P2-3-A (6/18 老板拍): TV 端 root 包 TvFocusGroup,  方向键导航.
      body: SafeArea(
        child: TvFocusGroup(
          child: Column(
            children: [
              _FavoritesAppBar(
                count: asyncFavs.maybeWhen(
                  data: (ids) => ids.length,
                  orElse: () => 0,
                ),
              ),
              Expanded(
                child: asyncFavs.when(
                  loading: () => const _LoadingState(),
                  error: (e, _) => _ErrorState(message: e.toString()),
                  data: (ids) => _buildList(context, ref, ids, asyncChannels),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<String> favIds,
    AsyncValue<List<Channel>> asyncChannels,
  ) {
    if (favIds.isEmpty) {
      return const _EmptyState();
    }
    return asyncChannels.when(
      loading: () => const _LoadingState(),
      error: (e, _) => _ErrorState(message: e.toString()),
      data: (allChannels) {
        // O(N) 反查一次, build 一次 hash map,  避免每个 tile 都线性扫描.
        // 严格说 480 频道 * 5 收藏不是性能瓶颈,  写专业点.
        final byId = <String, Channel>{for (final c in allChannels) c.id: c};
        final ordered = <Channel>[];
        for (final id in favIds) {
          final ch = byId[id];
          if (ch != null) ordered.add(ch);
        }
        if (ordered.isEmpty) {
          return const _EmptyState();
        }
        // 6/17 v0.2.3 P1-5: TV 端 TvFocus 拿焦点环.  手机端不变.
        // P2-3-A (6/18 老板拍): TV 端 borderWidth 3px + scale 1.08,  3 米可视.
        final isTv = context.deviceTier == DeviceTier.tv;
        return TvFocusGroup(
          child: ListView.builder(
            itemCount: ordered.length,
            itemBuilder: (context, i) {
              final ch = ordered[i];
              final tile = GestureDetector(
                onLongPress: () => _confirmRemove(context, ref, ch),
                child: ChannelTile(
                  channel: ch,
                  channelNumber: (i + 1).toString().padLeft(2, '0'),
                  channelName: ch.name,
                  country: ch.country,
                  isLive: ch.sources.isNotEmpty,
                  onTap: () => context.push('/player/${ch.id}'),
                  // P2-3-A (6/18): TV 端字号 14sp → 18sp,  3 米可视.
                  fontSizeOverride: isTv ? 18.0 : null,
                ),
              );
              if (!isTv) return tile;
              return TvFocus(
                autofocus: i == 0,
                onTap: () => context.push('/player/${ch.id}'),
                borderRadius: 0,
                borderWidth: 3,
                focusedScale: 1.08,
                child: tile,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    Channel ch,
  ) async {
    final svc = ref.read(favoritesServiceProvider);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      // 6/18 v0.3.6.1 hotfix: bgElevated → colorScheme.surfaceContainer,
      // 暗色下用 darkSurface (暖深灰) 而不是浅米色.
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '取消收藏「${ch.displayName}」?',
                    style: IptvTypography.serifTitle,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    '从收藏移除',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('取消'),
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true) {
      await svc.remove(ch.id);
      ref.invalidate(favoritesProvider);
    }
  }
}

class _FavoritesAppBar extends StatelessWidget {
  const _FavoritesAppBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // P2-3-A (6/18 老板拍): TV 端 back 按钮套 TvFocus,  3 米可视.
    final isTv = context.deviceTier == DeviceTier.tv;
    final backButton = IconButton(
      icon: const Icon(Icons.arrow_back),
      // 6/18 v0.3.6.1 hotfix: textPrimary → onSurface,
      // 暗色下用 darkTextPrimary (米色) 而不是浅色 token.
      color: Theme.of(context).colorScheme.onSurface,
      onPressed: () => context.pop(),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 12),
      child: Row(
        children: [
          if (isTv)
            TvFocus(
              borderRadius: 24,
              borderWidth: 3,
              focusedScale: 1.08,
              onTap: () => context.pop(),
              child: backButton,
            )
          else
            backButton,
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的收藏', style: IptvTypography.serifHeadline),
                Text(
                  count == 0 ? '暂无收藏' : '共 $count 个频道',
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
            Text(
              message,
              style: IptvTypography.caption,
              textAlign: TextAlign.center,
            ),
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
              Icons.favorite_border,
              size: 56,
              // 6/18 v0.3.6.1 hotfix: textSecondary → onSurfaceVariant,
              // 暗色下用 darkTextSecondary (暖灰) 而不是浅色 token.
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('还没有收藏', style: IptvTypography.serifTitle),
            const SizedBox(height: 8),
            Text(
              '去频道页或搜索页,  点 ♡ 收藏喜欢的频道',
              style: IptvTypography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
