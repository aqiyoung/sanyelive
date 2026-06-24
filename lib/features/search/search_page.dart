import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/typography.dart';
import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../features/favorites/favorite_button.dart';

/// 搜索页 — 模糊匹配频道名/号, 遥控器键盘导航
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();
  String _query = '';
  List<Channel> _results = [];
  int _selectedIndex = 0;
  bool _hasSearched = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final q = _controller.text.trim();
    if (q == _query) return;
    _query = q;
    _selectedIndex = 0;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    // 6/17 fix: await channelsProvider.future — Riverpod 的 FutureProvider
    // 是 lazy 的, SearchPage 没有 watch 它, 用 ref.read 拿到的可能还是
    // AsyncLoading, whenData 是 no-op, setState 永远不触发.
    // 改成 await future, 确保数据到了再 setState.
    final channels = await ref.read(channelsProvider.future);
    if (!mounted) return;
    final results = _fuzzySearch(channels, q);
    setState(() {
      _results = results;
      _hasSearched = true;
      _selectedIndex = 0;
    });
  }

  /// 模糊匹配: 频道名 或 channel id 包含 query (不区分大小写)
  List<Channel> _fuzzySearch(List<Channel> all, String q) {
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    final scored = <({Channel ch, int score})>[];

    for (final c in all) {
      final name = c.name.toLowerCase();
      final id = c.id.toLowerCase();

      // 完全匹配名 → 最高分
      if (name == lower || id == lower) {
        scored.add((ch: c, score: 100));
        continue;
      }
      // 名开头匹配
      if (name.startsWith(lower)) {
        scored.add((ch: c, score: 80));
        continue;
      }
      // id 开头匹配
      if (id.startsWith(lower)) {
        scored.add((ch: c, score: 70));
        continue;
      }
      // 名包含
      if (name.contains(lower)) {
        scored.add((ch: c, score: 50));
        continue;
      }
      // id 包含
      if (id.contains(lower)) {
        scored.add((ch: c, score: 40));
        continue;
      }
      // alt_names 包含
      bool altMatch = false;
      for (final a in c.altNames) {
        if (a.toLowerCase().contains(lower)) {
          altMatch = true;
          break;
        }
      }
      if (altMatch) {
        scored.add((ch: c, score: 30));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.ch).toList();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    setState(() {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_selectedIndex < _results.length - 1) _selectedIndex++;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_selectedIndex > 0) _selectedIndex--;
      } else if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.select) {
        if (_results.isNotEmpty && _selectedIndex < _results.length) {
          _goToPlayer(_results[_selectedIndex]);
        }
      }
    });
  }

  void _goToPlayer(Channel ch) {
    context.push('/player/${ch.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: CustomScrollView(
            slivers: [
              // 搜索栏
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => context.pop(),
                        // 6/18 v0.3.6.1 hotfix: textPrimary → onSurface
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '搜索频道名或频道号…',
                            hintStyle: IptvTypography.body.copyWith(
                              // 6/18 v0.3.6.1 hotfix: textSecondary → onSurfaceVariant
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _controller.clear();
                                    },
                                  )
                                : null,
                          ),
                          style: IptvTypography.body,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // v0.3.8+99 (6/20 14:03 老板反馈): 删 divider, 用 SizedBox 16 代替.
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // 结果列表
              if (!_hasSearched)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        '输入关键词搜索频道',
                        style: IptvTypography.body.copyWith(
                          // 6/18 v0.3.6.1 hotfix: textSecondary → onSurfaceVariant
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else if (_results.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            // 6/18 v0.3.6.1 hotfix: textSecondary → onSurfaceVariant
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '未找到匹配 "$_query" 的频道',
                            style: IptvTypography.body.copyWith(
                              // 6/18 v0.3.6.1 hotfix: textSecondary → onSurfaceVariant
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                // v0.3.8+101 (6/20 15:02 老板反馈): _SearchResultTile 跟
                // ChannelTile 风格统一 (独立容器 + 间隔).  list 加 padding
                // + item 间插 SizedBox(10).  跟 category/favorites 一致.
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final ch = _results[i];
                      final isSelected = i == _selectedIndex;
                      final tile = _SearchResultTile(
                        channel: ch,
                        isSelected: isSelected,
                        channelNumber: (i + 1).toString().padLeft(2, '0'),
                        onTap: () => _goToPlayer(ch),
                      );
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: i == _results.length - 1 ? 0 : 10,
                        ),
                        child: tile,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.channel,
    required this.isSelected,
    required this.channelNumber,
    this.onTap,
  });

  final Channel channel;
  final bool isSelected;
  final String channelNumber;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // v0.3.8+101 (6/20 15:02 老板反馈): 每个 _SearchResultTile 升级为
    // 独立容器 (浅一档米色 + 圆角 12).  选中态: accent 0.08 alpha bg
    // (区分).  非选中: bgElevated (#FFFCF6).  跟 ChannelTile 一致.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                // ignore: deprecated_member_use
                ? accent.withOpacity(0.12)
                : const Color(0xFFFFFCF6), // bgElevated
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  channelNumber,
                  style: IptvTypography.serifTitle.copyWith(
                    color: isSelected
                        ? accent
                        // ignore: deprecated_member_use
                        : accent.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.displayName,
                      style: IptvTypography.sansTitle.copyWith(
                        // 6/18 v0.3.6.1 hotfix: textPrimary → onSurface (x2)
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (channel.country.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${channel.country} · ${channel.primaryCategory}',
                        style: IptvTypography.caption,
                      ),
                    ],
                  ],
                ),
              ),
              FavoriteIcon(
                channelId: channel.id,
                channelName: channel.displayName,
              ),
              if (channel.sources.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
