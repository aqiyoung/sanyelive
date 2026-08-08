//
// 设计变更:
//   - 旧 v1: 红底 + Icons.play_arrow_rounded (Flutter primitive)
//   - 新 v2: GPT 设计原图 (红→深紫渐变 + 白三角 + 3D 光泽)
//   - 动画: 2s total (0.5s scale-in 0.5→1.0 overshoot + 1s hold + 0.5s fade-out)
//   - Asset: assets/icons/app_logo.png (v0.3.12.110 替换 — 深蓝底 IPTV 风格图标,
//     带播放三角 / TV 框 / 信号波纹, 透明背景)

import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

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
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: Material(
              color: scheme.surface,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  double scale;
                  if (t < 0.25) {
                    final p = t / 0.25;
                    scale = 0.5 + 0.5 * (1.0 + 0.2 * (1.0 - p) * (1.0 - p));
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
      ),
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: context.fgAccent.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
                  child: Image.asset(
                    'assets/icons/app_logo.png',
                    width: 180,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
        ),
      ),
    );
  }
}