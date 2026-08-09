// v0.3.7+20 VersionChecker 单元测试 (P1 feature, 6/18 老板拍板).
//
// 覆盖:
//   1. parse: APK asset 名 sanyelive-v0.3.7+20-arm64-v8a.apk → versionCode 20
//   2. parse: release body 第一行 "**P0**" 标记 → isCritical=true
//   3. parse: release body 普通 → isCritical=false
//   4. parse: 无 tag_name / 无 assets / 无 arm64-v8a → return null
//   5. 状态机 (mock Dio): 拉回 v0.3.8 + versionCode 21 > current 20 → outdated
//   6. 状态机 (mock Dio): 拉回 v0.3.6 + versionCode 19 < current 20 → upToDate
//   7. 状态机 (mock Dio 抛错): 网络失败 → state = VersionCheckFailed + 写 last_check_time
//   8. 状态机: 1h 内 cache 命中 → 保持 idle,  不写 state
//   9. 状态机: 1h 外 cache 过期 → 走 fetch 路径 (mock 抛错,  期望 failed)
//  10. 持久化: resetCache 清除所有 key
//
// parse 路径用 @visibleForTesting static 入口; 状态机走 ProviderContainer +
// 注入 mock Dio (override dioProvider).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/features/settings/theme_provider.dart';
import 'package:sanyelive/services/version_checker.dart';

