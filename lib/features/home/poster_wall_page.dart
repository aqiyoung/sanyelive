import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/content.dart';
import '../../../data/mock/mock_contents.dart';
import '../../../data/repositories/channel_repository.dart';
import 'widgets/hero_banner.dart';
import 'widgets/poster_card.dart';
import 'widgets/poster_section.dart';

/// 三页影视 海报墙首页 — 三屏 PageView
///
/// - Page 0: 推荐 (HeroBanner + 分类推荐)
/// - Page 1: 直播 (央视/卫视/地方台)
/// - Page 2: 点播 (电影/电视剧/综艺)
class PosterWallPage extends ConsumerStatefulWidget {
  const PosterWallPage({super.key});

  @override
  ConsumerState<PosterWallPage> createState() => _PosterWallPageState();
}

class _PosterWallPageState extends ConsumerState<PosterWallPage> {
  late final PageController _pageController;
  int _currentPage = 0;

  static const _tabs = [
    TabData('推荐', Icons.star_outline),
    TabData('直播', Icons.live_tv),
    TabData('点播', Icons.movie_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: IptvColors.bgParchment,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            _buildTopBar(context),
            // Tab 栏
            _buildTabBar(context),
            // 内容
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildRecommendScreen(),
                  _buildLiveScreen(),
                  _buildVodScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text(
            '三页影视',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_outline),
            onPressed: () => context.push('/favorites'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final active = i == _currentPage;
          final tab = _tabs[i];
          return GestureDetector(
            onTap: () => _goToPage(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: i < _tabs.length - 1 ? 16 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    tab.icon,
                    size: 16,
                    color: active
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── 推荐屏 ───

  Widget _buildRecommendScreen() {
    return CustomScrollView(
      slivers: [
        // Hero 轮播
        SliverToBoxAdapter(
          child: HeroBanner(
            height: 180,
            items: kMockRecommended
                .map((c) => HeroBannerItem(
                      title: c.title,
                      subtitle: c.description,
                      backdropUrl: c.backdropUrl,
                      onTap: () => _playContent(c),
                    ))
                .toList(),
            onItemTap: (i) => _playContent(kMockRecommended[i]),
          ),
        ),
        // 热门推荐
        SliverToBoxAdapter(
          child: PosterSection(
            title: '🔥 热门推荐',
            itemWidth: _posterWidth,
            items: kMockRecommended
                .map((c) => PosterCard(
                      title: c.title,
                      rating: c.rating,
                      imageUrl: c.posterUrl,
                      width: _posterWidth,
                      onTap: () => _playContent(c),
                    ))
                .toList(),
          ),
        ),
        // 分类快捷入口
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: _buildCategoryShortcuts(),
          ),
        ),
      ],
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
        final local = channels.where((c) => c.categories.contains('地方')).toList();

        return CustomScrollView(
          slivers: [
            if (cctv.isNotEmpty)
              SliverToBoxAdapter(
                child: PosterSection(
                  title: '📺 央视频道',
                  itemWidth: _livePosterWidth,
                  onSeeAll: () => _openCategory('cctv'),
                  items: cctv
                      .take(12)
                      .map((c) => LivePosterCard(
                            title: c.displayName,
                            logoUrl: c.logoUrl,
                            width: _livePosterWidth,
                            onTap: () => _playChannel(c),
                          ))
                      .toList(),
                ),
              ),
            if (satellite.isNotEmpty)
              SliverToBoxAdapter(
                child: PosterSection(
                  title: '📡 卫视频道',
                  itemWidth: _livePosterWidth,
                  onSeeAll: () => _openCategory('satellite'),
                  items: satellite
                      .take(12)
                      .map((c) => LivePosterCard(
                            title: c.displayName,
                            logoUrl: c.logoUrl,
                            width: _livePosterWidth,
                            onTap: () => _playChannel(c),
                          ))
                      .toList(),
                ),
              ),
            if (local.isNotEmpty)
              SliverToBoxAdapter(
                child: PosterSection(
                  title: '🏙️ 地方频道',
                  itemWidth: _livePosterWidth,
                  onSeeAll: () => _openCategory('local'),
                  items: local
                      .take(12)
                      .map((c) => LivePosterCard(
                            title: c.displayName,
                            logoUrl: c.logoUrl,
                            width: _livePosterWidth,
                            onTap: () => _playChannel(c),
                          ))
                      .toList(),
                ),
              ),
          ],
        );
      },
    );
  }

  // ─── 点播屏 ───

  Widget _buildVodScreen() {
    return CustomScrollView(
      slivers: [
        // 精选电影
        SliverToBoxAdapter(
          child: PosterSection(
            title: '🎬 精选电影',
            itemWidth: _posterWidth,
            items: kMockMovies
                .map((c) => PosterCard(
                      title: c.title,
                      subtitle: c.year,
                      rating: c.rating,
                      imageUrl: c.posterUrl,
                      width: _posterWidth,
                      onTap: () => _openDetail(c.id),
                    ))
                .toList(),
          ),
        ),
        // 热播剧集
        SliverToBoxAdapter(
          child: PosterSection(
            title: '📺 热播剧集',
            itemWidth: _posterWidth,
            items: kMockSeries
                .map((c) => PosterCard(
                      title: c.title,
                      subtitle: c.year,
                      rating: c.rating,
                      imageUrl: c.posterUrl,
                      width: _posterWidth,
                      onTap: () => _openDetail(c.id),
                    ))
                .toList(),
          ),
        ),
        // 综艺节目
        SliverToBoxAdapter(
          child: PosterSection(
            title: '🎪 综艺节目',
            itemWidth: _posterWidth,
            items: kMockVariety
                .map((c) => PosterCard(
                      title: c.title,
                      subtitle: c.year,
                      rating: c.rating,
                      imageUrl: c.posterUrl,
                      width: _posterWidth,
                      onTap: () => _openDetail(c.id),
                    ))
                .toList(),
          ),
        ),
        // 底部留白
        const SliverToBoxAdapter(
          child: SizedBox(height: 32),
        ),
      ],
    );
  }

  // ─── 辅助 ───

  Widget _buildCategoryShortcuts() {
    final categories = [
      ('直播', Icons.tv, () => _goToPage(1)),
      ('电影', Icons.movie, () => _goToPage(2)),
      ('收藏', Icons.favorite, () => context.push('/favorites')),
      ('历史', Icons.history, () {}),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: categories.map((cat) {
        return GestureDetector(
          onTap: cat.$3,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(cat.$2,
                    color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 6),
              Text(cat.$1,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  double get _posterWidth =>
      context.deviceTier == DeviceTier.tv ? 110.0 : 90.0;

  double get _livePosterWidth =>
      context.deviceTier == DeviceTier.tv ? 100.0 : 80.0;

  void _playContent(Content c) {
    if (c.sourceUrls.isNotEmpty) {
      // TODO: 统一播放入口
      debugPrint('Play: ${c.title}');
    }
  }

  void _playChannel(channel) {
    context.push('/player/${channel.id}');
  }

  void _openCategory(String catId) {
    context.push('/category/$catId');
  }

  void _openDetail(String id) {
    context.push('/detail/$id');
    // TODO: 详情页实现
  }
}

class TabData {
  const TabData(this.label, this.icon);
  final String label;
  final IconData icon;
}
