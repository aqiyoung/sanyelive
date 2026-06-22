// v0.3.8+178 (6/23 B+C splash fix): splash logo + 完整动画.
//
// 之前 v0.3.8+177 简陋版用 Icon(Icons.tv) 矢量框 + Georgia 文字 + 3s 硬等.
// 老板 6/23 05:36 拍板: 换回真 logo (Pixel2Motion 出的 v4 SVG), 完整动画时间线.
//
// 设计目标:
//   - 像素级跟 launcher icon 一致 (同一份矢量源 logo.svg, viewBox 192×192).
//   - 时间线严格按 motion_spec.md / motion.css v2:
//       0-25%   TV body  (scale 0.5 → 1.05 overshoot → 1.0)
//       15-37%  Antennae (extend from TV top edge to top corner)
//       35-55%  Play tri (scale 0.4 → 1.0, ease-out-back)
//       55-90%  Hold
//       90-100% Fade out (整 3s 总时长的最后 10%)
//   - 总展示时长 3s (跟 v0.3.8+177 保持一致).
//   - "黄线" 修复: 整片 splash 用 Material 包, 加 BoxShadow 让红圆角板有阴影
//     边界, 避免 Stack 容器硬切割产生的 1px 横线. 文字已删 (motion spec
//     明确不加文字), 黄线源头消除.
//
// 不依赖 flutter_svg: 本组件用 Flutter primitives (Container / CustomPaint)
// 重组 logo, 保留对每个 SVG 元素独立动画的能力. flutter_svg 只能渲染整张
// 图, 无法分别给 #tv-body / #antenna-left 等加 stagger 动画 — 而 B+C splash
// 需求要 “TV body pop-in + 天线伸展 + 三角 fade-in” 三个独立动效, 只能用
// primitives.
// 源 SVG 坐标映射: viewBox 192×192 → widget 240×240 (×1.25), 每个 SVG 元素
// 在 widget 里都是独立 Positioned + CustomPaint, 1:1 跟 SVG 对齐. SVG 改了
// 需要同步手动改这里. SVG 源文件: /home/liyang/.openclaw/workspace/splash-brand/logo.svg
// (v4 final, IoU 0.8842, 老板 6/23 05:36 拍板接受).
//
// 1.25× scale = SVG 192 → widget 240, 跟 motion.css #logo-root 240px 对齐.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Splash 展示总时长 (3s — 跟 v0.3.8+177 保持一致, 老板实测节奏).
const Duration kSplashDuration = Duration(milliseconds: 3000);

/// Logo 边长 — 240px, 跟 motion.css #logo-root 一致.
const double _kLogoSize = 240.0;

/// SVG 192 → widget 240 = 1.25×.
const double _kScale = _kLogoSize / 192.0;

double _s(double v) => v * _kScale;

/// 三页直播 splash: 暗色背景 + 红圆角 logo plate + 完整动画 + 淡出.
class SanyeliveSplash extends StatefulWidget {
  const SanyeliveSplash({super.key, required this.child});

  /// splash 结束后显示的子 widget (一般是路由页面).
  final Widget child;

  @override
  State<SanyeliveSplash> createState() => _SanyeliveSplashState();
}

