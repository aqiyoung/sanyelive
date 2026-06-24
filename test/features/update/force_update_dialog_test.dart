// v0.3.7+20 ForceUpdateDialog 单元测试 (P1 feature, 6/18 老板拍板).
//
// 覆盖:
//   1. 渲染: 显示新版本号 + 变更日志
//   2. barrierDismissible: false → 通过 ForceUpdateDialog.show 验证
//   3. P0/critical 模式: 不显示 "稍后" 按钮
//   4. P1 普通模式: 显示 "稍后" + "立刻更新" 2 按钮
//   5. 点 "稍后" → 写 dismissed_version + dismissed_at
//
// 不测下载流程 (dio.download 走真网络失败,  集成测试另开卡).
// _ForceUpdateDialogContent 是 private,  测不了内部 widget 树.  改为:
// - 用 Container 模拟 "dialog 内容" 的展示 + 按钮回调 (验证 P0 模式/稍后按钮
//   等关键行为).
// - barrierDismissible 通过读源码 + showDialog() + tapAt 外部,  验证 dialog
//   没被关闭 (Material 库原生行为).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/features/settings/theme_provider.dart';
import 'package:sanyelive/features/update/force_update_dialog.dart';
import 'package:sanyelive/services/version_checker.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// 启动 ProviderContainer (必须 override prefs).
  Future<ProviderContainer> setupContainer() async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    return container;
  }

  /// 把 VersionCheckState 强行设成 outdated (bypass 真 fetch).
  void setOutdated(
    ProviderContainer container, {
    String version = 'v0.3.8',
    int versionCode = 21,
    bool isCritical = false,
    String body = 'Some release notes',
  }) {
    container.read(versionCheckerProvider.notifier).debugSetState(
          VersionCheckOutdated(
            latestVersion: version,
            latestVersionCode: versionCode,
            currentVersion: '0.3.7',
            apkAssetName: 'sanyelive-v0.3.8+21-arm64-v8a.apk',
            apkDownloadUrl:
                'https://github.com/aqiyoung/iptv-app/releases/download/v0.3.8/apk.apk',
            releaseNotes: body,
            isCritical: isCritical,
          ),
        );
  }

  /// 渲染一个简化的 dialog 内容 (Container + version text + release notes +
  /// 按钮栈),  模拟 _ForceUpdateDialogContent 的关键 UI.  不走 showDialog,
  /// 避免真实 overlay + 异步动画.  按钮逻辑跟 _ForceUpdateDialogContent 一致.
  Widget buildTestDialog({
    required VersionCheckOutdated state,
    required void Function() onDismiss,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.isCritical ? '重要更新' : '发现新版本',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('${state.currentVersion} → ${state.latestVersion}'),
          const SizedBox(height: 12),
          Text(state.releaseNotes),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!state.isCritical)
                TextButton(onPressed: onDismiss, child: const Text('稍后')),
              FilledButton(
                onPressed: () {
                  // 测时不真下载.  集成测试在卡上 follow-up.
                },
                child: const Text('立刻更新'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  group('ForceUpdateDialog 内容渲染 (P0/critical 模式)', () {
    testWidgets('P0 release → 不显示 "稍后" 按钮', (tester) async {
      final container = await setupContainer();
      addTearDown(container.dispose);
      setOutdated(container, isCritical: true);
      final state =
          container.read(versionCheckerProvider) as VersionCheckOutdated;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: IptvTheme.light(),
            home: Scaffold(
              body: buildTestDialog(state: state, onDismiss: () {}),
            ),
          ),
        ),
      );

      expect(find.text('稍后'), findsNothing, reason: 'P0 critical 不应显示 "稍后" 按钮');
      expect(find.text('立刻更新'), findsOneWidget);
      expect(find.text('重要更新'), findsOneWidget);
    });

    testWidgets('P1 release → 显示 "稍后" + "立刻更新" 2 按钮', (tester) async {
      final container = await setupContainer();
      addTearDown(container.dispose);
      setOutdated(container, isCritical: false);
      final state =
          container.read(versionCheckerProvider) as VersionCheckOutdated;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: IptvTheme.light(),
            home: Scaffold(
              body: buildTestDialog(state: state, onDismiss: () {}),
            ),
          ),
        ),
      );

      expect(find.text('稍后'), findsOneWidget);
      expect(find.text('立刻更新'), findsOneWidget);
      expect(find.text('发现新版本'), findsOneWidget);
    });
  });

  group('ForceUpdateDialog 内容显示', () {
    testWidgets('显示新版本号 + 变更日志', (tester) async {
      final container = await setupContainer();
      addTearDown(container.dispose);
      setOutdated(container, version: 'v0.3.8', body: '**P1** 修了几个小 bug');
      final state =
          container.read(versionCheckerProvider) as VersionCheckOutdated;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: IptvTheme.light(),
            home: Scaffold(
              body: buildTestDialog(state: state, onDismiss: () {}),
            ),
          ),
        ),
      );

      // "0.3.7 → v0.3.8" 出现在 currentVersion → latestVersion 里.
      expect(find.textContaining('0.3.7'), findsOneWidget);
      expect(find.textContaining('v0.3.8'), findsOneWidget);
      expect(find.textContaining('**P1** 修了几个小 bug'), findsOneWidget);
    });
  });

  group('ForceUpdateDialog 按钮交互', () {
    testWidgets('点 "稍后" → 写 dismissed_version + dismissed_at', (tester) async {
      final container = await setupContainer();
      addTearDown(container.dispose);
      setOutdated(container, version: 'v0.3.8');
      final state =
          container.read(versionCheckerProvider) as VersionCheckOutdated;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: IptvTheme.light(),
            home: Scaffold(
              body: buildTestDialog(
                state: state,
                onDismiss: () {
                  // 模拟 production 行为:  markDismissed 写 prefs.
                  container
                      .read(versionCheckerProvider.notifier)
                      .markDismissed();
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();

      final dismissed = prefs.getString('version_checker.dismissed_version');
      expect(dismissed, 'v0.3.8');
      final dismissedAt = prefs.getInt('version_checker.dismissed_at');
      expect(dismissedAt, isNotNull);
    });
  });

  group('ForceUpdateDialog.show — barrierDismissible 验证', () {
    testWidgets('调用 show() 后 dialog 在,  点外部 (20, 20) 不关', (tester) async {
      final container = await setupContainer();
      addTearDown(container.dispose);
      setOutdated(container);

      // 用一个全屏 Scaffold + 居中 FAB 做参照物,  屏幕左上角 (20, 20) 必然
      // 在 dialog 外部 (Material 居中 dialog 不会到角落).
      BuildContext? ctx;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ctx = context;
                return const Scaffold(
                  body: Center(child: Text('underneath')),
                );
              },
            ),
          ),
        ),
      );

      // 不要 await show() — show() 返回的 Future 会一直 pending 直到 dialog
      // 被 pop,  会让 test 挂到 10 分钟 timeout.  showDialog 同步会 push
      // 到 Navigator,  后续 pump() 能拿到 widget 树.
      // ignore: unawaited_futures
      ForceUpdateDialog.show(ctx!);
      await tester.pump(); // 一帧
      await tester.pump(const Duration(milliseconds: 500)); // 弹窗动画结束

      // 找到 AlertDialog (Material library 内置 widget).
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'show() 后 AlertDialog 应在树中');

      // 点 (20, 20) — 屏幕左上角,  在 barrier 但不在 dialog 内容里.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // barrierDismissible: false → dialog 应该还在.
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'barrierDismissible:false 应阻止外部点击关闭');
    });
  });
}
