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
    // iOS 27 液态玻璃 Dock: 底部悬浮宽胶囊.
    //
    // 之前几次跑到屏幕中间的根因, 就在这里, 不是 Scaffold、
    // 不是 extendBody: bottomNavigationBar 槽位给的高度约束
    // 是松的、上限为整屏高, Center 会撑满这个高度再把胶囊
    // 在里面垂直居中, 于是胶囊就出现在了屏幕中间.
    // 而之前贴底全宽的版本没有 Center, 所以老实待在底部.
    // 修复: 坚决不用 Center/Align (它们都会撑满父级高度),
    // 只用 Padding 左右各留 16 + 宽度撑满的容器, 高度就是
    // 胶囊本身的 72, Scaffold 就会把它贴在底部.
    //  - 位置: 底部悬浮, 底部留 16px, 内容从它后面透过去.
    //  - 形状: 宽胶囊 (左右各留 16, 高 72, 圆角 32).
    //  - 玻璃看得见: 强浓度玻璃 + 暖灰底色 + 深色描边 + 下方投影.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          width: double.infinity,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: LiquidGlassContainer(
              variant: LiquidGlassVariant.auto,
              borderRadius: 32,
              blurSigma: 30,
              child: child,
            ),
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
