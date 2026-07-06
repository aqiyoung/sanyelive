import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/mock/mock_contents.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/content.dart';
import '../../../data/repositories/channel_repository.dart';

/// 三页影视 海报墙首页
class PosterWallPage extends ConsumerWidget {
  const PosterWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: const Color(0xFF101010),
      child: SafeArea(
        bottom: false,
        top: false,
        child: FutureBuilder<List<Channel>>(
          future: ref.read(channelRepositoryProvider).loadBundled(),
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
                      _ContentSection(
                        title: '今日推荐',
                        items: kMockRecommended,
                        badges: const ['HOT', 'VIP', '独播'],
                      ),
                      const SizedBox(height: 18),
                      const _FilterPills(),
                      const SizedBox(height: 14),
                      _ContentSection(
                        title: '热播剧集',
                        items: kMockSeries,
                        badges: const ['独播', 'VIP', '更新'],
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
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          const Text(
            '视界',
            style: TextStyle(
              color: Colors.white,
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
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded, color: Color(0xFFB8B8B8), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '庆余年 第二季',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Color(0xFFE6E6E6), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _TopIcon(icon: Icons.tune_rounded, onTap: () => context.go('/category/cctv')),
          _TopIcon(icon: Icons.history_rounded, onTap: () => context.go('/favorites')),
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
      icon: Icon(icon, color: Colors.white, size: 22),
      onPressed: onTap,
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 178,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4B1F1D), Color(0xFF151515), Color(0xFF2C1A12)],
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
                        const Color(0xFFE8A449).withOpacity(0.45),
                        const Color(0xFFE53935).withOpacity(0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                top: 18,
                child: _Badge(label: '独播', color: const Color(0xFFE53935)),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.go('/search'),
                    splashColor: Colors.white.withOpacity(0.06),
                    highlightColor: Colors.white.withOpacity(0.03),
                  ),
                ),
              ),
              const Positioned(
                left: 20,
                bottom: 30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('庆余年 第二季', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.1)),
                    SizedBox(height: 8),
                    Text('余年有幸  与君再相逢', style: TextStyle(color: Color(0xFFD5D5D5), fontSize: 13)),
                    SizedBox(height: 12),
                    Text('QING YU NIAN', style: TextStyle(color: Color(0x55FFFFFF), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) => Container(
                        width: i == 0 ? 16 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == 0 ? Colors.white : Colors.white.withOpacity(0.35),
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

class _CategoryShortcutBar extends StatelessWidget {
  const _CategoryShortcutBar();

  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      _Shortcut('电视直播', Icons.live_tv_rounded, const Color(0xFFE53935), '/category/cctv'),
      _Shortcut('电影', Icons.movie_creation_rounded, const Color(0xFF8E44AD), '/category/影视'),
      _Shortcut('电视剧', Icons.tv_rounded, const Color(0xFF3D7CFF), '/search'),
      _Shortcut('综艺', Icons.star_rounded, const Color(0xFF35B36B), '/category/娱乐'),
      _Shortcut('动漫', Icons.face_retouching_natural_rounded, const Color(0xFFF0B429), '/category/少儿'),
      _Shortcut('纪录片', Icons.public_rounded, const Color(0xFF42A5F5), '/category/科教'),
      _Shortcut('体育', Icons.sports_soccer_rounded, const Color(0xFF43A047), '/category/体育'),
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
                      color: const Color(0xFF1F1F1F),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Icon(item.icon, color: item.color, size: 27),
                  ),
                  const SizedBox(height: 7),
                  Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 12, fontWeight: FontWeight.w500)),
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
    // 首页整体是深色设计，直播模块也保持深色
    final bgColor = const Color(0xFF1A1A1A);
    final borderColor = Colors.white.withOpacity(0.06);
    final textColor = Colors.white;
    final mutedColor = const Color(0xFFB8B8B8);

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
            Expanded(
              flex: 5,
              child: GestureDetector(
                onTap: primary == null ? null : () => context.go('/player/${primary.id}'),
                child: AspectRatio(
                  aspectRatio: 1.18,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: const Color(0xFF252525),
                      child: Stack(
                        children: [
                          Center(
                            child: primary?.logoUrl != null && primary!.logoUrl!.isNotEmpty
                                ? Image.network(
                                    primary.logoUrl!,
                                    width: 78,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.live_tv_rounded, color: Colors.white70, size: 44),
                                  )
                                : Icon(isLoading ? Icons.hourglass_empty_rounded : Icons.live_tv_rounded, color: Colors.white70, size: 44),
                          ),
                          const Positioned(left: 8, top: 8, child: _Badge(label: '直播中', color: Color(0xFFE53935))),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Text(primary?.displayName ?? '三页直播', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(primary?.displayName ?? (error == null ? '频道加载中' : '加载失败'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Text('12:00', style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 10)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(99),
                                        child: LinearProgressIndicator(
                                          value: 0.62,
                                          minHeight: 3,
                                          color: const Color(0xFFE53935),
                                          backgroundColor: Colors.white.withOpacity(0.20),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('12:30', style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 10)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('正在直播', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (isLoading)
                    const _LiveListText(title: '加载频道中', subtitle: '正在读取本地频道库')
                  else if (channels.isEmpty)
                    const _LiveListText(title: '暂无频道', subtitle: '请检查频道数据')
                  else
                    ...channels.skip(1).take(3).map((ch) => GestureDetector(
                          onTap: () => context.go('/player/${ch.id}'),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 11),
                            child: _LiveListText(title: ch.displayName, subtitle: ch.categories.take(2).join(' · ')),
                          ),
                        )),
                ],
              ),
            ),
          ],
        ),
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
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(subtitle.isEmpty ? '精彩节目直播中' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 11)),
      ],
    );
  }
}

class _ContentSection extends StatelessWidget {
  const _ContentSection({required this.title, required this.items, required this.badges});

  final String title;
  final List<Content> items;
  final List<String> badges;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/search'),
                child: Row(
                  children: [
                    Text('更多', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.55), size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 194,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _PosterCard(
              content: items[index],
              badge: badges[index % badges.length],
            ),
          ),
        ),
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
      onTap: () => context.go('/search'),
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
                  colors: [const Color(0xFF343434), badgeColor.withOpacity(0.32), const Color(0xFF171717)],
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
          Text(content.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(content.subtitle ?? '${content.year ?? '热播'} · ${content.genres.take(2).join(' ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills();

  @override
  Widget build(BuildContext context) {
    const filters = ['全部', '古装', '都市', '悬疑', '科幻', '喜剧'];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final active = index == 0;
          return GestureDetector(
            onTap: active ? null : () => context.go('/search'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? const Color(0x22E53935) : const Color(0xFF242424),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? const Color(0xFFE53935) : Colors.white.withOpacity(0.04)),
              ),
              child: Text(filters[index], style: TextStyle(color: active ? Colors.white : const Color(0xFFD6D6D6), fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            ),
          );
        },
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
