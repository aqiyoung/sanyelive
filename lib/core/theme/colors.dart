import 'package:flutter/material.dart';

/// Design tokens — 新中式 · 暖色调 · 衬线标题
/// Reference: design doc §5.1
class IptvColors {
  IptvColors._();

  /// 暖米色主背景 — 仿宣纸
  static const Color bgParchment = Color(0xFFF5F4ED);

  /// 卡片背景（略白）
  static const Color bgElevated = Color(0xFFFFFCF6);

  /// 主色 — 赤陶 Terracotta
  static const Color accentTerracotta = Color(0xFFE5473A);

  /// 主色深色版 — 紫砂 Clay
  static const Color accentClay = Color(0xFFB83A2A);

  /// 主文字 — 深棕
  static const Color textPrimary = Color(0xFF2A2520);

  /// 次文字 — 浅棕
  static const Color textSecondary = Color(0xFF6B5F54);

  /// 分隔线 — 暖灰
  static const Color dividerWarm = Color(0xFFE8E0D4);

  // 设计原则: 暗色页面也保持"宣纸/赤陶"调性, 不走纯黑灰.
  // 主背景用深棕黑(仿"古纸焚"), 卡片用暖调深灰,
  // 主色 accentTerracotta 在暗色下也保留 — 暖橙在深底上对比度好.
  // 参考 Material 3 dark surface tier (surface / surfaceContainer 等).

  /// 暗色主背景 — 深棕黑 (仿古纸焚后的焦褐)
  static const Color darkBg = Color(0xFF1A1612);

  /// 暗色卡片背景 — 暖调深灰
  static const Color darkSurface = Color(0xFF25201B);

  /// 暗色高亮卡片 — 比 surface 略亮
  static const Color darkSurfaceHigh = Color(0xFF312B25);

  /// 暗色主文字 — 米色 (跟 bgParchment 呼应的"宣纸白")
  static const Color darkTextPrimary = Color(0xFFEDE4D3);

  /// 暗色次文字 — 暖灰
  static const Color darkTextSecondary = Color(0xFFB5A99A);

  /// 暗色分隔线 — 暖深灰
  static const Color darkDivider = Color(0xFF3A332C);
}

// ---------------------------------------------------------------------------
//
// 子页面原来全部硬编码深色 (Color(0xFF101010) / Colors.white / 0xFFE53935),
// 导致切到浅色模式后不跟 theme 走. 现在统一走 Theme.of(context).colorScheme,
// light / dark 两套 ThemeData 在 theme.dart 里定义, 这里只定义"语义名 → token"映射.
//
// 用法:
//   ColoredBox(color: context.bgBase)          // 页面/ scaffold 背景
//   Text('..', style: TextStyle(color: context.fgMain))   // 主文字
//   Container(color: context.bgCard)           // 卡片背景
//   Container(color: context.bgCardHigh)       // 卡片内更深一档 (按钮 / 内嵌块)
//   Icon(Icons.x, color: context.fgAccent)     // 强调色 (赤陶)
//   Border.all(color: context.fgBorder)        // 边框 / 分隔线
// ----------------------------------------------------------------------------

/// 语义色 — 从当前 Theme.colorScheme 读, light/dark 自动切换.
extension BuildThemeColors on BuildContext {
  ColorScheme get _cs => Theme.of(this).colorScheme;

  /// 页面 / scaffold 主背景.
  Color get bgBase => _cs.surface;

  /// 卡片 / 容器 背景 (比 surface 浅/深一档).
  Color get bgCard => _cs.surfaceContainer;

  /// 卡片内更深一档 (按钮底 / 内嵌块).
  Color get bgCardHigh => _cs.surfaceContainerHigh;

  /// 主文字.
  Color get fgMain => _cs.onSurface;

  /// 次文字.
  Color get fgSub => _cs.onSurfaceVariant;

  /// 强调色 — 赤陶 (主色 / 红 ICON / 直播标记).
  Color get fgAccent => _cs.primary;

  /// 边框 / 分隔线.
  Color get fgBorder => _cs.outline;

  /// 当前亮度 — 给状态栏 / AnnotatedRegion 用.
  Brightness get appBrightness => Theme.of(this).brightness;
}