/// 注入 mock Dio (响应 / 抛错,  不会走真网络).
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.responder);

  /// (RequestOptions) → ResponseBody  或 throw
  final Future<ResponseBody> Function(RequestOptions) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> json) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  return ResponseBody.fromBytes(
    bytes,
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'simulated network failure',
    );
  }

  @override
  void close({bool force = false}) {}
}

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
            'name': 'sanyelive-v0.3.8-arm64-v8a.apk',
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

    // ─── meta 版本源 (version.json) 格式 ──────────────────────────────
    test('meta: tag + versionCode + apk 映射 → 正确解析 arm64', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag': 'v0.3.12.131',
        'versionName': '0.3.12+131',
        'versionCode': 131,
        'apk': {
          'arm64-v8a':
              'https://github.com/aqiyoung/sanyelive/releases/download/v0.3.12.131/sanyelive-v0.3.12+131-arm64-v8a.apk',
          'armeabi-v7a':
              'https://github.com/aqiyoung/sanyelive/releases/download/v0.3.12.131/sanyelive-v0.3.12+131-armeabi-v7a.apk',
          'x86_64':
              'https://github.com/aqiyoung/sanyelive/releases/download/v0.3.12.131/sanyelive-v0.3.12+131-x86_64.apk',
        },
        'releaseUrl': 'https://github.com/aqiyoung/sanyelive/releases/tag/v0.3.12.131',
        'critical': false,
        'notes': '台标离线化',
      });
      expect(result, isNotNull);
      expect(result!['tagName'], 'v0.3.12.131');
      expect(result['versionCode'], 131);
      expect(result['apkAssetName'], 'sanyelive-v0.3.12+131-arm64-v8a.apk');
      expect(
        result['apkDownloadUrl'],
        'https://github.com/aqiyoung/sanyelive/releases/download/v0.3.12.131/sanyelive-v0.3.12+131-arm64-v8a.apk',
      );
      expect(result['isCritical'], isFalse);
      expect(result['releaseNotes'], '台标离线化');
    });

    test('meta: 带代理前缀 → apkDownloadUrl 也加前缀', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag': 'v0.3.12.131',
        'versionCode': 131,
        'apk': {
          'arm64-v8a': 'https://github.com/x/sanyelive-v0.3.12+131-arm64-v8a.apk',
        },
      }, proxyPrefix: 'https://gh-proxy.com/');
      expect(result!['apkDownloadUrl'],
          'https://gh-proxy.com/https://github.com/x/sanyelive-v0.3.12+131-arm64-v8a.apk');
    });

    test('meta: 缺少 apk 字段 → return null', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag': 'v0.3.12.131',
        'versionCode': 131,
      });
      expect(result, isNull);
    });

    test('meta: versionCode 非 int → return null', () {
      final result = VersionCheckerNotifier.debugParseRelease({
        'tag': 'v0.3.12.131',
        'versionCode': '131',
        'apk': {'arm64-v8a': 'https://x/y.apk'},
      });
      expect(result, isNull);
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
      expect(
        VersionCheckerNotifier.debugIsCriticalRelease('**P1** new feature'),
        isFalse,
      );
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

  group('VersionChecker 状态机 (ProviderContainer + mock Dio)', () {
    Future<ProviderContainer> buildContainer({
      required HttpClientAdapter adapter,
      int currentVersionCode = 20,
      String currentVersionString = '0.3.7',
    }) async {
      final mockDio = Dio();
      mockDio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentVersionCodeProvider.overrideWithValue(currentVersionCode),
          currentVersionStringProvider.overrideWithValue(currentVersionString),
          dioProvider.overrideWithValue(mockDio),
        ],
      );
      return container;
    }

    test('拉回 v0.3.8 + versionCode 21 > current 20 → outdated', () async {
      final container = await buildContainer(
        adapter: _MockAdapter((opts) async {
          return _jsonBody({
            'tag_name': 'v0.3.8',
            'body': '**P1** new feature',
            'assets': [
              {
                'name': 'sanyelive-v0.3.8+21-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/apk.apk',
              },
            ],
          });
        }),
        currentVersionCode: 20,
      );
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckOutdated>());
      final outdated = state as VersionCheckOutdated;
      expect(outdated.latestVersion, 'v0.3.8');
      expect(outdated.latestVersionCode, 21);
      expect(outdated.currentVersion, '0.3.7');
      expect(outdated.isCritical, isFalse);
    });

    test('拉回 v0.3.6 + versionCode 19 < current 20 → upToDate', () async {
      final container = await buildContainer(
        adapter: _MockAdapter((opts) async {
          return _jsonBody({
            'tag_name': 'v0.3.6',
            'body': 'old',
            'assets': [
              {
                'name': 'sanyelive-v0.3.6+19-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/apk.apk',
              },
            ],
          });
        }),
        currentVersionCode: 20,
      );
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckUpToDate>());
      expect((state as VersionCheckUpToDate).latestVersion, 'v0.3.6');
    });

    test('P0 critical release → outdated + isCritical=true', () async {
      final container = await buildContainer(
        adapter: _MockAdapter((opts) async {
          return _jsonBody({
            'tag_name': 'v0.3.7.1',
            'body': '**P0** 修启动崩溃',
            'assets': [
              {
                'name': 'sanyelive-v0.3.7.1+21-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/apk.apk',
              },
            ],
          });
        }),
        currentVersionCode: 20,
      );
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckOutdated>());
      expect((state as VersionCheckOutdated).isCritical, isTrue);
    });

    test('mock Dio 抛错 → state = VersionCheckFailed + 写 last_check_time',
        () async {
      final container = await buildContainer(adapter: _FailingAdapter());
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckFailed>());

      final lastCheck = prefs.getInt('version_checker.last_check_time');
      expect(lastCheck, isNotNull);
      expect(
          lastCheck, lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch));
    });

    test('1h 内 cache 命中 → 保持 idle,  不写 state', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(
          'version_checker.last_check_time', now - 30 * 60 * 1000);

      final container = await buildContainer(adapter: _FailingAdapter());
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      expect(container.read(versionCheckerProvider), isA<VersionCheckIdle>());
    });

    test('1h 外 cache 过期 → 走 fetch 路径 (mock 抛错 → failed,  写新 last_check_time)',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(
          'version_checker.last_check_time', now - 2 * 60 * 60 * 1000);

      final container = await buildContainer(adapter: _FailingAdapter());
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      expect(container.read(versionCheckerProvider), isA<VersionCheckFailed>());

      final newLastCheck = prefs.getInt('version_checker.last_check_time');
      expect(newLastCheck, isNotNull);
      expect(newLastCheck!, greaterThan(now - 2 * 60 * 60 * 1000));
    });

    test('dismiss 24h 内同版本不再弹 outdated', () async {
      // 预先 dismiss v0.3.8 (24h 内).
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString('version_checker.dismissed_version', 'v0.3.8');
      await prefs.setInt(
          'version_checker.dismissed_at', now - 1 * 60 * 60 * 1000);

      // 把 last_check_time 设到 2h 前 → 走 fetch 路径.
      await prefs.setInt(
          'version_checker.last_check_time', now - 2 * 60 * 60 * 1000);

      final container = await buildContainer(
        adapter: _MockAdapter((opts) async {
          return _jsonBody({
            'tag_name': 'v0.3.8',
            'body': 'new',
            'assets': [
              {
                'name': 'sanyelive-v0.3.8+21-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/apk.apk',
              },
            ],
          });
        }),
        currentVersionCode: 20,
      );
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      // dismissed → state 不应是 outdated,  而应是 upToDate (静默路径).
      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckUpToDate>(),
          reason: 'dismiss 24h 内同版本应静默不弹');
    });

    test('resetCache 清除所有持久化 key', () async {
      await prefs.setInt('version_checker.last_check_time', 12345);
      await prefs.setString('version_checker.last_seen_version', 'v0.3.7');
      await prefs.setString('version_checker.dismissed_version', 'v0.3.7');
      await prefs.setInt('version_checker.dismissed_at', 67890);

      final container = await buildContainer(adapter: _FailingAdapter());
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).resetCache();

      expect(prefs.getInt('version_checker.last_check_time'), isNull);
      expect(prefs.getString('version_checker.last_seen_version'), isNull);
      expect(prefs.getString('version_checker.dismissed_version'), isNull);
      expect(prefs.getInt('version_checker.dismissed_at'), isNull);
    });

    test('反向升级保护: 服务端 versionCode 152 < 本地 2168 时不弹 outdated', () async {
      // 模拟用户截图场景: 当前版本字符串异常 0.3.12.168+2168,
      // 服务端返回更低版本 v0.3.12.152 / build 152.
      final container = await buildContainer(
        adapter: _MockAdapter((opts) async {
          return _jsonBody({
            'tag_name': 'v0.3.12.152',
            'body': '旧版本',
            'assets': [
              {
                'name': 'sanyelive-v0.3.12+152-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/apk.apk',
              },
            ],
          });
        }),
        currentVersionCode: 2168,
        currentVersionString: '0.3.12.168+2168',
      );
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckUpToDate>(),
          reason: '服务端 versionCode 更低时绝不能反向提示升级');
    });

    test('异常版本字符串解析: 0.3.12.168+2168 识别为 build 2168', () async {
      // 通过集成测试间接验证 _parseVersion 对 0.3.12.168+2168 的解析:
      // 服务端 tag v0.3.12.2168 / build 2168 与本地相等 → upToDate.
      final container = await buildContainer(
        adapter: _MockAdapter((opts) async {
          return _jsonBody({
            'tag_name': 'v0.3.12.2168',
            'body': '同版本',
            'assets': [
              {
                'name': 'sanyelive-v0.3.12+2168-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/apk.apk',
              },
            ],
          });
        }),
        currentVersionCode: 2168,
        currentVersionString: '0.3.12.168+2168',
      );
      addTearDown(container.dispose);

      await container.read(versionCheckerProvider.notifier).checkOnStartup();

      final state = container.read(versionCheckerProvider);
      expect(state, isA<VersionCheckUpToDate>(),
          reason: '应把 0.3.12.168+2168 里的 +2168 当 build 而不是 .168');
    });
  });
}
