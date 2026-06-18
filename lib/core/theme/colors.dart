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
  static const Color accentTerracotta = Color(0xFFC96442);

  /// 主色深色版 — 紫砂 Clay
  static const Color accentClay = Color(0xFFA85234);

  /// 主文字 — 深棕
  static const Color textPrimary = Color(0xFF2A2520);

  /// 次文字 — 浅棕
  static const Color textSecondary = Color(0xFF6B5F54);

  /// 分隔线 — 暖灰
  static const Color dividerWarm = Color(0xFFE8E0D4);

  // -------- 0.3.6+19 暗色主题 tokens --------
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
