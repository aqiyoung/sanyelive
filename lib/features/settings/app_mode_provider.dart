//
// 应用模式开关 — 决定底部导航显示「精简电视直播界面」还是「完整功能」。
//
// 设计:
//   - AppModeNotifier 继承 Notifier<bool>, 用 SharedPreferences 持久化
//     'app_mode_full' (bool). 默认 false = 电视直播模式 (精简界面),
//     true = 完整功能模式 (显示全部 5 个底部标签).
//   - appModeProvider 暴露给 home_page / settings_page.
//   - sharedPreferencesProvider 在 main() 里 override (见 theme_provider.dart).
//
// 用法:
//   // home_page.dart
//   final full = ref.watch(appModeProvider);
//   // settings_page.dart
//   ref.read(appModeProvider.notifier).setFull(v);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart' show sharedPreferencesProvider;

/// 应用模式: false = 电视直播 (默认精简), true = 完整功能.
final appModeProvider =
    NotifierProvider<AppModeNotifier, bool>(AppModeNotifier.new);

class AppModeNotifier extends Notifier<bool> {
  static const kAppModeFullKey = 'app_mode_full';

  @override
  bool build() {
    // 启动时从 SharedPreferences 读, 默认 false (电视直播精简界面).
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getBool(kAppModeFullKey) ?? false;
  }

  /// 切换并持久化. [full]=true 显示全部功能, false 回到电视直播界面.
  Future<void> setFull(bool full) async {
    if (state == full) return;
    state = full;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(kAppModeFullKey, full);
  }
}
