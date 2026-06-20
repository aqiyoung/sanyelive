// v0.3.7+50 (6/19): 状态栏/导航栏 brightness 跟主题走 — 纯函数测试.
// 不 pump 整页 widget tree, 直接调 buildSystemUiOverlayForPlayer/App
// 验证 light/dark 模式输出.
// v0.3.8+112 (6/20): statusBarColor / systemNavigationBarColor 改 Colors.black
// (跟视频区黑底一体化,  老板反馈 "上白条" + "左边白条" fix).  不再用 transparent
// 也不用 IptvColors.bgParchment / darkBg.  图标亮度保留:  浅色主题深图标 /
// 暗色主题白图标.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanyelive/features/player/system_ui_overlay.dart';

void main() {
  group('buildSystemUiOverlayForPlayer 跟主题走', () {
    test('浅色主题 → statusBarIconBrightness=dark (深图标)', () {
      const scheme = ColorScheme.light();
      final overlay = buildSystemUiOverlayForPlayer(
        scheme,
        Brightness.light,
      );
      expect(overlay.statusBarIconBrightness, Brightness.dark,
          reason: '浅色主题状态栏图标应该是深的才能看清');
      expect(overlay.statusBarBrightness, Brightness.light,
          reason: 'iOS 端: 状态栏文字应匹配 light 主题');
    });

    test('暗色主题 → statusBarIconBrightness=light (白图标)', () {
      const scheme = ColorScheme.dark();
      final overlay = buildSystemUiOverlayForPlayer(
        scheme,
        Brightness.dark,
      );
      expect(overlay.statusBarIconBrightness, Brightness.light,
          reason: '暗色主题状态栏图标应该是白的才能看清');
      expect(overlay.statusBarBrightness, Brightness.dark,
          reason: 'iOS 端: 状态栏文字应匹配 dark 主题');
    });

    test('statusBarColor 永远黑色 (v0.3.8+112 跟视频区一体化, 防上白条)', () {
      // v0.3.8+112:  之前 Colors.transparent 在 Android 14+ edge-to-edge 强制
      // 透出 theme scaffold bg = 米白,  老板看到 "上白条".  改成 Colors.black
      // (跟视频区黑底一体化,  状态栏看不到米白透出).
      final lightOverlay = buildSystemUiOverlayForPlayer(
        const ColorScheme.light(),
        Brightness.light,
      );
      final darkOverlay = buildSystemUiOverlayForPlayer(
        const ColorScheme.dark(),
        Brightness.dark,
      );
      expect(lightOverlay.statusBarColor, Colors.black);
      expect(darkOverlay.statusBarColor, Colors.black);
    });

    test('systemNavigationBarColor 浅色=黑色 (v0.3.8+112 跟播放页黑背景一体)', () {
      // v0.3.8+112:  之前用 IptvColors.bgParchment (0xF5F4ED).  改成 Colors.black
      // 跟播放页黑背景一体化,  老板看到 "底部米黄跟视频黑对不上".
      const scheme = ColorScheme.light();
      final overlay = buildSystemUiOverlayForPlayer(
        scheme,
        Brightness.light,
      );
      expect(overlay.systemNavigationBarColor, Colors.black);
    });

    test('systemNavigationBarColor 暗色=黑色 (v0.3.8+112 跟播放页黑背景一体)', () {
      // v0.3.8+112:  之前用 IptvColors.darkBg (0x1A1612).  改成 Colors.black.
      const scheme = ColorScheme.dark();
      final overlay = buildSystemUiOverlayForPlayer(
        scheme,
        Brightness.dark,
      );
      expect(overlay.systemNavigationBarColor, Colors.black);
    });
  });

  group('buildSystemUiOverlayForApp 跟 player 一致', () {
    test('浅色 → 深图标', () {
      const scheme = ColorScheme.light();
      final overlay = buildSystemUiOverlayForApp(scheme, Brightness.light);
      expect(overlay.statusBarIconBrightness, Brightness.dark);
    });

    test('暗色 → 白图标', () {
      const scheme = ColorScheme.dark();
      final overlay = buildSystemUiOverlayForApp(scheme, Brightness.dark);
      expect(overlay.statusBarIconBrightness, Brightness.light);
    });
  });
}
