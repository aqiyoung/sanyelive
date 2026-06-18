// v0.3.7+20 VersionChecker 单元测试 (P1 feature, 6/18 老板拍板).
//
// 覆盖:
//   1. parse: APK asset 名 sanyelive-v0.3.7+20-arm64-v8a.apk → versionCode 20
//   2. parse: release body 第一行 "**P0**" 标记 → isCritical=true
//   3. parse: release body 普通 → isCritical=false
//   4. parse: 无 tag_name / 无 assets / 无 arm64-v8a → return null
//   5. 状态机: 网络失败 → state = VersionCheckFailed + 写 last_check_time
//   6. 状态机: 1h 内 cache 命中 → 保持 idle,  不写 state
//   7. 状态机: 1h 外 cache 过期 → 走 fetch 路径 (CI 沙箱无外网,  期望 failed)
//   8. 持久化: resetCache 清除所有 key
//
// parse 路径用 @visibleForTesting static 入口,  状态机走真 ProviderContainer
// (网络失败是 CI 沙箱的预期结果,  不需要 mock).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/features/settings/theme_provider.dart';
import 'package:sanyelive/services/version_checker.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('debugParseRelease (parse 逻辑)', () {
    test('happy path: tag v0.3.8 + arm64-v8a APK', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.8',
        'body': '**P1** some new feature',
        'assets': [
          {
            'name': 'sanyelive-v0.3.8+21-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/apk-21.apk',
          },
          {
            'name': 'sanyelive-v0.3.8+21-x86.apk',
            'browser_download_url': 'https://example.com/apk-21-x86.apk',
          },
        ],
      });
      expect(result, isNotNull);
      expect(result!['tagName'], 'v0.3.8');
      expect(result['versionCode'], 21);
      expect(result['apkAssetName'], 'sanyelive-v0.3.8+21-arm64-v8a.apk');
      expect(result['apkDownloadUrl'], 'https://example.com/apk-21.apk');
      expect(result['isCritical'], isFalse);
    });

    test('critical: body 第一行含 **P0** → isCritical=true', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.6.1',
        'body': '**P0** 修复 CCTV-5 死链 + 启动崩溃',
        'assets': [
          {
            'name': 'sanyelive-v0.3.6.1+19-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/apk.apk',
          },
        ],
      });
      expect(result, isNotNull);
      expect(result!['isCritical'], isTrue);
    });

    test('critical (case-insensitive): body 含 **critical** 标记', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.7',
        'body': '**CRITICAL** 安全修复',
        'assets': [
          {
            'name': 'sanyelive-v0.3.7+20-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/apk.apk',
          },
        ],
      });
      expect(result!['isCritical'], isTrue);
    });

    test('non-critical: body 第一行是普通标题', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.7',
        'body': '\n\n**P1** 新功能: 后台强制更新',
        'assets': [
          {
            'name': 'sanyelive-v0.3.7+20-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/apk.apk',
          },
        ],
      });
      expect(result!['isCritical'], isFalse);
    });

    test('edge: 缺 tag_name → return null', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'body': '...',
        'assets': [],
      });
      expect(result, isNull);
    });

    test('edge: 缺 assets → return null', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.8',
        'body': '...',
      });
      expect(result, isNull);
    });

    test('edge: 资产没 .apk → return null', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.8',
        'body': '...',
        'assets': [
          {'name': 'source.zip', 'browser_download_url': '...'},
        ],
      });
      expect(result, isNull);
    });

    test('edge: APK asset 名无 +N 模式 → return null', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.8',
        'body': '...',
        'assets': [
          {
            'name': 'sanyelive-v0.3.8-arm64-v8a.apk', // 缺 +20
            'browser_download_url': 'https://example.com/apk.apk',
          },
        ],
      });
      expect(result, isNull);
    });

    test('fallback: 没 arm64-v8a → 拿第一个 .apk', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.8',
        'body': '...',
        'assets': [
          {
            'name': 'sanyelive-v0.3.8+21-armeabi-v7a.apk',
            'browser_download_url': 'https://example.com/armeabi.apk',
          },
        ],
      });
      expect(result!['apkAssetName'], 'sanyelive-v0.3.8+21-armeabi-v7a.apk');
      expect(result['versionCode'], 21);
    });

    test('空 body → releaseNotes 为空,  isCritical=false', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag_name': 'v0.3.8',
        'body': '',
        'assets': [
          {
            'name': 'sanyelive-v0.3.8+21-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/apk.apk',
          },
        ],
      });
      expect(result!['releaseNotes'], '');
      expect(result['isCritical'], isFalse);
    });
  });

  group('debugExtractVersionCode', () {
    test('v0.3.7+20-arm64-v8a.apk → 20', () {
      expect(
        VersionCheckerNotifier.debugExtractVersionCode(
            'sanyelive-v0.3.7+20-arm64-v8a.apk'),
        20,
      );
    });

    test('sanyelive-v0.3.8+99-armeabi-v7a.apk → 99', () {
      expect(
        VersionCheckerNotifier.debugExtractVersionCode(
            'sanyelive-v0.3.8+99-armeabi-v7a.apk'),
        99,
      );
    });

    test('没 +N 模式 → null', () {
      expect(
        VersionCheckerNotifier.debugExtractVersionCode('sanyelive.apk'),
        isNull,
      );
    });
  });

  group('debugIsCriticalRelease', () {
    test('**P0** 标记 → true', () {
      expect(VersionCheckerNotifier.debugIsCriticalRelease('**P0** fix bug'),
          isTrue);
    });

    test('**critical** (小写) → true', () {
      expect(
        VersionCheckerNotifier.debugIsCriticalRelease('**critical** security'),
        isTrue,
      );
    });

    test('**P1** 提级不强制 → false', () {
      expect(VersionCheckerNotifier.debugIsCriticalRelease('**P1** new feature'),
          isFalse);
    });

    test('空 body → false', () {
      expect(VersionCheckerNotifier.debugIsCriticalRelease(''), isFalse);
    });

    test('空白行后才是 P0 → 看 first non-empty line', () {
      expect(
        VersionCheckerNotifier.debugIsCriticalRelease('\n\n**P0** fix bug'),
        isTrue,
      );
    });
  });

  group('VersionChecker 状态机 (ProviderContainer + 真 network failure)', () {
    Future<ProviderContainer> buildContainer({
      int currentVersionCode = 20,
      String currentVersionString = '0.3.7',
    }) async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentVersionCodeProvider.overrideWithValue(currentVersionCode),
          currentVersionStringProvider.overrideWithValue(currentVersionString),
        ],
      );
      return container;
    }

    test('网络失败 → state = VersionCheckFailed + 写 last_check_time', () async {
      final container = await buildContainer();
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckFailed>(),
          reason: '网络失败应被捕获并 state = VersionCheckFailed');

      final lastCheck = prefs.getInt('version_checker.last_check_time');
      expect(lastCheck, isNotNull);
      expect(lastCheck, lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch));
    });

    test('1h 内 cache 命中 → 保持 idle,  不写 state', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(
          'version_checker.last_check_time', now - 30 * 60 * 1000);

      final container = await buildContainer();
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      expect(container.read(versionCheckerProvider), isA<VersionCheckIdle>());
    });

    test('1h 外 cache 过期 → 走 fetch 路径 (期望 failed,  写新 last_check_time)',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(
          'version_checker.last_check_time', now - 2 * 60 * 60 * 1000);

      final container = await buildContainer();
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      expect(container.read(versionCheckerProvider), isA<VersionCheckFailed>());

      final newLastCheck = prefs.getInt('version_checker.last_check_time');
      expect(newLastCheck, isNotNull);
      expect(newLastCheck!, greaterThan(now - 2 * 60 * 60 * 1000));
    });

    test('resetCache 清除所有持久化 key', () async {
      await prefs.setInt('version_checker.last_check_time', 12345);
      await prefs.setString('version_checker.last_seen_version', 'v0.3.7');
      await prefs.setString('version_checker.dismissed_version', 'v0.3.7');
      await prefs.setInt('version_checker.dismissed_at', 67890);

      final container = await buildContainer();
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).resetCache();

      expect(prefs.getInt('version_checker.last_check_time'), isNull);
      expect(prefs.getString('version_checker.last_seen_version'), isNull);
      expect(prefs.getString('version_checker.dismissed_version'), isNull);
      expect(prefs.getInt('version_checker.dismissed_at'), isNull);
    });
  });
}
