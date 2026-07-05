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
class PosterWallPage extends ConsumerWidget {
  const PosterWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部搜索栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: _SearchBar(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined,
                        color: Colors.white70),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            // 分类 Tab
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DefaultTabController(
                length: 7,
                child: TabBar(
                  isScrollable: true,
                  indicatorColor: const Color(0xFFE53935),
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  tabs: const [
                    Tab(text: '首页'),
                    Tab(text: '电视剧'),
                    Tab(text: '电影'),
                    Tab(text: '综艺'),
                    Tab(text: '动漫'),
                    Tab(text: '纪录片'),
                    Tab(text: '新闻'),
                  ],
                ),
              ),
            ),
            const Expanded(child: _HomeBody()),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _HomeBody extends ConsumerStatefulWidget {
  const _HomeBody();

  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Channel>>(
      future: ref.read(channelRepositoryProvider).loadBundled(),
      builder: (context, snapshot) {
        final channels = snapshot.data ?? [];
        return CustomScrollView(
          slivers: [
            // ── 1. 横幅轮播 ──
            SliverToBoxAdapter(child: _HeroBanner(movies: kMockMovies)),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            // ── 2. 分类入口 ──
            const SliverToBoxAdapter(child: _CategoryRow()),
            // ── 3. 电视直播 ──
            if (channels.isNotEmpty)
              SliverToBoxAdapter(
                child: _LiveSection(channels: channels),
              ),
            // ── 4. 正在热播 ──
            SliverToBoxAdapter(
              child: _buildSection(context, '正在热播', kMockRecommended),
            ),
            // ── 5. 为你推荐 ──
            SliverToBoxAdapter(
              child: _buildSection(context, '为你推荐', kMockMovies),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }
}

// ═══ 1. 横幅轮播 ═══

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
              itemBuilder: (_, i) => _heroCard(items[i], _bannerImages[i % _bannerImages.length], context),
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
                  color: _page == i ? const Color(0xFFE53935) : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(Content movie, String imageUrl, BuildContext context) {
    final hue = (movie.title.codeUnitAt(0) * 47 + 120) % 360;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 背景图 (用 Image.network + errorBuilder 避免炸全局)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.30).toColor(),
                        HSLColor.fromAHSL(1, (hue + 40) % 360, 0.50, 0.12).toColor(),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

// ═══ 2. 分类入口 ═══

class _CategoryRow extends StatelessWidget {
  const _CategoryRow();

  @override
  Widget build(BuildContext context) {
    final items = [
      _Cat('电视直播', Icons.tv, 0xFFE53935),
      _Cat('电影', Icons.movie, 0xFFFF6F00),
      _Cat('电视剧', Icons.live_tv, 0xFF2E7D32),
      _Cat('综艺', Icons.star, 0xFF1565C0),
      _Cat('动漫', Icons.emoji_emotions, 0xFF6A1B9A),
      _Cat('纪录片', Icons.public, 0xFF00838F),
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
                  color: Color(c.color).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(c.icon, color: Color(c.color), size: 24),
              ),
              const SizedBox(height: 6),
              Text(c.label,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _Cat {
  final String label;
  final IconData icon;
  final int color;
  const _Cat(this.label, this.icon, this.color);
}

// ═══ 3. 电视直播 ═══

final _mockEpg = {
  'CCTV-1': '今日说法',
  'CCTV-2': '经济半小时',
  'CCTV-3': '开门大吉',
  'CCTV-4': '国宝档案',
  'CCTV-5': '体育新闻',
  'CCTV-6': '佳片有约',
  '湖南卫视': '乘风2025',
  '浙江卫视': '奔跑吧',
  '江苏卫视': '最强大脑',
  '东方卫视': '极限挑战',
};

class _LiveSection extends StatelessWidget {
  final List<Channel> channels;
  const _LiveSection({required this.channels});

  @override
  Widget build(BuildContext context) {
    final cctvs = channels.where((c) => c.categories.contains('央视')).take(5).toList();
    final allCctvs = channels.where((c) => c.categories.contains('央视')).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                          fontSize: 12,
                          color: IptvColors.textSecondary)),
                  Icon(Icons.chevron_right,
                      size: 16, color: IptvColors.textSecondary)
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 三栏布局
          Container(
            height: 145,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // 左：频道列表
                SizedBox(
                  width: 72,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: cctvs.length,
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
                    onTap: cctvs.isNotEmpty
                        ? () => context.go('/player/${cctvs.first.id}')
                        : null,
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
                            Text(
                              cctvs.isNotEmpty ? cctvs.first.displayName : '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _mockEpg[cctvs.isNotEmpty ? cctvs.first.displayName : ""] ?? '直播中',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 右：EPG 节目单
                SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        child: const Text('节目预告',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: min(
                              allCctvs.length, 5),
                          itemBuilder: (_, i) {
                            final ch = allCctvs[i];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 3,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: BoxDecoration(
                                      color: i == 0
                                          ? const Color(0xFFE53935)
                                          : Colors.white24,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _mockEpg[ch.displayName] ?? '直播中',
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
}

// ═══ 4. 海报区块 ═══

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

Widget _buildSection(BuildContext context, String title, List<Content> items) {
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
                    size: 16, color: IptvColors.textSecondary)
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
              _PosterCard(content: items[i], imageUrl: _posterImages[i % _posterImages.length]),
        ),
      ),
    ],
  );
}

class _PosterCard extends StatelessWidget {
  final Content content;
  final String imageUrl;
  const _PosterCard({required this.content, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放: ${content.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 海报图
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.network(imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _posterFallback(content)),
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
                    // VIP 标签 (随机加)
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
                        padding: const EdgeInsets.fromLTRB(6, 20, 6, 6),
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
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
          ],
        ),
      ),
    );
  }

  Widget _posterFallback(Content content) {
    final hue = (content.title.codeUnitAt(0) * 47 + 120) % 360;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.35).toColor(),
            HSLColor.fromAHSL(1, (hue + 45) % 360, 0.50, 0.15).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Text(content.title.characters.first,
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white30)),
      ),
    );
  }
}