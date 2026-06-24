import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'typography.dart';

class IptvTheme {
  IptvTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      // v0.3.8+95 (6/20 12:35 老板反馈): 从 ColorScheme.fromSeed 改 const ColorScheme.light().
      // fromSeed(seedColor: terracotta) 会自动生成一整套 M3 surface tokens (surfaceContainer
      // / surfaceContainerHigh / surfaceContainerHighest) 都是中性灰绿色调 (跟 Material
      // 3 default theme 一样),  跟 light theme 的 bgParchment 采米色不连贯.
      // 老板 settings page 看到背景 = #70716C (fromSeed 算的灰绿) + 文字 = textPrimary 深棕
      // #2A2520 — 两者对比度低,  看不清.
      // 现在显式指定 surfaceContainer* = bgElevated (调淁米白),  scaffold + surface 都是
      // 采米色调,  settings page 背景 = #FFFCF6 (比 bgParchment 亮 一点点),  文字 = #2A2520
      // 对比度清晰.
      colorScheme: const ColorScheme.light(
        primary: IptvColors.accentTerracotta,
        onPrimary: Colors.white,
        secondary: IptvColors.accentClay,
        onSecondary: Colors.white,
        surface: IptvColors.bgParchment,
        onSurface: IptvColors.textPrimary,
        surfaceContainerHighest: IptvColors.bgElevated,
        surfaceContainerHigh: IptvColors.bgElevated,
        surfaceContainer: IptvColors.bgParchment,
        surfaceContainerLow: IptvColors.bgParchment,
        surfaceContainerLowest: IptvColors.bgParchment,
        surfaceDim: IptvColors.bgParchment,
        surfaceBright: IptvColors.bgElevated,
        outline: IptvColors.dividerWarm,
        onSurfaceVariant: IptvColors.textSecondary,
      ),
      scaffoldBackgroundColor: IptvColors.bgParchment,
      // v0.3.7+60: light 主题也加 .apply 显式指定 IptvColors.textPrimary 颜色.
      // 之前 6/19 v0.3.7+50 漏了 (只 dark 主题 apply),  light 下 Text 走 Material
      // 默认 onSurface (#212121) 跟 light theme 深棕 textPrimary (#2A2520) 颜色
      // 不一致.  现在 light + dark 都 apply 颜色,  Typography 删 color 后
      // textTheme.color 是唯一来源.
      textTheme: const TextTheme(
        headlineLarge: IptvTypography.serifHeadline,
        titleLarge: IptvTypography.serifTitle,
        titleMedium: IptvTypography.sansTitle,
        bodyLarge: IptvTypography.body,
        bodyMedium: IptvTypography.body,
        labelSmall: IptvTypography.caption,
      ).apply(
        bodyColor: IptvColors.textPrimary,
        displayColor: IptvColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: IptvColors.bgParchment,
        foregroundColor: IptvColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: IptvTypography.serifTitle,
        // 6/17 (UI 优化): 顶层 AppBar 状态栏用黑图标 (跟浅米色页面背景配套)
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: IptvColors.bgParchment,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      dividerColor: IptvColors.dividerWarm,
    );
  }

  /// 0.3.6+19: 暗色主题. 跟 light 同样的"宣纸/赤陶"调性,
  /// 改为深棕黑底 + 米色字 + 暖橙主色.
  /// 注意: 状态栏图标要反转 (白图标), 玩家页自己会改.
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: IptvColors.accentTerracotta,
        onPrimary: Colors.white,
        secondary: IptvColors.accentClay,
        onSecondary: Colors.white,
        surface: IptvColors.darkBg,
        onSurface: IptvColors.darkTextPrimary,
        surfaceContainerHighest: IptvColors.darkSurface,
        surfaceContainerHigh: IptvColors.darkSurfaceHigh,
        outline: IptvColors.darkDivider,
      ),
      scaffoldBackgroundColor: IptvColors.darkBg,
      cardColor: IptvColors.darkSurface,
      dividerColor: IptvColors.darkDivider,
      textTheme: const TextTheme(
        headlineLarge: IptvTypography.serifHeadline,
        titleLarge: IptvTypography.serifTitle,
        titleMedium: IptvTypography.sansTitle,
        bodyLarge: IptvTypography.body,
        bodyMedium: IptvTypography.body,
        labelSmall: IptvTypography.caption,
      ).apply(
        // 暗色主题默认白底黑字, 改 bodyColor 让 IptvTypography.body
        // (Color(0xFF2A2520) 深棕) 也用暗色色板.
        bodyColor: IptvColors.darkTextPrimary,
        displayColor: IptvColors.darkTextPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: IptvColors.darkBg,
        foregroundColor: IptvColors.darkTextPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: IptvTypography.serifTitle,
        // 6/18 暗色主题: 状态栏用白图标 (跟深棕黑页面背景配套)
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: IptvColors.darkBg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        iconTheme: IconThemeData(color: IptvColors.darkTextPrimary),
        actionsIconTheme: IconThemeData(color: IptvColors.darkTextPrimary),
      ),
      iconTheme: const IconThemeData(color: IptvColors.darkTextPrimary),
    );
  }
}
