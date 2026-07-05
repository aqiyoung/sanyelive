import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/channel.dart';
import '../../../data/models/content.dart';
import '../../../data/mock/mock_contents.dart';
import '../../../data/repositories/channel_repository.dart';
import '../../core/theme/colors.dart';

/// 三页影视 海报墙首页
class PosterWallPage extends ConsumerWidget {
  const PosterWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: IptvColors.bgParchment,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('三页影视',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface)),
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
            ),
            const Expanded(child: _PosterWallTabs()),
          ],
        ),
      ),
    );
  }
}

class _PosterWallTabs extends ConsumerStatefulWidget {
  const _PosterWallTabs();

  @override
  ConsumerState<_PosterWallTabs> createState() => _PosterWallTabsState();
}

class _PosterWallTabsState extends ConsumerState<_PosterWallTabs> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: List.generate(3, (i) {
              const tabs = ['首页', '点播', '收藏'];
              final active = i == _currentTab;
              return GestureDetector(
                onTap: () => setState(() => _currentTab = i),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.bold : FontWeight.w500,
                      color: active
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: switch (_currentTab) {
            0 => const _HomeScreenContent(),
            1 => const _VodScreenContent(),
            _ => _ComingSoonScreen(tab: _currentTab),
          },
        ),
      ],
    );
  }
}

// ──────── 首页 — 混排海报墙 ────────

/// 首页 — 频道海报 + 点播推荐混排
class _HomeScreenContent extends ConsumerWidget {
  const _HomeScreenContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Channel>>(
      future: ref.read(channelRepositoryProvider).loadBundled(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                const SizedBox(height: 12),
                const Text('加载失败', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text(snapshot.error.toString(),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(channelRepositoryProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        final channels = snapshot.data ?? [];
        final cctv = <Channel>[];
        final satellite = <Channel>[];
        final local = <Channel>[];
        for (final ch in channels) {
          if (ch.categories.contains('央视')) {
            cctv.add(ch);
          } else if (ch.categories.contains('卫视')) {
            satellite.add(ch);
          } else {
            local.add(ch);
          }
        }
        return ListView(
          children: [
            if (cctv.isNotEmpty)
              _buildSection(context, '🔥 推荐直播', cctv,
                  () => context.go('/category/cctv')),
            if (satellite.isNotEmpty)
              _buildSection(context, '📡 卫视频道', satellite,
                  () => context.go('/category/satellite')),
            if (local.isNotEmpty)
              _buildSection(context, '🏙️ 地方频道', local,
                  () => context.go('/category/local')),
            const SizedBox(height: 8),
            // ── 点播推荐 ──
            _buildPosterSection(context, '🎬 热门电影', kMockMovies),
            _buildPosterSection(context, '📺 电视剧', kMockSeries),
            if (kMockVariety.isNotEmpty)
              _buildPosterSection(context, '🎤 热门综艺', kMockVariety),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildSection(BuildContext context, String title,
      List<Channel> items, VoidCallback onSeeAll) {
    final cardWidth = MediaQuery.of(context).size.width > 600 ? 130.0 : 95.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _sectionBar(context),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: onSeeAll,
                child: Row(children: [
                  Text('查看全部',
                      style: TextStyle(
                          fontSize: 13, color: IptvColors.textSecondary)),
                  Icon(Icons.chevron_right,
                      size: 18, color: IptvColors.textSecondary)
                ]),
              ),
            ],
          ),
        ),
        SizedBox(
          height: cardWidth / 0.65 + 28,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                _ChannelCard(channel: items[i], width: cardWidth),
          ),
        ),
      ],
    );
  }

  Widget _sectionBar(BuildContext context) {
    return Container(
      width: 4,
      height: 18,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildPosterSection(
      BuildContext context, String title, List<Content> items) {
    final cardWidth = 130.0;
    final cardHeight = cardWidth / 0.7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight + 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                _PosterCard(content: items[i], width: cardWidth, height: cardHeight),
          ),
        ),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel, required this.width});

  final Channel channel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width / 0.65;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => context.go('/player/${channel.id}'),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: width,
                height: height,
                color: theme.colorScheme.surfaceContainerHighest,
                child: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                    ? Image.network(channel.logoUrl!,
                        fit: BoxFit.contain,
                        width: width,
                        errorBuilder: (_, __, ___) =>
                            _LogoPlaceholder(char: firstChar(channel.displayName)))
                    : _LogoPlaceholder(char: firstChar(channel.displayName)),
              ),
            ),
            const SizedBox(height: 6),
            Text(channel.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// 频道首字母占位 — 渐变背景 + 白字, 取代红字
class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder({required this.char});
  final String char;

  @override
  Widget build(BuildContext context) {
    final hash = char.codeUnitAt(0);
    final hue = (hash * 37) % 360;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.35).toColor(),
            HSLColor.fromAHSL(1, (hue + 30) % 360, 0.50, 0.25).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Text(char,
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white70)),
      ),
    );
  }
}

// ──────── 点播 — 海报墙 ────────

/// 点播海报墙 — 展示电影/电视剧/综艺海报卡片
class _VodScreenContent extends StatelessWidget {
  const _VodScreenContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _buildPosterSection(context, '🎬 电影推荐', kMockMovies),
        _buildPosterSection(context, '📺 电视剧', kMockSeries),
        if (kMockVariety.isNotEmpty)
          _buildPosterSection(context, '🎤 综艺', kMockVariety),
      ],
    );
  }

  Widget _buildPosterSection(
      BuildContext context, String title, List<Content> items) {
    final cardWidth = 130.0;
    final cardHeight = cardWidth / 0.7; // ~186px poster aspect
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight + 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                _PosterCard(content: items[i], width: cardWidth, height: cardHeight),
          ),
        ),
      ],
    );
  }
}

/// 单张海报卡片 — 渐变占位背景 + 标题/评分/标签
class _PosterCard extends StatelessWidget {
  const _PosterCard(
      {required this.content,
      required this.width,
      required this.height});

  final Content content;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hash = content.title.codeUnitAt(0);
    final hue = (hash * 47 + 120) % 360;
    return GestureDetector(
      onTap: () {
        // 播放点播 → 后续接入 player
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放: ${content.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: SizedBox(
        width: width,
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
                      HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.35)
                          .toColor(),
                      HSLColor.fromAHSL(1, (hue + 45) % 360, 0.50, 0.15)
                          .toColor(),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // 评分徽章
                    if (content.rating != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: content.rating! >= 9.0
                                ? const Color(0xFFE65100)
                                : Colors.black45,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star,
                                  size: 11, color: Color(0xFFFFD600)),
                              const SizedBox(width: 2),
                              Text(content.displayRating,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    // 标题（居中）
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          content.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // 底部标签
                    if (content.genres.isNotEmpty)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: content.genres.take(2).map((g) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(g,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10)),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 标题
            Text(content.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            // 副标题/年份
            if (content.year != null || content.subtitle != null)
              Text(
                content.subtitle ?? content.year ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: IptvColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────── Coming Soon ────────

class _ComingSoonScreen extends StatelessWidget {
  const _ComingSoonScreen({required this.tab});
  final int tab;

  @override
  Widget build(BuildContext context) {
    final info = tab == 2 ? ('收藏', Icons.favorite) : ('', Icons.help);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.$2, size: 64, color: IptvColors.textSecondary),
          const SizedBox(height: 16),
          Text('${info.$1}功能开发中…',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text('即将上线，敬请期待',
              style:
                  TextStyle(fontSize: 13, color: IptvColors.textSecondary)),
        ],
      ),
    );
  }
}

String firstChar(String s) => s.isNotEmpty ? s[0] : '?';