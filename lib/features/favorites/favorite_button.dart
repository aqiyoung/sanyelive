import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import 'favorites_service.dart';

/// 心形收藏按钮 — 点击切换收藏状态
class FavoriteButton extends ConsumerStatefulWidget {
  const FavoriteButton({
    super.key,
    required this.channelId,
    required this.channelName,
    this.size = 24,
  });

  final String channelId;
  final String channelName;
  final double size;

  @override
  ConsumerState<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<FavoriteButton> {
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(favoritesServiceProvider);
    final fav = await svc.isFavorite(widget.channelId);
    if (mounted) setState(() => _isFav = fav);
  }

  Future<void> _toggle() async {
    final svc = ref.read(favoritesServiceProvider);
    final now = await svc.toggle(widget.channelId, widget.channelName);
    if (mounted) {
      setState(() => _isFav = now);
      // 刷新收藏列表
      ref.invalidate(favoritesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isFav ? Icons.favorite : Icons.favorite_border,
        color: _isFav ? IptvColors.accentTerracotta : IptvColors.textSecondary,
        size: widget.size,
      ),
      onPressed: _toggle,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: _isFav ? '取消收藏' : '添加收藏',
    );
  }
}

/// 内联心形 toggle (不单独占按钮, 可嵌入任何 Row)
class FavoriteIcon extends ConsumerStatefulWidget {
  const FavoriteIcon({
    super.key,
    required this.channelId,
    required this.channelName,
    this.size = 20,
    this.onChanged,
  });

  final String channelId;
  final String channelName;
  final double size;
  final void Function(bool isFav)? onChanged;

  @override
  ConsumerState<FavoriteIcon> createState() => _FavoriteIconState();
}

class _FavoriteIconState extends ConsumerState<FavoriteIcon> {
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(favoritesServiceProvider);
    final fav = await svc.isFavorite(widget.channelId);
    if (mounted) setState(() => _isFav = fav);
  }

  Future<void> _toggle() async {
    final svc = ref.read(favoritesServiceProvider);
    final now = await svc.toggle(widget.channelId, widget.channelName);
    if (mounted) {
      setState(() => _isFav = now);
      ref.invalidate(favoritesProvider);
      widget.onChanged?.call(now);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          _isFav ? Icons.favorite : Icons.favorite_border,
          color:
              _isFav ? IptvColors.accentTerracotta : IptvColors.textSecondary,
          size: widget.size,
        ),
      ),
    );
  }
}
