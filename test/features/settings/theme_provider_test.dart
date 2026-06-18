// 0.3.6+19 暗色主题 — themeProvider 单元测试
//
// 验收 (proof):
//   1. 默认 mode = ThemeMode.system (无 pref 记录)
//   2. setMode 后, SharedPreferences 真的写入了 'theme_mode' 字符串
//   3. 重启模拟 (新 container) 读回相同 mode
//   4. 三种模式字符串映射正确 (system / light / dark)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/features/settings/theme_provider.dart';

void main() {
  group('ThemeModeNotifier (v0.3.6+19)', () {
    setUp(() {
      // flutter_test 内置 mock,  每次清空
      SharedPreferences.setMockInitialValues({});
    });

    test('默认 mode = ThemeMode.system (无 pref 记录)', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('setMode(ThemeMode.dark) 后 SharedPreferences 写入了 "dark"', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('setMode(ThemeMode.light) 后 SharedPreferences 写入了 "light"', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(prefs.getString('theme_mode'), 'light');
    });

    test('重启模拟: 持久化后新 container 读回相同 mode', () async {
      // 第一次启动, 写 dark
      final prefs1 = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs1)],
      );
      await c1.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      c1.dispose();

      // 第二次启动, 用同一份 prefs (模拟重启后从磁盘读)
      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs1)],
      );
      addTearDown(c2.dispose);

      expect(c2.read(themeModeProvider), ThemeMode.dark);
    });

    test('非法/未知值降级为 ThemeMode.system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'whatever'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}
