import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';

/// 三页影视 首页 — 海报墙
class PosterWallPage extends StatefulWidget {
  const PosterWallPage({super.key});

  @override
  State<PosterWallPage> createState() => _PosterWallPageState();
}

class _PosterWallPageState extends State<PosterWallPage> {
  int _currentTab = 0;
  List<dynamic>? _channels;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    try {
      // 直接加载 assets, 不用 repository (避免缓存/版本检查导致的崩溃)
      await Future.delayed(const Duration(milliseconds: 300)); // 让 splash 显示
      final raw = await DefaultAssetBundle.of(context)
          .loadString('assets/data/channels_cn.json');
      final decoded = json.decode(raw);
      final list = (decoded as List?) ?? [];
      if (mounted) {
        setState(() => _channels = list);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IptvColors.bgParchment,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            _buildTabs(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          const Text(
            '三页影视',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
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
    );
  }

  Widget _buildTabs() {
    const tabs = ['直播', '点播', '收藏'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = i == _currentTab;
          return GestureDetector(
            onTap: () => setState(() => _currentTab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: active ? Theme.of(context).colorScheme.primary : Colors.transparent,
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
                  color: active ? Colors.white : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text('加载失败', style: TextStyle(fontSize: 16, color: IptvColors.textSecondary)),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 12, color: IptvColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _loadChannels(), child: const Text('重试')),
          ],
        ),
      );
    }

    if (_channels == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _currentTab == 0
        ? _buildLiveScreen()
        : _currentTab == 1
            ? _buildComingSoon('点播', Icons.movie)
            : _buildComingSoon('收藏', Icons.favorite);
  }

  Widget _buildLiveScreen() {
    // 解析分类
    final cctv = <Map>[];
    final satellite = <Map>[];
    final local = <Map>[];

    for (final ch in _channels!) {
      if (ch is! Map) continue;
      final cats = (ch['categories'] as List?)?.cast<String>() ?? [];
      final name = (ch['name'] as String?) ?? (ch['id'] as String? ?? '');
      final logo = ch['logo'] as String?;
      final id = ch['id'] as String? ?? '';
      final item = {'id': id, 'name': name, 'logo': logo};

      if (cats.contains('央视')) {
        cctv.add(item);
      } else if (cats.contains('卫视')) {
        satellite.add(item);
      } else if (cats.contains('地方')) {
        local.add(item);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (cctv.isNotEmpty)
          _buildSection('央视频道', cctv.take(10).toList(),
              () => context.go('/category/cctv')),
        if (satellite.isNotEmpty)
          _buildSection('卫视频道', satellite.take(15).toList(),
              () => context.go('/category/satellite')),
        if (local.isNotEmpty)
          _buildSection('地方频道', local.take(10).toList(),
              () => context.go('/category/local')),
      ],
    );
  }

  Widget _buildSection(String title, List<Map> items, VoidCallback onSeeAll) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cardWidth = MediaQuery.of(context).size.width > 600 ? 130.0 : 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: onSeeAll,
                child: Row(
                  children: [
                    Text('查看全部',
                        style: TextStyle(fontSize: 13, color: IptvColors.textSecondary)),
                    Icon(Icons.chevron_right, size: 18, color: IptvColors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: cardWidth / 0.7 + 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _buildCard(items[i], cardWidth),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Map item, double width) {
    final name = item['name'] as String? ?? '';
    final logo = item['logo'] as String?;
    final id = item['id'] as String? ?? '';
    final h = width / 0.7;

    return GestureDetector(
      onTap: () {
        if (id.isNotEmpty) context.go('/player/$id');
      },
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: width,
                height: h,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      Theme.of(context).colorScheme.primary.withOpacity(0.05),
                    ],
                  ),
                ),
                child: Center(
                  child: logo != null && logo.isNotEmpty
                      ? Image.network(logo,
                          width: width * 0.5,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(name, width))
                      : _buildPlaceholder(name, width),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String name, double width) {
    return Text(
      name.isNotEmpty ? name.substring(0, 1) : '?',
      style: TextStyle(
        fontSize: width * 0.3,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildComingSoon(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: IptvColors.textSecondary),
          const SizedBox(height: 16),
          Text('$title功能开发中…',
              style: const TextStyle(fontSize: 16, color: IptvColors.textSecondary)),
          const SizedBox(height: 8),
          Text('即将上线，敬请期待',
              style: TextStyle(fontSize: 13, color: IptvColors.textSecondary)),
        ],
      ),
    );
  }
}
