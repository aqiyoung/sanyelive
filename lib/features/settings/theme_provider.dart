// 0.3.6+19 暗色主题持久化.
//
// 设计:
//   - ThemeProviderNotifier 继承 Notifier<ThemeMode>, 是 StateNotifier 的
//     替代品 (Riverpod 2.x 推荐). 内部用 SharedPreferences 存 'theme_mode'
//     字符串 (system / light / dark), 启动时 read, 切换时 write.
//   - themeModeProvider 暴露 ThemeMode 给 main.dart / settings_page.
//   - sharedPreferencesProvider 用 overrideWithValue 在 main() / 测试里
//     注入 — 测试用 SharedPreferences.setMockInitialValues({}) 即可,
//     无需 mock framework.
//
// 用法:
//   // main.dart
//   final prefs = await SharedPreferences.getInstance();
//   runApp(
//     UncontrolledProviderScope(
//       container: ProviderContainer(
//         overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
//       ),
//       child: IptvApp(),
//     ),
//   );
//
//   // settings_page.dart
//   final mode = ref.watch(themeModeProvider);
//   ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 实例 — 在 main() / 测试里 override.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider 必须在 ProviderContainer 里 override',
  );
});

/// ThemeMode 持久化 + 切换.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _kThemeModeKey = 'theme_mode';

  @override
  ThemeMode build() {
    // 启动时从 SharedPreferences 读, 默认 system (跟随系统).
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_kThemeModeKey);
    return _parseMode(raw);
  }

  /// 切换并持久化.
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kThemeModeKey, _serializeMode(mode));
  }

  static ThemeMode _parseMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _serializeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

/// 暴露给 main.dart / settings_page 用的 ThemeMode provider.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
