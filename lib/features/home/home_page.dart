import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sanyelive/widgets/liquid_glass_container.dart';
import '../../../core/theme/colors.dart';
import '../settings/app_mode_provider.dart';
import 'poster_wall_page.dart';

/// 视界主页 — 外层统一管理底部导航
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  /// 根据模式构建底部导航项 + 对应页面.
  /// 电视直播模式 (默认): 仅 [首页, 我的].
  /// 完整功能模式: [首页, 短视频, 会员, 发现, 我的].
  List<_NavItem> _navItems() {
    final live = _NavItem(
      icon: Icons.home_outlined,
      activeIcon: const Icon(Icons.home_rounded, size: 24, weight: 700),
      label: '首页',
      page: const PosterWallPage(),
    );
    final mine = _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: const Icon(Icons.person_rounded, size: 24, weight: 700),
      label: '我的',
      page: const _MinePage(),
    );
    if (!ref.read(appModeProvider)) {
      return [live, mine];
    }
    return [
      live,
      _NavItem(
        icon: Icons.smart_display_outlined,
        activeIcon: const Icon(Icons.smart_display_rounded, size: 24, weight: 700),
        label: '短视频',
        page: _ActionHubPage(
          title: '短视频',
          subtitle: '短视频频道还没接入，先为你打开搜索。',
          icon: Icons.smart_display_rounded,
          primaryLabel: '去搜索内容',
          onPrimary: () => context.go('/search'),
        ),
      ),
      _NavItem(
        icon: Icons.workspace_premium_outlined,
        activeIcon: const Icon(Icons.workspace_premium_rounded, size: 24, weight: 700),
        label: '会员',
        page: _ActionHubPage(
          title: '会员',
          subtitle: '会员体系暂未上线，当前所有直播入口都可直接使用。',
          icon: Icons.workspace_premium_rounded,
          primaryLabel: '看电视直播',
          onPrimary: () => context.go('/category/live'),
        ),
      ),
      _NavItem(
        icon: Icons.explore_outlined,
        activeIcon: const Icon(Icons.explore_rounded, size: 24, weight: 700),
        label: '发现',
        page: _ActionHubPage(
          title: '发现',
          subtitle: '发现页先聚合频道分类，后续再接专题内容。',
          icon: Icons.explore_rounded,
          primaryLabel: '浏览体育频道',
          onPrimary: () => context.go('/category/体育'),
          secondaryLabel: '浏览娱乐频道',
          onSecondary: () => context.go('/category/娱乐'),
        ),
      ),
      mine,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 监听模式变化 → 导航项数量会变, 需钳制 _currentIndex 防越界.
    ref.watch(appModeProvider);
    final items = _navItems();
    final safeIndex = _currentIndex.clamp(0, items.length - 1);

    final overlay = _resolveOverlay(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
      backgroundColor: context.bgBase,
      body: IndexedStack(
        index: safeIndex,
        children: items.map((e) => e.page).toList(),
      ),
      bottomNavigationBar: _StreamingBottomNav(
        currentIndex: safeIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: items,
      ),
    ),
    );
  }

  SystemUiOverlayStyle _resolveOverlay(BuildContext context) {
    final isDark = context.appBrightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: context.bgBase,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.page,
  });
  final IconData icon;
  final Widget activeIcon;
  final String label;
  final Widget page;
}

class _StreamingBottomNav extends StatelessWidget {
  const _StreamingBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassContainer(
      variant: LiquidGlassVariant.light,
      borderRadius: 0,
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          backgroundColor: Colors.transparent,
          elevation: 0,
          // 选中=强调色 (赤陶, 主题主色), 未选中=次文字色 (比硬编码灰色深, 看得清)
          // 两套颜色都走 Theme, 深浅色自动适配.
          selectedItemColor: context.fgAccent,
          unselectedItemColor: context.fgSub,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: items
              .map((e) => BottomNavigationBarItem(
                    icon: Icon(e.icon, size: 24),
                    activeIcon: e.activeIcon,
                    label: e.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _MinePage extends ConsumerWidget {
  const _MinePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fullMode = ref.watch(appModeProvider);
    return ColoredBox(
      color: context.bgBase,
      child: SafeArea(
        bottom: false,
        top: true,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icons/app_logo.png',
                        width: 72,
                        height: 72,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '视界',
                        style: TextStyle(
                          color: context.fgMain,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fullMode ? '全新品牌升级 • 直播 + 影视' : '专注电视直播',
                        style: TextStyle(
                          color: context.fgSub,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 电视频道置顶 (TV 模式主打); 搜索仅在完整功能模式出现.
            _MineTile(icon: Icons.tv_rounded, title: '电视频道', subtitle: '央视 / 卫视 / 体育 / 地方直播', onTap: () => context.go('/category/live')),
            if (fullMode)
              _MineTile(icon: Icons.search_rounded, title: '搜索节目', subtitle: '搜索频道、视频内容', onTap: () => context.go('/search')),
            _MineTile(icon: Icons.favorite_border_rounded, title: '我的收藏', subtitle: '收藏的直播频道', onTap: () => context.go('/favorites')),
            _MineTile(icon: Icons.settings_rounded, title: '设置', subtitle: '主题、更新、关于', onTap: () => context.go('/settings')),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('最近浏览', style: TextStyle(color: context.fgMain, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: fullMode ? 8 : 4,
                itemBuilder: (context, index) {
                  // TV 模式只展示直播卡片, 隐藏视频占位.
                  final isLive = fullMode ? (index % 2 == 0) : true;
                  return LiquidGlassContainer(
                    variant: LiquidGlassVariant.light,
                    borderRadius: 14,
                    width: 110,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 70,
                          decoration: BoxDecoration(
                            color: context.bgCardHigh,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                          ),
                          child: Center(
                            child: Icon(
                              isLive ? Icons.live_tv_rounded : Icons.movie_rounded,
                              color: context.fgSub,
                              size: 28,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: context.fgAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  isLive ? '直播' : '视频',
                                  style: TextStyle(color: context.fgAccent, fontSize: 9, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 3, 8, 6),
                          child: Text(
                            isLive ? '频道名称' : '视频标题',
                            style: TextStyle(color: context.fgMain, fontSize: 11, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
    );
  }
}

class _ActionHubPage extends StatelessWidget {
  const _ActionHubPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.bgBase,
      child: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 24),
              child: LiquidGlassContainer(
                variant: LiquidGlassVariant.light,
                borderRadius: 24,
                padding: const EdgeInsets.all(22),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: context.fgAccent, size: 52),
                  const SizedBox(height: 14),
                  Text(title, style: TextStyle(color: context.fgMain, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: context.fgSub, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 18),
                  _PrimaryButton(label: primaryLabel, onTap: onPrimary),
                  if (secondaryLabel != null && onSecondary != null) ...[
                    const SizedBox(height: 10),
                    _SecondaryButton(label: secondaryLabel!, onTap: onSecondary!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MineTile extends StatelessWidget {
  const _MineTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: context.fgAccent.withValues(alpha: 0.08),
        highlightColor: context.fgAccent.withValues(alpha: 0.04),
          child: LiquidGlassContainer(
            variant: LiquidGlassVariant.light,
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
            children: [
              Icon(icon, color: context.fgAccent, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: context.fgMain, fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: context.fgSub, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.fgSub),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.light,
        borderRadius: 16,
        tint: context.fgAccent,
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: SizedBox(
          width: double.infinity,
          child: Center(
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.light,
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: SizedBox(
          width: double.infinity,
          child: Center(
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.fgMain, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}
