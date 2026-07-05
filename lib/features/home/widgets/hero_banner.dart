import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// 顶部大海报轮播 — 自动轮播 + 渐变遮罩 + 播放按钮
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.items,
    this.height = 200,
    this.onItemTap,
  });

  final List<HeroBannerItem> items;
  final double height;
  final void Function(int index)? onItemTap;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  late final PageController _controller;
  int _currentIndex = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.items.length > 1) {
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_currentIndex + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // 轮播内容
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              final item = widget.items[i];
              return GestureDetector(
                onTap: () => widget.onItemTap?.call(i),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景图
                    if (item.backdropUrl != null && item.backdropUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: item.backdropUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildGradientBg(),
                      )
                    else
                      _buildGradientBg(),
                    // 底部渐变遮罩
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                    // 内容
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (item.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: () => widget.onItemTap?.call(i),
                                icon: const Icon(Icons.play_arrow, size: 18),
                                label: const Text('播放'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // 页面指示器
          if (widget.items.length > 1)
            Positioned(
              top: 8,
              right: 16,
              child: Row(
                children: List.generate(widget.items.length, (i) {
                  final active = i == _currentIndex;
                  return Container(
                    margin: const EdgeInsets.only(left: 4),
                    width: active ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGradientBg() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            IptvColors.darkBg,
            IptvColors.darkSurface,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 48,
          color: Colors.white24,
        ),
      ),
    );
  }
}

class HeroBannerItem {
  const HeroBannerItem({
    required this.title,
    this.subtitle,
    this.backdropUrl,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? backdropUrl;
  final VoidCallback? onTap;
}
