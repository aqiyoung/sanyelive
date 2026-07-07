import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/providers/vod_provider.dart';
import '../../../data/models/content.dart';

/// 视界 海报墙首页
class PosterWallPage extends ConsumerWidget {
  const PosterWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: const Color(0xFF101010),
      child: SafeArea(
        bottom: false,
        top: false,
        child: Column(
              children: [
                const _HomeTopBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      const _HeroBanner(),
                      const SizedBox(height: 18),
                      const _VodCategoryTabBar(),
                      const SizedBox(height: 24),
                      _VodSection(
                        title: '今日推荐',
                        provider: vodRecommendedProvider,
                        badges: const ['HOT', 'VIP', '独播'],
                      ),
                      const SizedBox(height: 18),
                      _VodSection(
                        title: '热播电影',
                        provider: vodMoviesProvider,
                        badges: const ['热播', '独播', 'VIP'],
                      ),
                      const SizedBox(height: 18),
                      _VodSection(
                        title: '热播剧集',
                        provider: vodSeriesProvider,
                        badges: const ['独播', 'VIP', '更新'],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
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

/// 视界 角标 — 热播/独播/HOT 等标签
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
                        style: TextStyle(color: Color(0xFFE6E6E6), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _TopIcon(icon: Icons.tune_rounded, onTap: () => context.go('/category/live')),
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

class _VodCategoryTabBar extends ConsumerStatefulWidget {
  const _VodCategoryTabBar();
  @override
  ConsumerState<_VodCategoryTabBar> createState() => _VodCategoryTabBarState();
}

class _VodCategoryTabBarState extends ConsumerState<_VodCategoryTabBar> {
  int _selectedTab = 0;
  int _selectedSub = 0;

  static const _tabs = ['电影', '电视剧', '综艺'];

  // 预置二级分类（后续从 API 动态加载）
  static const _subCategories = [
    ['全部', '动作', '科幻', '喜剧', '爱情', '悬疑', '动画', '犯罪'],
    ['全部', '国产剧', '欧美剧', '日韩剧', '悬疑', '古装', '都市'],
    ['全部', '真人秀', '选秀', '脱口秀', '访谈', '竞技', '生活'],
  ];

  static const _tabTypeIds = [20, 30, 45];

  @override
  Widget build(BuildContext context) {
    final provider = _selectedTab == 0
        ? vodMoviesProvider
        : _selectedTab == 1
            ? vodSeriesProvider
            : vodVarietyProvider;
    final async = ref.watch(provider);
    final subList = _subCategories[_selectedTab];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Tab 栏 ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final active = i == _selectedTab;
              return Padding(
                padding: EdgeInsets.only(right: i < _tabs.length - 1 ? 24 : 0),
                child: GestureDetector(
                  onTap: () => setState(() { _selectedTab = i; _selectedSub = 0; }),
                  child: Column(
                    children: [
                      Text(
                        _tabs[i],
                        style: TextStyle(
                          color: active ? Colors.white : const Color(0xFF9E9E9E),
                          fontSize: 17,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 20,
                        height: 3,
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFFE53935) : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 14),
        // ─── 二级分类标签 ────────────────────────────────────
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: subList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final active = i == _selectedSub;
              return GestureDetector(
                onTap: () => setState(() => _selectedSub = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? const Color(0x22E53935) : const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: active ? const Color(0xFFE53935) : Colors.white.withOpacity(0.04)),
                  ),
                  child: Text(
                    subList[i],
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFFD6D6D6),
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        // ─── 内容区 ────────────────────────────────────────────
        SizedBox(
          height: 194,
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Center(child: Text('暂无内容', style: TextStyle(color: Colors.white54)));
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, index) {
                  const badges = ['热播', '独播', 'VIP', '更新'];
                  return _PosterCard(content: items[index], badge: badges[index % badges.length]);
                },
              );
            },
          ),
        ),
      ],
    );
  }
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
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败: ${e.toString().split("\n").first}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Center(child: Text('暂无内容', style: TextStyle(color: Colors.white54)));
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
