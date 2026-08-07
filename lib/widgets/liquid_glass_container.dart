import 'package:flutter/material.dart';

/// 液态玻璃容器 — 全 app 卡片统一的玻璃视觉语言.
///
/// 平背景 (主页米色底) 上 BackdropFilter 看不出模糊, 故用
/// 对角渐变底 + 顶部高光 + 底部内阴影 + 细白边 + 圆角阴影 模拟
/// 通透发亮的液态玻璃质感 (非 flat 灰块).
///
/// - [variant] = [LiquidGlassVariant.light]: 浅色白透玻璃片 (内文用深色 fgMain);
///   [LiquidGlassVariant.dark]: 右下深底 (白色台标/白字清晰, 用于频道卡/播放页).
/// - [tint] 给玻璃叠一层色调 (如频道卡用深石板, 播放页用品牌色).
/// - [specular] 顶部高光 + 底部内阴影 (默认开, 营造体积/反光).
/// - [shadow] 圆角外阴影 (默认开).
///
/// 注意: 高光层用 [IgnorePointer] 包裹, 不会拦截点击; TvFocus 的焦点边框
/// 画在 child 外层, 内部换本组件安全 (勿在 TvFocus 与本组件间加 ClipRRect 裁掉边框).
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final LiquidGlassVariant variant;
  final Color? tint;
  final bool specular;
  final bool shadow;
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
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final double r = borderRadius;
    final bool dark = variant == LiquidGlassVariant.dark;

    final List<Color> gradientStops = dark
        ? <Color>[
            const Color(0xBFFFFFFF), // 左上: 亮白高光
            const Color(0x73FFFFFF), // 中上: 半透白
            (tint ?? const Color(0xFF1F2937)).withValues(alpha: 0.82), // 右下: 深底 (台标落此)
          ]
        : <Color>[
            const Color(0xBFFFFFFF), // 左上亮高光
            const Color(0x73FFFFFF), // 中透白
            (tint ?? const Color(0xFFFFFFFF)).withValues(alpha: 0.18), // 右下淡白, 整体白玻璃片
          ];

    final Color borderColor =
        dark ? const Color(0x40FFFFFF) : const Color(0x33FFFFFF);

    final List<BoxShadow>? boxShadow = shadow
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.22 : 0.12),
              blurRadius: dark ? 16 : 14,
              offset: const Offset(0, 7),
            ),
          ]
        : null;

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientStops,
          stops: const <double>[0.0, 0.4, 1.0],
        ),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          children: <Widget>[
            if (padding != null) Padding(padding: padding!, child: child) else child,
            if (specular) ...<Widget>[
              // 顶部高光: 液态玻璃的"反光"
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: r * 1.7,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: dark ? 0.5 : 0.6),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 底部内阴影: 体积感
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: r * 2.1,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: dark ? 0.24 : 0.10),
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
  }
}

enum LiquidGlassVariant { light, dark }
