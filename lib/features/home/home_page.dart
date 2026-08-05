import 'dart:ui';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import 'poster_wall_page.dart';

/// 视界主页 — 外层统一管理底部导航
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final overlay = _resolveOverlay(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
      backgroundColor: context.bgBase,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const PosterWallPage(),
          _ActionHubPage(
            title: '短视频',
            subtitle: '短视频频道还没接入，先为你打开搜索。',
            icon: Icons.smart_display_rounded,
            primaryLabel: '去搜索内容',
            onPrimary: () => context.go('/search'),
          ),
          _ActionHubPage(
            title: '会员',
            subtitle: '会员体系暂未上线，当前所有直播入口都可直接使用。',
            icon: Icons.workspace_premium_rounded,
            primaryLabel: '看电视直播',
            onPrimary: () => context.go('/category/live'),
          ),
          _ActionHubPage(
            title: '发现',
            subtitle: '发现页先聚合频道分类，后续再接专题内容。',
            icon: Icons.explore_rounded,
            primaryLabel: '浏览体育频道',
            onPrimary: () => context.go('/category/体育'),
            secondaryLabel: '浏览娱乐频道',
            onSecondary: () => context.go('/category/娱乐'),
          ),
          const _MinePage(),
        ],
      ),
      bottomNavigationBar: _StreamingBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
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

class _StreamingBottomNav extends StatelessWidget {
  const _StreamingBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.bgBase.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: context.fgBorder)),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SafeArea(
            top: false,
            child: BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: onTap,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: Colors.red.shade600,
              unselectedItemColor: Colors.grey.shade400,
              showSelectedLabels: true,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined, size: 24),
                  activeIcon: Icon(Icons.home_rounded, size: 24, weight: 700),
                  label: '首页',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.smart_display_outlined, size: 24),
                  activeIcon: Icon(Icons.smart_display_rounded, size: 24, weight: 700),
                  label: '短视频',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.workspace_premium_outlined, size: 24),
                  activeIcon: Icon(Icons.workspace_premium_rounded, size: 24, weight: 700),
                  label: '会员',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.explore_outlined, size: 24),
                  activeIcon: Icon(Icons.explore_rounded, size: 24, weight: 700),
                  label: '发现',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded, size: 24),
                  activeIcon: Icon(Icons.person_rounded, size: 24, weight: 700),
                  label: '我的',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MinePage extends ConsumerWidget {
  const _MinePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/icons/shijie_logo.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
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
                        '全新品牌升级 • 直播 + 影视',
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
            _MineTile(icon: Icons.search_rounded, title: '搜索节目', subtitle: '搜索频道、视频内容', onTap: () => context.go('/search')),
            _MineTile(icon: Icons.favorite_border_rounded, title: '我的收藏', subtitle: '收藏的直播频道和视频', onTap: () => context.go('/favorites')),
            _MineTile(icon: Icons.tv_rounded, title: '电视频道', subtitle: '央视 / 卫视 / 体育 / 娱乐直播', onTap: () => context.go('/category/live')),
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
                itemCount: 8,
                itemBuilder: (context, index) {
                  final isLive = index % 2 == 0;
                  return Container(
                    width: 110,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.fgBorder),
                    ),
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
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.fgBorder),
              ),
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.fgBorder),
          ),
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
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: context.fgAccent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
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
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: context.bgCardHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.fgBorder),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: context.fgMain, fontSize: 14, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
