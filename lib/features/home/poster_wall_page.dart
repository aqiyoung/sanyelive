import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../data/providers/vod_provider.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/content.dart';
import '../../../data/repositories/channel_repository.dart';

/// 视界 海报墙首页
class PosterWallPage extends ConsumerWidget {
  const PosterWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: context.bgBase,
      child: SafeArea(
        bottom: false,
        top: false,
        child: FutureBuilder<List<Channel>>(
          // v0.3.13.0: 改用 channelsProvider (includes _enrichWithRemoteLogos) —
          // 本地 logo 为 null 时拿远程 logo fill, 台标出现.
          // channelsProvider 同步返本地 (loadBundled 有缓存, 零 IO), 远程拉取
          // fire-and-forget, FutureBuilder 首帧不白屏.
          future: ref.read(channelsProvider.future),
          builder: (context, snapshot) {
            final channels = snapshot.data ?? const <Channel>[];
            final liveChannels = channels
                .where((ch) => ch.categories.any((c) => ['央视', '卫视', '体育', '地方', '影视'].contains(c)))
                .toList();
            final displayChannels = liveChannels.isNotEmpty ? liveChannels : channels;

            return Column(
              children: [
                const _HomeTopBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      const _HeroBanner(),
                      const SizedBox(height: 18),
                      const _CategoryShortcutBar(),
                      const SizedBox(height: 18),
                      _LiveTvModule(
                        isLoading: snapshot.connectionState == ConnectionState.waiting,
                        channels: displayChannels.take(4).toList(),
                        error: snapshot.error,
                      ),
                      const SizedBox(height: 20),
                      _VodSection(
                        title: '今日推荐',
                        provider: vodRecommendedProvider,
                        badges: const ['HOT', 'VIP', '独播'],
                      ),
                      const SizedBox(height: 20),
                      _VodSectionWithTabs(
                        title: '热播电影',
                        provider: vodMoviesProvider,
                        badges: const ['热播', 'VIP', '独播', '热播', 'VIP'],
                        tabs: const ['全部', '动作', '科幻', '喜剧'],
                      ),
                      const SizedBox(height: 20),
                      _VodSectionWithTabs(
                        title: '热播剧集',
                        provider: vodSeriesProvider,
                        badges: const ['热播', 'VIP', '热播', 'VIP', 'VIP'],
                        tabs: const ['全部', '古装', '都市', '悬疑'],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10 + MediaQuery.of(context).padding.top, 16, 8),
      child: Row(
        children: [
          // GPT 设计的品牌 icon
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset(
              'assets/icons/shijie_logo.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '视界',
            style: TextStyle(
              color: context.fgMain,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () => context.go('/search'),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.bgCardHigh,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: context.fgBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: context.fgSub, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '庆余年 第二季',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.fgSub, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _TopIcon(icon: Icons.history_rounded, onTap: () => context.go('/playback-history')),
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: context.fgMain, size: 22),
      onPressed: onTap,
    );
  }
}

class _HeroBanner extends StatefulWidget {
  const _HeroBanner();

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  late final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_PosterItem> _posters = const [
    _PosterItem(
      gradientColors: const [Color(0xFF4B1F1D), Color(0xFF151515), Color(0xFF2C1A12)],
      circleColor: const Color(0xFFE8A449),
      badge: '独播',
      badgeColor: const Color(0xFFE53935),
      title: '庆余年 第二季',
      subtitle: '余年有幸  与君再相逢',
      enTitle: 'QING YU NIAN',
    ),
    _PosterItem(
      gradientColors: const [Color(0xFF0D2137), Color(0xFF151515), Color(0xFF1A2A3A)],
      circleColor: const Color(0xFF4FC3F7),
      badge: '科幻',
      badgeColor: const Color(0xFF1565C0),
      title: '三体',
      subtitle: '人类文明的至暗时刻',
      enTitle: 'THE THREE-BODY PROBLEM',
    ),
    _PosterItem(
      gradientColors: const [Color(0xFF2A0D1A), Color(0xFF151515), Color(0xFF2A1515)],
      circleColor: const Color(0xFFE040FB),
      badge: '悬疑',
      badgeColor: const Color(0xFF7B1FA2),
      title: '漫长的季节',
      subtitle: '往前看，别回头',
      enTitle: 'THE LONG SEASON',
    ),
    _PosterItem(
      gradientColors: const [Color(0xFF1A3A1A), Color(0xFF151515), Color(0xFF1A2A1A)],
      circleColor: const Color(0xFF66BB6A),
      badge: '动作',
      badgeColor: const Color(0xFF2E7D32),
      title: '狂飙',
      subtitle: '正义与罪恶的较量',
      enTitle: 'THE KNOCKOUT',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 178,
          child: Stack(
            children: [
              PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: _posters.map((p) => _PosterSlide(item: p)).toList(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_posters.length, (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _currentPage == i ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? context.fgMain
                              : context.fgMain.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterItem {
  final List<Color> gradientColors;
  final Color circleColor;
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final String enTitle;

  const _PosterItem({
    required this.gradientColors,
    required this.circleColor,
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.enTitle,
  });
}

class _PosterSlide extends StatelessWidget {
  final _PosterItem item;
  const _PosterSlide({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: item.gradientColors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -28,
            top: -18,
            bottom: -12,
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    item.circleColor.withValues(alpha: 0.45),
                    item.circleColor.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 18,
            child: _Badge(label: item.badge, color: item.badgeColor),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.go('/search'),
                splashColor: Colors.white.withValues(alpha: 0.06),
                highlightColor: Colors.white.withValues(alpha: 0.03),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: 8),
                Text(item.subtitle, style: const TextStyle(color: Color(0xFFD5D5D5), fontSize: 13)),
                const SizedBox(height: 12),
                Text(item.enTitle, style: const TextStyle(color: Color(0x55FFFFFF), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryShortcutBar extends StatelessWidget {
  const _CategoryShortcutBar();

  @override
  Widget build(BuildContext context) {
    const shortcuts = [
      _Shortcut('电视直播', Icons.live_tv_rounded, const Color(0xFFE53935), '/category/live'),
      _Shortcut('电影', Icons.movie_creation_rounded, const Color(0xFF8E44AD), '/vod-category?cat=movie'),
      _Shortcut('电视剧', Icons.tv_rounded, const Color(0xFF3D7CFF), '/vod-category?cat=series'),
      _Shortcut('综艺', Icons.star_rounded, const Color(0xFF35B36B), '/vod-category?cat=variety'),
      _Shortcut('动漫', Icons.face_retouching_natural_rounded, const Color(0xFFF0B429), '/vod-category?cat=anime'),
      _Shortcut('纪录片', Icons.public_rounded, const Color(0xFF42A5F5), '/vod-category?cat=documentary'),
      _Shortcut('体育', Icons.sports_soccer_rounded, const Color(0xFF43A047), '/vod-category?cat=sports'),
      // v0.3.13.0: 海外剧场 — 欧美剧/英剧/韩剧/日剧.
      _Shortcut('海外剧场', Icons.language_rounded, const Color(0xFF00BCD4), '/vod-category?cat=overseas'),
    ];

    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: shortcuts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = shortcuts[index];
          return GestureDetector(
            onTap: item.route == null ? null : () => context.go(item.route!),
            child: SizedBox(
              width: 58,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.fgBorder),
                    ),
                    child: Icon(item.icon, color: item.color, size: 27),
                  ),
                  const SizedBox(height: 7),
                  Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgMain, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LiveTvModule extends StatelessWidget {
  const _LiveTvModule({required this.isLoading, required this.channels, this.error});

  final bool isLoading;
  final List<Channel> channels;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    // v0.3.13.0: 直播模块跟随 theme — 浅色米白底深棕字, 深色深棕黑底米色字.
    final bgColor = context.bgCard;
    final borderColor = context.fgBorder;
    final textColor = context.fgMain;

    final primary = channels.isNotEmpty ? channels.first : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 一栏：预览缩略图
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: primary == null ? null : () => context.go('/player/${primary.id}'),
                child: AspectRatio(
                  aspectRatio: 0.7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        children: [
                          Center(
                            child: primary?.logoUrl != null && primary!.logoUrl!.isNotEmpty
                                ? Image.network(
                                    primary.logoUrl!,
                                    width: 48,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Icon(Icons.live_tv_rounded, color: context.fgSub, size: 32),
                                  )
                                : Icon(isLoading ? Icons.hourglass_empty_rounded : Icons.live_tv_rounded, color: context.fgSub, size: 32),
                          ),
                          const Positioned(left: 6, top: 6, child: _Badge(label: '直播中', color: Color(0xFFE53935))),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(primary?.displayName ?? '', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 二栏：正在直播详情
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('正在直播', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('新闻30分', style: TextStyle(color: context.fgAccent, fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('12:00', style: TextStyle(color: context.fgSub, fontSize: 10)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: 0.62,
                            minHeight: 2.5,
                            color: const Color(0xFFE53935),
                            backgroundColor: context.fgBorder,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('12:30', style: TextStyle(color: context.fgSub, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.arrow_forward_rounded, color: context.fgSub, size: 10),
                      const SizedBox(width: 4),
                      Text('午间剧场 · 辉煌岁月', style: TextStyle(color: context.fgSub, fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // 三栏：其他频道列表
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('其他频道', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (isLoading)
                    const Text('加载中...', style: TextStyle(color: context.fgSub, fontSize: 12))
                  else if (channels.isEmpty)
                    const Text('暂无频道', style: TextStyle(color: context.fgSub, fontSize: 12))
                  else
                    ...channels.skip(1).take(4).map((ch) => GestureDetector(
                          onTap: () => context.go('/player/${ch.id}'),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                Container(
                                  width: 4, height: 4,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(ch.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        )),
                ],
              ),
            ),
          ],
        ),        ),
      ),
    );
  }
}

class _LiveListText extends StatelessWidget {
  const _LiveListText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgMain, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(subtitle.isEmpty ? '精彩节目直播中' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgSub, fontSize: 11)),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.content, required this.badge});

  final Content content;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final badgeColor = badge == 'VIP'
        ? const Color(0xFFF0B429)
        : badge == 'HOT'
            ? const Color(0xFFE53935)
            : const Color(0xFF8E44AD);

    return GestureDetector(
      onTap: () {
        // v0.3.11.62: 有真实可播源 → 直接点播; 否则跳搜索
        if (content.sourceUrls.isNotEmpty &&
            !content.sourceUrls.first.contains('example.com')) {
          context.go('/player/vod?url=${Uri.encodeComponent(content.sourceUrls.first)}&title=${Uri.encodeComponent(content.title)}');
        } else {
          context.go('/search');
        }
      },
      child: SizedBox(
        width: 104,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 142,
              width: 104,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF343434), badgeColor.withValues(alpha: 0.32), const Color(0xFF171717)],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        content.title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.15),
                      ),
                    ),
                  ),
                  Positioned(right: 7, top: 7, child: _Badge(label: badge, color: badgeColor)),
                  if (content.rating != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF0B429), size: 14),
                          const SizedBox(width: 2),
                          Text(content.displayRating, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(content.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgMain, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(content.subtitle ?? '${content.year ?? '热播'} · ${content.genres.take(2).join(' ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgSub, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.icon, this.color, this.route);

  final String label;
  final IconData icon;
  final Color color;
  final String? route;
}

/// v0.3.11.64: VOD 动态内容区 — 用 Riverpod provider 替换 mock 数据
class _VodSection extends ConsumerWidget {
  const _VodSection({required this.title, required this.provider, required this.badges});

  final String title;
  final FutureProvider<List<Content>> provider;
  final List<String> badges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(title, style: TextStyle(color: context.fgMain, fontSize: 20, fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/search'),
                child: Row(
                  children: [
                    Text('更多', style: TextStyle(color: context.fgSub, fontSize: 13)),
                    Icon(Icons.chevron_right_rounded, color: context.fgSub, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 194,
          child: async.when(
            loading: () => Center(child: CircularProgressIndicator(color: context.fgSub, strokeWidth: 2)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败: ${e.toString().split("\n").first}', style: TextStyle(color: context.fgSub, fontSize: 13)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Center(child: Text('暂无内容', style: TextStyle(color: context.fgSub)));
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _PosterCard(content: items[index], badge: badges[index % badges.length]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 热播剧集 / 热播电影 — 带分类筛选标签的 VOD 横滚区.
/// v0.3.12+95: tabs 放标题同一行, 标题字号 16, 选中态红色描边 + 浅红底.
class _VodSectionWithTabs extends ConsumerStatefulWidget {
  const _VodSectionWithTabs({
    required this.title,
    required this.provider,
    required this.badges,
    required this.tabs,
  });

  final String title;
  final FutureProvider<List<Content>> provider;
  final List<String> badges;
  final List<String> tabs;

  @override
  ConsumerState<_VodSectionWithTabs> createState() =>
      _VodSectionWithTabsState();
}

class _VodSectionWithTabsState extends ConsumerState<_VodSectionWithTabs> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(widget.provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                Text(widget.title,
                    style: TextStyle(
                        color: context.fgMain,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: widget.tabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedTab == index;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTab = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? context.fgAccent.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? context.fgAccent : context.fgBorder,
                              width: isSelected ? 1.2 : 1,
                            ),
                          ),
                          child: Text(
                            widget.tabs[index],
                            style: TextStyle(
                              color: isSelected ? context.fgAccent : context.fgSub,
                              fontSize: 11,
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => context.go('/search'),
                  child: Row(
                    children: [
                      Text('更多', style: TextStyle(color: context.fgSub, fontSize: 12)),
                      Icon(Icons.chevron_right_rounded,
                          color: context.fgSub, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 194,
          child: async.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.fgSub, strokeWidth: 2)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败: ${e.toString().split("\n").first}',
                    style: TextStyle(color: context.fgSub, fontSize: 13)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Center(
                    child: Text('暂无内容', style: TextStyle(color: context.fgSub)));
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _PosterCard(
                  content: items[index],
                  badge: widget.badges[index % widget.badges.length],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
