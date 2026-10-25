import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

/// 液态玻璃容器 — 全 app 卡片统一的玻璃视觉语言 (iOS 26/27 Liquid Glass 风格).
///
/// iOS 27 redesign 原则 (见 widgets/glass_kit.dart):
///   - 玻璃只做「控件层」: 导航条、悬浮按钮、播放器浮层、弹窗, 不做内容层.
///     内容卡片 (频道墙、节目单正文) 保持清晰可读, 不被整面玻璃糊住.
///   - 半径统一放大: 卡片 24、导航/悬浮条 32、胶囊按钮 999, 贴合圆角硬件.
///   - 明暗自适应: 新增 [LiquidGlassVariant.auto], 按当前 Theme 亮度选
///     light/dark, 避免暗色下仍用白玻璃、浅色下仍用深玻璃.
///
/// 视觉构成 (从内到外):
///   1. 半透明玻璃底色 (对角渐变, 顶部更亮) —— 让背景透出来;
///   2. [blur] BackdropFilter 背景磨砂模糊 —— 玻璃对背后内容的"折射"感;
///   3. [specular] 顶部凝聚高光带 + 底部内阴影 —— 玻璃表面的反光与厚度;
///   4. [rim] 渐变描边 (rim-light) —— 这是 iOS 26 的招牌: 玻璃边缘自上而下的
///      亮线 (顶部最亮, 底部隐去), 模拟边缘捕捉环境光, 让卡片"发光"而非灰块;
///   5. [shadow] 柔和投影 —— 把玻璃片从背景里托起来.
///
/// 之前实现只有"磨砂玻璃片" (透底 + 模糊 + 均匀白边 + 高光), 缺少 rim-light,
/// 在浅色 parchment 上仍偏灰塑料. 现在补上边缘高光环 + 更强磨砂, 才接近
/// iOS 26 那种"通透会发光的玻璃".
///
/// - [variant] light: 浅色白透玻璃, 文字/图标用深色; dark: 深色透底玻璃,
///   白色台标/文字清晰 (仅用于真正深色背景, 如播放页浮层).
/// - [tint] 给玻璃叠一层色调 (选中态用 accent, 频道卡用深石板).
/// - [specular]/[shadow]/[blur]/[rim] 分别控制高光 / 投影 / 模糊 / 边缘光,
///   默认全开; TV / 低端机可关 [blur] 或 [rim] 降开销.
///
/// 注意: 高光/边缘光层用 [IgnorePointer] 包裹, 不会拦截点击; TvFocus 的焦点
/// 边框画在 child 外层, 内部换本组件安全 (勿在 TvFocus 与本组件间加 ClipRRect
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
  final bool rim;
  final double? width;
  final double? height;

  /// iOS 27 Dock / 悬浮底栏用的「透明玻璃」: 底色更稀 (顶部 0.14 /
  /// 底部 0.07)、投影更淡, 透过它能清楚看到背后内容, 而不是一块
  /// 半实心白板. 配合强模糊 (建议 blurSigma 28) 才有「清玻璃」
  /// 的感觉: 透, 但背后是磨砂的, 不是直接穿透的透明塑料.
  final bool clear;

  /// 贴底全宽底栏用的「加浓玻璃」: 在实色背景 (如宣纸底色) 上,
  /// 正常浓度 (0.34 / 0.16) 的白玻璃几乎看不出来, 底栏会像
  /// 恢复成原来的普通底栏. strong 把填充提到 0.92 / 0.80,
  /// 让底栏在实色背景上也一眼就是一条玻璃栏, 同时仍透光、
  /// 仍有磨砂模糊, 不是实心白板.
  final bool strong;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding,
    this.margin,
    this.variant = LiquidGlassVariant.light,
    this.tint,
    this.specular = true,
    this.shadow = true,
    this.blur = true,
    this.rim = true,
    this.width,
    this.height,
    this.blurSigma = 20,
    this.clear = false,
    this.strong = false,
  });

  /// 背景模糊强度. iOS 27 的玻璃比旧版更通透: 默认 20, 播放器浮层等
  /// 需要更清晰时可降到 12; TV / 低端机可传 0 关掉模糊只留描边.
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final double r = borderRadius;
    final bool dark = variant == LiquidGlassVariant.dark ||
        (variant == LiquidGlassVariant.auto &&
            Theme.of(context).brightness == Brightness.dark);

    // 玻璃底色: 极低透明度对角渐变, 顶部更亮, 让背景明显透过来并带"折射"光泽.
    // clear 模式 (Dock) 再稀一倍多, 背后内容几乎原样透出.
    final Color fillTop = (tint ?? (dark ? const Color(0xFF3A4654) : Colors.white))
        .withValues(alpha: strong ? (dark ? 0.85 : 0.92) : clear ? 0.14 : (dark ? 0.30 : 0.34));
    final Color fillBottom = (tint ?? (dark ? const Color(0xFF1B2230) : Colors.white))
        .withValues(alpha: strong ? (dark ? 0.70 : 0.80) : clear ? 0.07 : (dark ? 0.14 : 0.16));

    final List<BoxShadow>? boxShadow = shadow
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(
                  alpha: strong ? (dark ? 0.25 : 0.14) : clear ? 0.05 : (dark ? 0.18 : 0.08)),
              blurRadius: dark ? 18 : 16,
              offset: const Offset(0, 8),
            ),
          ]
        : null;

    Widget glass = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[fillTop, fillBottom],
        ),
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          children: <Widget>[
            if (padding != null) Padding(padding: padding!, child: child) else child,
            if (specular) ...<Widget>[
              // 顶部高光: 凝聚在顶部边缘的亮带, 模拟玻璃表面反光.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: r * 1.6,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: dark ? 0.22 : 0.50),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 底部内阴影: 增加玻璃厚度感, 但保持很淡以免显脏.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: r * 1.4,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: dark ? 0.18 : 0.06),
                          Colors.black.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (rim)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GlassRimPainter(radius: r, dark: dark, tint: tint),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // 背景模糊: 让玻璃背后的内容呈现磨砂感, 是"液态玻璃"认知的核心.
    if (blur && blurSigma > 0) {
      glass = ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: glass,
        ),
      );
    }

    return glass;
  }
}

