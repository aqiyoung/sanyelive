import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import 'liquid_glass_container.dart';

/// iOS 27 Liquid Glass 设计系统 — 控件层专用.
///
/// 层级规则 (Apple HIG 的核心, 也是本项目旧 UI 最容易犯的错):
///   1. 内容在下, 控件在上: 玻璃只给导航条、悬浮按钮、播放器浮层、弹窗.
///      频道墙、节目单、列表正文不做整面玻璃, 保证可读性.
///   2. 一屏最多两层玻璃: 顶栏 + 底栏, 或播放器顶栏 + 底部浮层, 不叠第三层.
///   3. 视频上方用 dark 玻璃, 浅色页面用 auto 玻璃, 亮度自适应.
///   4. 动效只做「按压回弹 + 显隐淡入」, 不做玻璃变形/流动, 避免 TV 遥控
///      操作下眩晕, 也避免 BackdropFilter 在视频上叠加的性能开销.
///
/// 品牌保留: 宣纸米色底 + 赤陶强调色 + Georgia 衬线标题不变, 玻璃只是
/// 把原来「实心条 / 灰块」换成「通透浮层」, 不是换一套新品牌.
class GlassRadius {
  GlassRadius._();

  /// 内容卡片.
  static const double card = 24;

  /// 导航条、悬浮条、底部浮层.
  static const double bar = 32;

  /// 胶囊按钮、胶囊标签.
  static const double pill = 999;
}

/// 悬浮玻璃条 — 首页顶栏、底部导航、播放器顶栏/底部浮层的统一外壳.
///
/// 用法: GlassBar(child: Row(...)) 即可, 内边距、圆角、明暗自适应已定好;
/// 不要在 GlassBar 外再套一层 LiquidGlassContainer, 避免双层模糊.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.variant = LiquidGlassVariant.auto,
    this.blurSigma = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final LiquidGlassVariant variant;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassContainer(
      variant: variant,
      borderRadius: GlassRadius.bar,
      margin: margin,
      padding: padding,
      blurSigma: blurSigma,
      child: child,
    );
  }
}

/// iOS 27 Dock 栏 — 首页底部导航的 Dock 形态, 不是贴底全宽条.
///
/// 跟普通 GlassBar 的区别:
///   1. 居中收窄: 宽度按 tab 数算 (每项约 76px), 5 个 tab 约 380px,
///      两边留空, 像 iPhone 主屏 Dock 那样「浮」在内容上, 而不是
///      一条横贯屏幕的底边.
///   2. 透明玻璃 (clear): 底色稀到 0.14/0.07 + 强模糊 28, 背后频道墙 /
///      海报能透出来, 但磨砂后不会跟图标混在一起.
///   3. 悬浮在内容上: 配合 Scaffold.extendBody = true 使用, 内容从
///      Dock 后面透过去; 调用方必须给各页列表底部留 120px padding,
///      否则最后一行会被 Dock 盖住.
///   4. 仍用 BottomNavigationBar 做子组件, TV 遥控焦点、语义、选中态
///      逻辑都不变, 只是把它放进一个居中的透明玻璃壳里.
class GlassDock extends StatelessWidget {
  const GlassDock({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 贴底全宽底栏: 占满横向、贴着底部边缘, 不居中、不悬浮.
    // 关键教训: 宣纸底色 (#F5F4ED) 本来就接近白色, 白玻璃
    // (哪怕加浓到 0.92) 铺在上面也几乎看不出来, 截图里就
    // 像没有栏、只有两个图标. 所以底栏必须有自己的边缘:
    // 顶部一条深色分界线 + 顶部柔和阴影 + 略深的暖灰底色,
    // 三者一起才在实色背景上划出一条看得见的栏.
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.14),
            width: 1,
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          width: double.infinity,
          child: LiquidGlassContainer(
            variant: LiquidGlassVariant.auto,
            borderRadius: 0,
            blurSigma: 20,
            strong: true,
            tint: const Color(0xFFE9E7E0),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 按压回弹 — iOS 27 控件的标准反馈: 按下缩到 0.96, 松开弹回.
///
/// 只做缩放, 不做颜色/透明度变化, 在视频浮层上也不会闪. 包在 GlassBar
/// / LiquidGlassContainer 外层使用, 不要包在 BackdropFilter 内层.
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 胶囊玻璃按钮 — 播放器「重试 / 换源」、分类筛选、快捷操作用.
///
/// selected 时用赤陶 tint 做选中态, 未选中时是纯玻璃; 文字/图标颜色
/// 跟随选中态走, 不需要调用方再配一套颜色.
class GlassCapsuleButton extends StatelessWidget {
  const GlassCapsuleButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = context.fgAccent;
    final foreground = selected ? Colors.white : context.fgMain;
    return GlassPressable(
      onTap: onTap,
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.auto,
        borderRadius: GlassRadius.pill,
        tint: selected ? accent : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 胶囊玻璃标签 — 分类 chips、频道角标等小控件用, 比按钮更扁平.
///
/// 注意: tint 只在选中时传, 未选中不传 tint 才是纯玻璃; 旧代码把
/// primary 当 tint 传给所有卡片的做法, 会让整排卡片都发红, 不要再用.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.fgAccent;
    return GlassPressable(
      onTap: onTap,
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.auto,
        borderRadius: GlassRadius.pill,
        tint: selected ? accent : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : context.fgMain,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
