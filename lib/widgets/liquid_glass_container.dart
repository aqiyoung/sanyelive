import 'dart:ui';

import 'package:flutter/material.dart';

/// 液态玻璃容器 — 全 app 卡片统一的玻璃视觉语言.
///
/// 核心视觉: 低透明度底色 + 轻微背景模糊(BackdropFilter) + 顶部高光 +
/// 底部内阴影 + 细白边 + 柔和投影, 营造通透发亮的磨砂玻璃质感.
///
/// 之前实现把渐变/底色 alpha 设得太高(深色 0xD21F2937 ≈ 82%, 高光白 0xBF ≈
/// 75%), 导致卡片看起来是实心的灰块, 完全不像玻璃. 现在把透明度压到
/// 22~38%, 让背后的米色/深色页面能透过来, 配合 BackdropFilter 的轻微
/// 模糊, 才是真正的"半透明玻璃片".
///
/// - [variant] = [LiquidGlassVariant.light]: 浅色白透玻璃片, 文字/图标用
///   深色; [LiquidGlassVariant.dark]: 深色透底玻璃片, 白色台标/文字清晰.
/// - [tint] 给玻璃叠一层色调(如选中态用 accent, 频道卡用深石板).
/// - [specular] 顶部高光 + 底部内阴影 (营造体积/反光).
/// - [shadow] 圆角外阴影.
/// - [blur] 是否启用 BackdropFilter 背景模糊(默认 true, TV/低端机可关).
///
/// 注意: 高光层用 [IgnorePointer] 包裹, 不会拦截点击; TvFocus 的焦点边框
/// 画在 child 外层, 内部换本组件安全(勿在 TvFocus 与本组件间加 ClipRRect
/// 裁掉边框).
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final LiquidGlassVariant variant;
  final Color? tint;
  final bool specular;
  final bool shadow;
  final bool blur;
  final double? width;
  final double? height;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.margin,
    this.variant = LiquidGlassVariant.light,
    this.tint,
    this.specular = true,
    this.shadow = true,
    this.blur = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final double r = borderRadius;
    final bool dark = variant == LiquidGlassVariant.dark;

    // 玻璃底色: 低透明度, 让背景能透过来, 才像真正的玻璃片.
    final Color baseColor = dark
        ? (tint ?? const Color(0xFF1F2937)).withValues(alpha: 0.40)
        : (tint ?? Colors.white).withValues(alpha: 0.22);

    final Color borderColor = dark
        ? Colors.white.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.45);

    final List<BoxShadow>? boxShadow = shadow
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.18 : 0.08),
              blurRadius: dark ? 14 : 12,
              offset: const Offset(0, 6),
            ),
          ]
        : null;

    Widget glass = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        color: baseColor,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          children: <Widget>[
            if (padding != null) Padding(padding: padding!, child: child) else child,
            if (specular) ...<Widget>[
              // 顶部高光: 玻璃表面的"反光".
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: r * 1.5,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: dark ? 0.22 : 0.35),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 底部内阴影: 增加体积感.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: r * 1.8,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: dark ? 0.16 : 0.06),
                          Colors.black.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // 背景模糊: 让玻璃背后的内容呈现磨砂感. 在 Uniform 背景上效果较淡,
    // 但有彩色/图案背景时会很明显; 即使 uniform 背景, blur 也能让玻璃
    // 边缘更柔和.
    if (blur) {
      glass = ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: glass,
        ),
      );
    }

    return glass;
  }
}

enum LiquidGlassVariant { light, dark }
