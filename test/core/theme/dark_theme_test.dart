// 0.3.6+19 暗色主题 — IptvTheme.dark() 单元测试
//
// 验收 (proof):
//   1. dark() 返回 brightness == dark
//   2. dark() 主背景不是白色 (不是 Color(0xFFFFFFFF))
//   3. dark() 和 light() 的 surface color 不同
//   4. dark() 状态栏用白图标 (light 用黑图标)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanyelive/core/theme/colors.dart';
import 'package:sanyelive/core/theme/theme.dart';

void main() {
  group('IptvTheme.dark() (v0.3.6+19)', () {
    test('brightness == Brightness.dark', () {
      final dark = IptvTheme.dark();
      expect(dark.brightness, Brightness.dark);
    });

    test('light() 的 brightness == Brightness.light (回归)', () {
      final light = IptvTheme.light();
      expect(light.brightness, Brightness.light);
    });

    test('dark() scaffoldBackgroundColor 不是白色', () {
      final dark = IptvTheme.dark();
      final bg = dark.scaffoldBackgroundColor;
      // 暗色页面背景必须不是纯白
      expect(bg, isNot(equals(Colors.white)));
      // 也不应该是 null
      expect(bg, isNotNull);
      // 应该用 IptvColors.darkBg 暖深棕黑
      expect(bg, equals(IptvColors.darkBg));
    });

    test('dark() 和 light() surface 颜色不同', () {
      final dark = IptvTheme.dark();
      final light = IptvTheme.light();

      final darkSurface = dark.colorScheme.surface;
      final lightSurface = light.colorScheme.surface;

      expect(darkSurface, isNot(equals(lightSurface)));
      expect(darkSurface, equals(IptvColors.darkBg));
      expect(lightSurface, equals(IptvColors.bgParchment));
    });

    test('dark() 状态栏图标用 light (白图标, 跟深底配套)', () {
      final dark = IptvTheme.dark();
      final sysUi = dark.appBarTheme.systemOverlayStyle;
      // 暗色页 statusBarIconBrightness 应该是 light (= 白图标)
      expect(sysUi?.statusBarIconBrightness, Brightness.light);
    });

    test('light() 状态栏图标用 dark (黑图标, 跟浅底配套) — 回归', () {
      final light = IptvTheme.light();
      final sysUi = light.appBarTheme.systemOverlayStyle;
      expect(sysUi?.statusBarIconBrightness, Brightness.dark);
    });

    test('dark() 主色保留 IptvColors.accentTerracotta (暖橙在深底上对比好)', () {
      final dark = IptvTheme.dark();
      expect(dark.colorScheme.primary, IptvColors.accentTerracotta);
    });
  });
}
