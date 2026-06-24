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

// v0.3.8+95 (6/20 老板反馈): light theme 的 surfaceContainerHighest
// 不应该是 fromSeed 算的灰绿色 (Material 3 default),  应该是 bgElevated.
// 之前 light() 用 ColorScheme.fromSeed,  surfaceContainerHighest 没指定
// → 默认灰色调 (跟 bgParchment 不连贯).  settings page ListTile 背景
// = surfaceContainerHighest = 灰绿色,  文字 = onSurface = textPrimary 深棕
// → 对比度低看不清.

  group('IptvTheme.light() (v0.3.8+95)', () {
    test('surfaceContainerHighest == bgElevated (不灰绿)', () {
      final light = IptvTheme.light();
      final sch = light.colorScheme.surfaceContainerHighest;
      // bgElevated = 0xFFFFFCF6 (调亮米白)
      // fromSeed 默认会算成中性灰绿色 (~0xE6E1E5 在 light mode)
      expect(sch, equals(IptvColors.bgElevated));
    });

    test('surfaceContainer == bgParchment (米色一致)', () {
      final light = IptvTheme.light();
      expect(
          light.colorScheme.surfaceContainer, equals(IptvColors.bgParchment));
    });

    test('onSurface == textPrimary (深棕字跟米色底对比度)', () {
      final light = IptvTheme.light();
      expect(light.colorScheme.onSurface, equals(IptvColors.textPrimary));
    });

    test('ListTile 默认背景色跟 surface 一致 (米色, 不是灰绿)', () {
      final light = IptvTheme.light();
      // M3 ListTile 默认 background = colorScheme.surfaceContainerHighest
      // (iOS 是 surface).  我们的 AppBar + Scaffold 跟 surfaceContainer
      // 同色 = 采米色连贯.
      final listTileBg = light.colorScheme.surfaceContainerHighest;
      final scaffoldBg = light.scaffoldBackgroundColor;
      // 都在采色调,  不会有深灰绿背景拼米色 scaffold 的难看现象.
      expect(listTileBg, isNot(equals(const Color(0xFF70716C))));
      // bgElevated 跟 bgParchment 都是采色调
      expect(listTileBg, equals(IptvColors.bgElevated));
      expect(scaffoldBg, equals(IptvColors.bgParchment));
    });
  });
}
