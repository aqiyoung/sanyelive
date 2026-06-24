import 'dart:ui';

import 'package:flutter/material.dart';

/// 轻玻璃容器 — P1-1 ChatGPT 6/17 建议
///
/// 设计规范:
/// - blur: sigma 12 (10-15 区间)
/// - border: 1px 白色, opacity 0.12
/// - borderRadius: 12 (12-16 区间)
/// - hover: scale 1.03, 200ms ease
///
/// 用于播放页浮层 (NowNextProgram / NextChannelsStrip / SourcePickerSheet),
/// 背后有视频画面时 blur 效果最明显.
/// 主页卡片 (CategoryCard) 用 [GlassCardBorder] 包裹即可 (暖米色背景 blur 无意义).
class GlassContainer extends StatefulWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.blurSigma = 12,
    this.onTap,
    this.padding,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: widget.blurSigma,
          sigmaY: widget.blurSigma,
        ),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            // 半透明白底 — 让 blur 效果可见
            color:
                Colors.white.withOpacity(0.06), // ignore: deprecated_member_use
            borderRadius: BorderRadius.circular(widget.borderRadius),
            // v0.3.7+69 (6/19): 边框用 theme.outlineVariant 0.4 alpha,  浅色
            // 主题下能看见 (之前 Colors.white 0.12 在浅米色背景上几乎透明,
            // 老板反馈 "浅色模式的首页频道分类的边框没有了").  暗色下也保留
            // outlineVariant (M3 标准) 0.4 alpha = 跟分割线风格统一.
          ),
          child: widget.child,
        ),
      ),
    );

    content = MouseRegion(
      onEnter: (_) => _ctl.forward(),
      onExit: (_) => _ctl.reverse(),
      child: ScaleTransition(scale: _scale, child: content),
    );

    if (widget.onTap != null) {
      content = GestureDetector(onTap: widget.onTap, child: content);
    }

    return content;
  }
}

/// 轻玻璃卡片边框 — 无 blur, 仅白边 + hover scale
///
/// 用于主页卡片 (暖米色背景, 不需要 blur).
/// 设计: 1px 白边 (opacity 0.12) + hover scale 1.03, 200ms ease.
class GlassCardBorder extends StatefulWidget {
  const GlassCardBorder({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.onTap,
  });

  final Widget child;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  State<GlassCardBorder> createState() => _GlassCardBorderState();
}

class _GlassCardBorderState extends State<GlassCardBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = MouseRegion(
      onEnter: (_) => _ctl.forward(),
      onExit: (_) => _ctl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            // v0.3.7+69 (6/19): 边框用 theme.outlineVariant 0.4 alpha,  浅色
            // 主题下能看见 (之前 Colors.white 0.12 在浅米色背景上几乎透明,
            // 老板反馈 "浅色模式的首页频道分类的边框没有了").  暗色下也保留
            // outlineVariant (M3 标准) 0.4 alpha = 跟分割线风格统一.
          ),
          child: widget.child,
        ),
      ),
    );

    if (widget.onTap != null) {
      content = GestureDetector(onTap: widget.onTap, child: content);
    }

    return content;
  }
}
