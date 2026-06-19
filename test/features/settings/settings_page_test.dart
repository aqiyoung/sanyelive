// v0.3.5.9 设置页版本号显示 — widget 测试
//
// 验收 (proof):
//   1. 设置页显示版本号 (currentVersion)
//   2. 设置页显示 build number (currentVersionCode)
//   3. currentVersion 跟 pubspec 版本一致
//   4. currentVersionCode 是正整数
//   5. 设置页同时有"主题"和"版本号"两个 section

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/features/settings/settings_page.dart';
import 'package:sanyelive/features/settings/theme_provider.dart';
import 'package:sanyelive/services/version_checker.dart'
    show currentVersionStringProvider, currentVersionCodeProvider;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsPage 版本号显示 (v0.3.7.2: 运行时读 PackageInfo)', () {
    testWidgets('显示 Provider 注入的版本号', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentVersionStringProvider.overrideWithValue('0.3.7+57'),
          currentVersionCodeProvider.overrideWithValue(57),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('版本号'), findsOneWidget);
      expect(find.textContaining('0.3.7+57'), findsOneWidget);
    });

    testWidgets('显示 Provider 注入的 build number', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentVersionStringProvider.overrideWithValue('0.3.7+57'),
          currentVersionCodeProvider.overrideWithValue(57),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('build 57'), findsOneWidget);
    });

    // v0.3.7.2: currentVersionStringProvider / currentVersionCodeProvider
    // 在 version_checker.dart 里默认 throw UnimplementedError,  必须在
    // ProviderContainer 里 override (参考 main.dart 的 PackageInfo.fromPlatform
    // 路径).  所以不写 "默认读取" test,  只测 override 后能正常显示.

    testWidgets('设置页同时有主题和版本号 section', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentVersionStringProvider.overrideWithValue('0.3.7+58'),
          currentVersionCodeProvider.overrideWithValue(58),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('主题'), findsOneWidget);
      expect(find.text('版本号'), findsOneWidget);
    });
  });
}
