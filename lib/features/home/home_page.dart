import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/version_checker.dart';
import '../favorites/favorites_service.dart';
import 'poster_wall_page.dart';

/// 三页影视主页 — 外层统一管理底部导航
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
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
            onPrimary: () => context.go('/category/cctv'),
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
        color: const Color(0xFF151515).withOpacity(0.94),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
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
              selectedItemColor: const Color(0xFFE53935),
              unselectedItemColor: const Color(0xFF8E8E8E),
              showSelectedLabels: true,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined, size: 23),
                  activeIcon: Icon(Icons.home_rounded, size: 23),
                  label: '首页',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.smart_display_outlined, size: 23),
                  activeIcon: Icon(Icons.smart_display_rounded, size: 23),
                  label: '短视频',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.workspace_premium_outlined, size: 23),
                  activeIcon: Icon(Icons.workspace_premium_rounded, size: 23),
                  label: '会员',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.explore_outlined, size: 23),
                  activeIcon: Icon(Icons.explore_rounded, size: 23),
                  label: '发现',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded, size: 23),
                  activeIcon: Icon(Icons.person_rounded, size: 23),
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
    final favorites = ref.watch(favoritesProvider);
    final version = ref.watch(currentVersionStringProvider);

    return ColoredBox(
      color: const Color(0xFF101010),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('三页影视', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text('极简 IPTV · Beta $version', style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: '我的收藏',
                    value: favorites.maybeWhen(data: (ids) => '${ids.length}', orElse: () => '0'),
                    icon: Icons.favorite_rounded,
                    onTap: () => context.go('/favorites'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: '直播频道',
                    value: '央视',
                    icon: Icons.live_tv_rounded,
                    onTap: () => context.go('/category/cctv'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _MineTile(icon: Icons.search_rounded, title: '搜索节目', subtitle: '快速查找频道和内容', onTap: () => context.go('/search')),
            _MineTile(icon: Icons.favorite_border_rounded, title: '我的收藏', subtitle: '查看已收藏的直播频道', onTap: () => context.go('/favorites')),
            _MineTile(icon: Icons.tv_rounded, title: '电视频道', subtitle: '央视 / 卫视 / 体育 / 娱乐', onTap: () => context.go('/category/cctv')),
            _MineTile(icon: Icons.settings_rounded, title: '设置', subtitle: '主题、更新、版本信息', onTap: () => context.go('/settings')),
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
      color: const Color(0xFF101010),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: const Color(0xFFE53935), size: 52),
                  const SizedBox(height: 14),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14, height: 1.5)),
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFE53935), size: 24),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
          ],
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
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFE53935), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF6E6E6E)),
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
          color: const Color(0xFFE53935),
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
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