class _SanyeliveSplashState extends State<SanyeliveSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _hideTimer;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kSplashDuration,
    );
    _controller.forward();
    // 3s 后隐藏 splash.  controller 已经走完整个 0→1 timeline (含 90-100%
    // fade out).  这里只负责 setState 让 widget 切回 child, 不再画 splash.
    _hideTimer = Timer(kSplashDuration, () {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      children: [
        widget.child,
        // Material 包裹 splash content: 避免 Stack 容器硬边界产生的 1px "黄线"
        // (v0.3.8+177 反馈). Material 自带 surfaceTint + elevation 处理, 没有
        // 裸 Container 那种 sub-pixel 渲染缝隙. Positioned.fill 占满全屏.
        Positioned.fill(
          child: Material(
            color: scheme.surface,
            // clipBehavior anti-alias 避免 child 边缘锯齿 (跟 splash plate 阴影互动).
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value; // 0.0 → 1.0 over 3s.
                return Center(
                  child: Opacity(
                    // 最后 10% (2.7s - 3.0s) 整体淡出 1.0 → 0.0.
                    opacity: t < 0.9 ? 1.0 : (1.0 - (t - 0.9) / 0.1).clamp(0.0, 1.0),
                    child: _SplashLogo(progress: _entranceProgress(t)),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 把 controller.value (0-1, 3s) 映射成 entrance 进度 (0-1, 1.5s = 0-0.5).
  /// 0.0 - 0.5 → 0.0 - 1.0 entrance (linear).
  /// 0.5 - 0.9 → 1.0 (hold).
  /// 0.9 - 1.0 → 1.0 (fade out, opacity 在外面处理).
  double _entranceProgress(double t) {
    if (t >= 0.5) return 1.0;
    return t / 0.5;
  }
}

/// Splash logo 主体: 红圆角 plate + TV body + 天线 + 播放三角.
/// 每个 SVG 元素独立 widget, 按 motion.css v2 时间线各自动画.
class _SplashLogo extends StatelessWidget {
  const _SplashLogo({required this.progress});

  /// 0.0 → 1.0, 走完 entrance 动画 (前 1.5s).
  final double progress;

  // --- 时间线百分比 (0-1, entrance 期) ---
  // TV body: 0-25% scale-pop
  static const _tvOvershoot = 0.12;
  static const _tvSettle = 0.25;

  // Antennae: 15-37% (left starts at 15%, right at 17% for stagger)
  static const _antLeftStart = 0.15;
  static const _antLeftOvershoot = 0.25;
  static const _antLeftSettle = 0.35;
  static const _antRightStart = 0.17;
  static const _antRightOvershoot = 0.27;
  static const _antRightSettle = 0.37;

  // Play triangle: 35-55%
  static const _triStart = 0.35;
  static const _triSettle = 0.55;

  /// 在 [start, settle] 区间做 [0, 1] linear progress.
  double _progressIn(double start, double settle) {
    if (progress < start) return 0.0;
    if (progress > settle) return 1.0;
    return ((progress - start) / (settle - start)).clamp(0.0, 1.0);
  }

  /// 解析 [phaseStart, overshoot, settle] 三段 scale 曲线:
  /// phaseStart → overshoot: scale 0 → 1.1
  /// overshoot → settle: scale 1.1 → 1.0
  /// settle 之后保持 1.0.
  double _antennaScale(double phaseStart, double overshoot, double settle) {
    final p = _progressIn(phaseStart, settle);
    if (p == 0.0) return 0.0;
    if (p < (overshoot - phaseStart) / (settle - phaseStart)) {
      // start → overshoot: 0 → 1.1
      return 1.1 * p / ((overshoot - phaseStart) / (settle - phaseStart));
    } else if (p < 1.0) {
      // overshoot → settle: 1.1 → 1.0
      return 1.1 -
          0.1 *
              ((p - (overshoot - phaseStart) / (settle - phaseStart)) /
                  ((settle - overshoot) / (settle - phaseStart)));
    }
    return 1.0;
  }

  /// TV body scale-pop: 0 → 1.05 (overshoot) → 1.0 (settle).
  double _tvScale() {
    final p = _progressIn(0.0, _tvSettle);
    if (p == 0.0) return 0.5;
    if (p < _tvOvershoot / _tvSettle) {
      return 0.5 + (1.05 - 0.5) * (p / (_tvOvershoot / _tvSettle));
    }
    return 1.05 -
        (1.05 - 1.0) *
            ((p - _tvOvershoot / _tvSettle) /
                ((_tvSettle - _tvOvershoot) / _tvSettle));
  }

  /// Play triangle ease-out-back scale: 0.4 → overshoot (~1.1) → 1.0.
  double _triangleScale() {
    final p = _progressIn(_triStart, _triSettle);
    if (p == 0.0) return 0.4;
    // ease-out-back formula: 1 + c3*(t-1)^3 + c1*(t-1)^2,  c1=1.70158, c3=2.70158
    const c1 = 1.70158;
    const c3 = c1 + 1.0;
    final t = p;
    final eased = 1.0 +
        c3 * math.pow(t - 1.0, 3).toDouble() +
        c1 * math.pow(t - 1.0, 2).toDouble();
    return 0.4 + (1.0 - 0.4) * eased;
  }

  @override
  Widget build(BuildContext context) {
    final tvScale = _tvScale();
    final antLeftScale = _antennaScale(
      _antLeftStart,
      _antLeftOvershoot,
      _antLeftSettle,
    );
    final antRightScale = _antennaScale(
      _antRightStart,
      _antRightOvershoot,
      _antRightSettle,
    );
    final triScale = _triangleScale();
    final tvProgress = _progressIn(0.0, _tvSettle);

    return SizedBox(
      width: _kLogoSize,
      height: _kLogoSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 红圆角 plate (背景). 立刻显示, 不动画.
          Container(
            width: _kLogoSize,
            height: _kLogoSize,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(_s(42)),
              boxShadow: [
                BoxShadow(
                  // 红 plate 阴影 — 避免裸 Container 边界 1px 黄线 (v0.3.8+177 反馈).
                  color: const Color(0xFFE53935).withValues(alpha: 0.25),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
          ),

          // TV body — white-stroke rectangle, scale-pop 0-25%.
          // SVG: rect x=48 y=70 w=96 h=70 rx=8 stroke-width=6.
          Positioned(
            left: _s(48),
            top: _s(70),
            width: _s(96),
            height: _s(70),
            child: Opacity(
              opacity: tvProgress,
              child: Center(
                child: Transform.scale(
                  scale: tvScale,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_s(8)),
                      border: Border.all(
                        color: const Color(0xFFFFFFFF),
                        width: _s(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Antenna left — line from (91, 68) (TV top center, bottom) to
          // (77, 56) (top-left). Extends from bottom toward top-left.
          // SVG 起点位置: x=91 y=68 → widget (_s(91), _s(68)) = (113.75, 85).
          // 终点: (_s(77), _s(56)) = (96.25, 70).
          // CustomPaint 起点 = (0,0), 终点 = (deltaX, deltaY) (相对起点),
          // progress 0→1 让线从起点延伸.
          Positioned(
            left: _s(91),
            top: _s(68),
            child: Opacity(
              opacity: antLeftScale > 0 ? 1.0 : 0.0,
              child: CustomPaint(
                size: Size(
                  _s((77.0 - 91.0).abs()) + _s(6),
                  _s((68.0 - 56.0).abs()) + _s(6),
                ),
                painter: _ExtendLinePainter(
                  start: const Offset(0, 0),
                  end: Offset(_s(77.0 - 91.0), _s(56.0 - 68.0)),
                  progress: antLeftScale,
                  color: const Color(0xFFFFFFFF),
                  strokeWidth: _s(6),
                ),
              ),
            ),
          ),

          // Antenna right — line from (100, 68) to (114, 56).
          Positioned(
            left: _s(100),
            top: _s(68),
            child: Opacity(
              opacity: antRightScale > 0 ? 1.0 : 0.0,
              child: CustomPaint(
                size: Size(
                  _s((114.0 - 100.0).abs()) + _s(6),
                  _s((68.0 - 56.0).abs()) + _s(6),
                ),
                painter: _ExtendLinePainter(
                  start: const Offset(0, 0),
                  end: Offset(_s(114.0 - 100.0), _s(56.0 - 68.0)),
                  progress: antRightScale,
                  color: const Color(0xFFFFFFFF),
                  strokeWidth: _s(6),
                ),
              ),
            ),
          ),

          // Play triangle — SVG path M (86, 90) L (86, 124) L (116, 107) Z.
          // 这是一个右指三角形 (从 (86,90)→(86,124)→(116,107)).
          // bounding box: w=30, h=34, 左上 (86, 90).  几何重心 (10, 17) — 偏左.
          // Scale-pop 从几何重心放大 (Alignment(-0.333, 0) = 重心位置).
          Positioned(
            left: _s(86),
            top: _s(90),
            width: _s(30),
            height: _s(34),
            child: Opacity(
              opacity: triScale > 0.4 ? 1.0 : 0.0,
              child: Transform.scale(
                scale: triScale,
                alignment: const Alignment(-0.333, 0),
                child: CustomPaint(
                  size: Size(_s(30), _s(34)),
                  painter: _TrianglePainter(
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画一根从 start 延伸到 lerp(start, end, progress) 的线.
/// progress=0 → 长度 0 (不可见).
/// progress=1 → 完整 start → end.
class _ExtendLinePainter extends CustomPainter {
  _ExtendLinePainter({
    required this.start,
    required this.end,
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final Offset start;
  final Offset end;
  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final currentEnd =
        Offset.lerp(start, end, progress.clamp(0.0, 1.0))!;
    canvas.drawLine(start, currentEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _ExtendLinePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.start != start ||
      old.end != end;
}

/// 右指三角形 painter. SVG path: M (86,90) L (86,124) L (116,107) Z.
/// 转换到 local widget: (0,0) → (0, h) → (w, h/2) → close.
class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) => old.color != color;
}