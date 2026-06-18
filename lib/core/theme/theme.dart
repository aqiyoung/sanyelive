import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'typography.dart';

class IptvTheme {
  IptvTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: IptvColors.accentTerracotta,
        primary: IptvColors.accentTerracotta,
        surface: IptvColors.bgParchment,
        onSurface: IptvColors.textPrimary,
        secondary: IptvColors.accentClay,
      ),
      scaffoldBackgroundColor: IptvColors.bgParchment,
      textTheme: const TextTheme(
        headlineLarge: IptvTypography.serifHeadline,
        titleLarge: IptvTypography.serifTitle,
        titleMedium: IptvTypography.sansTitle,
        bodyLarge: IptvTypography.body,
        bodyMedium: IptvTypography.body,
        labelSmall: IptvTypography.caption,
      ),
      appBarTheme: AppBarTheme(
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
