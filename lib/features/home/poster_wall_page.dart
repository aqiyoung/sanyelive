import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/channel.dart';
import '../../../data/repositories/channel_repository.dart';

/// 三页影视 海报墙首页 — 三屏: 直播/点播/收藏
class PosterWallPage extends ConsumerStatefulWidget {
  const PosterWallPage({super.key});

  @override
  ConsumerState<PosterWallPage> createState() => _PosterWallPageState();
}

class _PosterWallPageState extends ConsumerState<PosterWallPage> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IptvColors.bgParchment,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            _buildTopBar(context),
            // Tab 栏
            _buildTabs(),
            // 内容
            Expanded(
              child: _currentTab == 0
                  ? _buildLiveScreen()
                  : _currentTab == 1
                      ? _buildVodScreen()
                      : _buildFavScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text('三页影视',
              style: IptvTypography.serifHeadline
                  .copyWith(fontSize: 24, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    const tabs = ['直播', '点播', '收藏'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = i == _currentTab;
          return GestureDetector(
            onTap: () => setState(() => _currentTab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── 直播屏 ───

  Widget _buildLiveScreen() {
    return FutureBuilder<List<Channel>>(
      future: ref.read(channelRepositoryProvider).loadBundled(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('加载失败: ${snapshot.error}'));
        }
        final channels = snapshot.data ?? [];
        final cctv = channels.where((c) => c.categories.contains('央视')).toList();
        final satellite = channels.where((c) => c.categories.contains('卫视')).toList();
        final local = channels.where((c) => c.categories.contains('地方'))..toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (cctv.isNotEmpty)
              _buildSection('央视频道', cctv.take(12).toList(), _liveCardWidth,
                  () => context.go('/category/cctv')),
            if (satellite.isNotEmpty)
              _buildSection('卫视频道', satellite.take(12).toList(), _liveCardWidth,
                  () => context.go('/category/satellite')),
            if (local.isNotEmpty)
              _buildSection('地方频道', local.take(12).toList(), _liveCardWidth,
                  () => context.go('/category/local')),
          ],
        );
      },
    );
  }

  Widget _buildVodScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_outlined, size: 64, color: IptvColors.textSecondary),
          const SizedBox(height: 16),
          Text('点播功能开发中…', style: IptvTypography.serifTitle),
          const SizedBox(height: 8),
          Text('即将上线电影/电视剧/综艺',
              style: TextStyle(color: IptvColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildFavScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_outline, size: 64, color: IptvColors.textSecondary),
          const SizedBox(height: 16),
          Text('收藏功能开发中…', style: IptvTypography.serifTitle),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go('/favorites'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('查看旧版收藏'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      String title, List<Channel> channels, double cardWidth, VoidCallback onSeeAll) {
    if (channels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(title, style: IptvTypography.serifTitle),
              const Spacer(),
              GestureDetector(
                onTap: onSeeAll,
                child: Row(
                  children: [
                    Text('查看全部',
                        style: TextStyle(
                            fontSize: 13, color: IptvColors.textSecondary)),
                    Icon(Icons.chevron_right,
                        size: 18, color: IptvColors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 横滑列表
        SizedBox(
          height: cardWidth / (16 / 9) + 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final ch = channels[i];
              return SizedBox(
                width: cardWidth,
                child: _buildLiveCard(ch, cardWidth),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLiveCard(Channel ch, double width) {
    final height = width / (16 / 9);
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => context.go('/player/${ch.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 海报
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withOpacity(0.25),
                    scheme.primary.withOpacity(0.08),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Logo 或台标
                  Center(
                    child: ch.logoUrl != null && ch.logoUrl!.isNotEmpty
                        ? Image.network(
                            ch.logoUrl!,
                            width: width * 0.4,
                            height: height * 0.4,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _buildInitial(ch.displayName, width),
                          )
                        : _buildInitial(ch.displayName, width),
                  ),
                  // LIVE 标识
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('LIVE',
                          style: TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 频道名
          Text(
            ch.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial(String name, double width) {
    return Container(
      width: width * 0.5,
      height: width * 0.5,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1) : '?',
          style: TextStyle(
            fontSize: width * 0.2,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  double get _liveCardWidth {
    final w = MediaQuery.of(context).size.width;
    if (w > 1024) return 140; // TV
    if (w > 600) return 120; // Tablet
    return 100; // Phone
  }
}
