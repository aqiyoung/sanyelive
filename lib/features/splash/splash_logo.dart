// v0.3.12+1 (2026-07-07): 视界品牌升级 — 简化 splash, 去掉 TV 直播元素.
//
// 设计变更:
//   - 旧: 红底 + TV body + 天线 + 播放三角 (三页直播风格)
//   - 新: 红底 + 白色播放三角 (视界通用品牌)
//   - 动画简化: 2s total (0.5s scale-in + 1s hold + 0.5s fade-out)
//   - 去掉 CustomPaint / 天线 / TV body, 改用 primitives + Icon
//
// 品牌一致性:
//   - Launcher icon: 同款红底 + 播放三角 (各 mipmap 密度已更新)
//   - App name: "视界" (strings.xml 已更新)

import 'dart:async';
import 'package:flutter/material.dart';

const Duration kSplashMinDuration = Duration(milliseconds: 2000);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _hideTimer;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kSplashMinDuration,
    );
    _controller.forward();
    _hideTimer = Timer(kSplashMinDuration, () {
      if (mounted) setState(() => _hidden = true);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: scheme.surface,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value; // 0.0 → 1.0 over 2s.
                
                // Entrance: 0-0.25 (0.5s) scale 0.6 → 1.0
                // Hold: 0.25-0.75 (1.0s)
                // Fade out: 0.75-1.0 (0.5s)
                double scale;
                if (t < 0.25) {
                  final p = t / 0.25;
                  // ease-out-back approximation
                  scale = 0.6 + 0.4 * (1.0 + 0.2 * (1.0 - p) * (1.0 - p));
                } else {
                  scale = 1.0;
                }
                
                double opacity;
                if (t < 0.75) {
                  opacity = 1.0;
                } else {
                  opacity = 1.0 - (t - 0.75) / 0.25;
                }
                
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: const _SplashLogo(),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE53935).withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 80,
        ),
      ),
    );
  }
}
