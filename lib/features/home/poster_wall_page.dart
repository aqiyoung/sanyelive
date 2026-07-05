import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/channel.dart';
import '../../../data/models/content.dart';
import '../../../data/mock/mock_contents.dart';
import '../../../data/repositories/channel_repository.dart';
import '../../core/theme/colors.dart';

/// 三页影视 首页 — 视界影音风格
class PosterWallPage extends ConsumerStatefulWidget {
  const PosterWallPage({super.key});

  @override
  ConsumerState<PosterWallPage> createState() => _PosterWallPageState();
}

class _PosterWallPageState extends ConsumerState<PosterWallPage> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<Channel>>(
        future: ref.read(channelRepositoryProvider).loadBundled(),
        builder: (context, snapshot) {
          final channels = snapshot.data ?? [];
          return CustomScrollView(
            slivers: [
              // 1. 顶部搜索栏
              SliverToBoxAdapter(child: _buildSearchBar(context)),
              // 2. 分类 Tab
              SliverToBoxAdapter(
                child: _buildCategoryTabs(),
              ),
              // 3. 横幅轮播
              SliverToBoxAdapter(child: _buildHeroBanner()),
              // 4. 分类入口
              SliverToBoxAdapter(child: _buildCategoryRow()),
              // 5. 电视直播
              if (channels.isNotEmpty)
                SliverToBoxAdapter(child: _buildLiveSection(channels)),
              // 6. 今日推荐
              SliverToBoxAdapter(
                child: _buildSection('今日推荐', kMockRecommended),
              ),
              // 7. 热播剧集
              SliverToBoxAdapter(child: _buildHotSeries()),
              // 底部留白
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  // ── 1. 搜索栏 ──
  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/search'),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, size: 18, color: Colors.white38),
                  SizedBox(width: 8),
                  Text('搜索电影 / 直播 / 剧集',
                      style: TextStyle(fontSize: 13, color: Colors.white38)),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: Colors.white70),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // ── 2. 分类 Tab ──
  Widget _buildCategoryTabs() {
    const tabs = ['首页', '电视剧', '电影', '综艺', '动漫', '纪录片', '新闻'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) => GestureDetector(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: i == 0
                  ? const Color(0xFFE53935).withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(tabs[i],
                style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        i == 0 ? FontWeight.w600 : FontWeight.w400,
                    color: i == 0
                        ? const Color(0xFFE53935)
                        : Colors.white60)),
          ),
        ),
      ),
    );
  }

  // ── 3. 横幅轮播 ──
  Widget _buildHeroBanner() {
    return SizedBox(
      height: 200,
      child: _HeroBanner(movies: kMockMovies),
    );
  }

  // ── 4. 分类入口 ──
  Widget _buildCategoryRow() {
    const items = [
      ('电视直播', Icons.tv, 0xFFE53935),
      ('电影', Icons.movie, 0xFFFF6F00),
      ('电视剧', Icons.live_tv, 0xFF2E7D32),
      ('综艺', Icons.star, 0xFF1565C0),
      ('动漫', Icons.emoji_emotions, 0xFF6A1B9A),
      ('纪录片', Icons.public, 0xFF00838F),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((c) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Color(c.$3).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(c.$2, color: Color(c.$3), size: 24),
              ),
              const SizedBox(height: 6),
              Text(c.$1,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── 5. 电视直播 ──
  Widget _buildLiveSection(List<Channel> channels) {
    final cctvs = channels.where((c) => c.categories.contains('央视')).toList();
    final previewCh = cctvs.isNotEmpty ? cctvs.first : channels.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('电视直播',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/category/cctv'),
                child: Row(children: [
                  Text('查看更多',
                      style: TextStyle(
                          fontSize: 12, color: IptvColors.textSecondary)),
                  Icon(Icons.chevron_right,
                      size: 16, color: IptvColors.textSecondary),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 三栏直播
          Container(
            height: 145,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // 左：频道列表
                SizedBox(
                  width: 72,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: min(cctvs.length, 5),
                    itemBuilder: (_, i) {
                      final ch = cctvs[i];
                      return GestureDetector(
                        onTap: () => context.go('/player/${ch.id}'),
                        child: Container(
                          height: 36,
                          margin: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: i == 0
                                ? const Color(0xFFE53935).withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: i == 0
                                ? Border.all(
                                    color: const Color(0xFFE53935)
                                        .withOpacity(0.5))
                                : null,
                          ),
                          child: Center(
                            child: Text(ch.displayName,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: i == 0
                                        ? const Color(0xFFE53935)
                                        : Colors.white54,
                                    fontWeight: i == 0
                                        ? FontWeight.bold
                                        : FontWeight.w400)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 中：直播画面
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () => context.go('/player/${previewCh.id}'),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        image: const DecorationImage(
                          image: NetworkImage(
                            'https://images.unsplash.com/photo-1596526131657-ef5e24d3bb41?w=400&h=250&fit=crop',
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(8),
                        alignment: Alignment.bottomLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(previewCh.displayName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            const Text('正在直播',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 右：节目预告
                SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin:
                            const EdgeInsets.only(top: 8, bottom: 4),
                        child: const Text('节目预告',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: min(cctvs.length, 5),
                          itemBuilder: (_, i) {
                            final ch = cctvs[i];
                            final epg = i == 0
                                ? '今日说法'
                                : i == 1
                                    ? '新闻联播'
                                    : i == 2
                                        ? '开门大吉'
                                        : i == 3
                                            ? '国宝档案'
                                            : '体育新闻';
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 3,
                                    margin:
                                        const EdgeInsets.only(right: 5),
                                    decoration: BoxDecoration(
                                      color: i == 0
                                          ? const Color(0xFFE53935)
                                          : Colors.white24,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      epg,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: i == 0
                                              ? Colors.white
                                              : Colors.white54),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. 通用海报区块 ──
  Widget _buildSection(String title, List<Content> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const Spacer(),
              GestureDetector(
                child: Row(children: [
                  Text('更多',
                      style: TextStyle(
                          fontSize: 12, color: IptvColors.textSecondary)),
                  Icon(Icons.chevron_right,
                      size: 16, color: IptvColors.textSecondary),
                ]),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) =>
                _PosterCard(content: items[i], index: i),
          ),
        ),
      ],
    );
  }

  // ── 7. 热播剧集 ──
  Widget _buildHotSeries() {
    const filterTabs = ['全部', '古装', '都市', '悬疑', '喜剧', '动作'];
    const colCount = 3;
    final items = kMockSeries;
    final rows = (items.length / colCount).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              const Text('热播剧集',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const Spacer(),
              GestureDetector(
                child: Row(children: [
                  Text('更多',
                      style: TextStyle(
                          fontSize: 12, color: IptvColors.textSecondary)),
                  Icon(Icons.chevron_right,
                      size: 16, color: IptvColors.textSecondary),
                ]),
              ),
            ],
          ),
        ),
        // 筛选标签
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filterTabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: i == 0
                    ? const Color(0xFFE53935)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(filterTabs[i],
                  style: TextStyle(
                      fontSize: 13,
                      color: i == 0 ? Colors.white : Colors.white60,
                      fontWeight:
                          i == 0 ? FontWeight.w600 : FontWeight.w400)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 海报网格
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: List.generate(rows, (row) {
              final start = row * colCount;
              final end = min(start + colCount, items.length);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: List.generate(end - start, (col) {
                    final idx = start + col;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            left: col == 0 ? 0 : 6,
                            right: col == colCount - 1 ? 0 : 6),
                        child: _HotSeriesCard(content: items[idx]),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// 子组件
// ═══════════════════════════════════════════

// ── Hero 轮播 ──
final _bannerImages = [
  'https://images.unsplash.com/photo-1536440136628-849c177e76a1?w=800&h=400&fit=crop',
  'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=800&h=400&fit=crop',
  'https://images.unsplash.com/photo-1478720568477-152d9b164e26?w=800&h=400&fit=crop',
  'https://images.unsplash.com/photo-1504384308090-c894fdcc538d?w=800&h=400&fit=crop',
  'https://images.unsplash.com/photo-1517604931442-7e0c8ed2963e?w=800&h=400&fit=crop',
];

class _HeroBanner extends StatefulWidget {
  final List<Content> movies;
  const _HeroBanner({required this.movies});

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  late PageController _pageCtrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.movies.take(5).toList();
    return SizedBox(
      height: 200,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: items.length,
              itemBuilder: (_, i) =>
                  _heroCard(items[i], _bannerImages[i % _bannerImages.length]),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _page == i ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _page == i
                      ? const Color(0xFFE53935)
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(Content movie, String imageUrl) {
    final hue = (movie.title.codeUnitAt(0) * 47 + 120) % 360;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // 背景图 (errorBuilder 兜底渐变色)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          HSLColor.fromAHSL(
                                  1, hue.toDouble(), 0.55, 0.30)
                              .toColor(),
                          HSLColor.fromAHSL(1, (hue + 40) % 360, 0.50,
                                  0.12)
                              .toColor(),
                        ],
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        HSLColor.fromAHSL(
                                1, hue.toDouble(), 0.55, 0.30)
                            .toColor(),
                        HSLColor.fromAHSL(
                                1, (hue + 40) % 360, 0.50, 0.12)
                            .toColor(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 渐变遮罩
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // 内容
          Positioned(
            left: 16,
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(movie.title,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (movie.rating != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: movie.rating! >= 9.0
                              ? const Color(0xFFE65100)
                              : Colors.black45,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 12, color: Color(0xFFFFD600)),
                            const SizedBox(width: 2),
                            Text(movie.displayRating,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('立即播放',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 海报收藏卡 ──
final _posterImages = [
  'https://images.unsplash.com/photo-1485846234645-a62644f84728?w=200&h=280&fit=crop',
  'https://images.unsplash.com/photo-1536440136628-849c177e76a1?w=200&h=280&fit=crop',
  'https://images.unsplash.com/photo-1478720568477-152d9b164e26?w=200&h=280&fit=crop',
  'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=200&h=280&fit=crop',
  'https://images.unsplash.com/photo-1504384308090-c894fdcc538d?w=200&h=280&fit=crop',
  'https://images.unsplash.com/photo-1517604931442-7e0c8ed2963e?w=200&h=280&fit=crop',
  'https://images.unsplash.com/photo-1500462918059-b1a0cb512f1d?w=200&h=280&fit=crop',
  'https://images.unsplash.com/photo-1440404653325-ab127d49abc1?w=200&h=280&fit=crop',
];

class _PosterCard extends StatelessWidget {
  final Content content;
  final int index;
  const _PosterCard({required this.content, required this.index});

  @override
  Widget build(BuildContext context) {
    final imgUrl = _posterImages[index % _posterImages.length];
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _gradientFallback(content.title, 0.35),
                    ),
                  ),
                  // 评分
                  if (content.rating != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: content.rating! >= 9.0
                              ? const Color(0xFFE65100)
                              : Colors.black54,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 10, color: Color(0xFFFFD600)),
                            const SizedBox(width: 2),
                            Text(content.displayRating,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  // VIP 标签
                  if (content.rating != null && content.rating! >= 9.0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('VIP',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  // 底部渐隐 + 标题
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding:
                          const EdgeInsets.fromLTRB(6, 20, 6, 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.8),
                          ],
                        ),
                      ),
                      child: Text(
                        content.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (content.year != null || content.subtitle != null)
            Text(
              content.subtitle ?? content.year ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 10, color: Colors.white38),
            ),
        ],
      ),
    );
  }
}

// ── 热播剧集海报 ──
class _HotSeriesCard extends StatelessWidget {
  final Content content;
  const _HotSeriesCard({required this.content});

  @override
  Widget build(BuildContext context) {
    final hue = (content.title.codeUnitAt(0) * 47 + 120) % 360;
    return GestureDetector(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 160,
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
              child: Center(
                child: Text(content.title.characters.first,
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white30)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(content.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          if (content.rating != null)
            Row(
              children: [
                const Icon(Icons.star,
                    size: 10, color: Color(0xFFFFD600)),
                const SizedBox(width: 2),
                Text(content.displayRating,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white38)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── 渐变色 fallback ──
Widget _gradientFallback(String title, double lightness) {
  final hue = (title.codeUnitAt(0) * 47 + 120) % 360;
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HSLColor.fromAHSL(1, hue.toDouble(), 0.55, lightness).toColor(),
          HSLColor.fromAHSL(1, (hue + 45) % 360, 0.50, lightness * 0.5)
              .toColor(),
        ],
      ),
    ),
  );
}