/// 玻璃边缘高光 (rim-light) 画家: 沿圆角矩形描一条渐变亮线 —— 顶部最亮、
/// 向下淡出. 这是 iOS 26 液态玻璃"边缘会发光"的招牌效果, 普通 1px 均匀白边
/// 做不到这种体积感.
class _GlassRimPainter extends CustomPainter {
  final double radius;
  final bool dark;
  final Color? tint;

  const _GlassRimPainter({required this.radius, required this.dark, this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Color top = (tint ?? Colors.white).withValues(alpha: dark ? 0.55 : 0.92);
    final Color bottom = (tint ?? Colors.white).withValues(alpha: dark ? 0.12 : 0.30);
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[top, bottom],
    ).createShader(Offset.zero & size);
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter old) =>
      old.radius != radius || old.dark != dark || old.tint != tint;
}

enum LiquidGlassVariant {
  light,
  dark,

  /// 按当前 Theme 亮度自动选 light/dark. 导航条、播放器浮层等跨主题
  /// 控件优先用 auto, 避免硬编码 light 在暗色下过曝.
  auto,
}

/// 玻璃对话框 — 与 [AlertDialog] 同接口 (title / content / actions), 但整体
/// 渲染在一块液态玻璃面板上, 而不是实心 surface. 用于替换全 app 的
/// AlertDialog / BottomSheet 背景, 让浮层也拥有 iOS 26 通透玻璃质感.
///
/// 用法: 把 `AlertDialog(` 直接换成 `GlassDialog(`, 其余 title/content/actions
/// 原样保留即可; 同时把外层 `showDialog` 的 barrier 调暗一点更出彩.
class GlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;
  final LiquidGlassVariant variant;
  final double borderRadius;
  final bool scrollable;
  final double maxWidth;

  const GlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
    this.variant = LiquidGlassVariant.light,
    this.borderRadius = 24,
    this.scrollable = false,
    this.maxWidth = 320,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    if (title != null) {
      children.add(
        Padding(
          padding: titlePadding ?? const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.titleLarge!,
            child: title!,
          ),
        ),
      );
    }
    if (content != null) {
      children.add(
        Padding(
          padding: contentPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: scrollable ? SingleChildScrollView(child: content!) : content!,
          ),
        ),
      );
    }
    if (actions != null && actions!.isNotEmpty) {
      children.add(
        Padding(
          padding: actionsPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions!,
          ),
        ),
      );
    }
    // 关键: 给玻璃面板一个「紧宽度」(tight width), 而不是宽松的 maxWidth.
    // LiquidGlassContainer 内部有 BackdropFilter, 在宽松约束下会向父级撑满可用
    // 空间, 把弹窗拉成全屏. 这里用 SizedBox 强制一个明确的宽度 (≤ maxWidth,
    // 且始终留 24px 边距), 让 BackdropFilter 无处可撑, 弹窗必为小窗.
    final double screenW = MediaQuery.of(context).size.width;
    final double dialogW = min(maxWidth, screenW - 48);
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: dialogW,
        child: Material(
          type: MaterialType.transparency,
          child: LiquidGlassContainer(
            variant: variant,
            borderRadius: borderRadius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
