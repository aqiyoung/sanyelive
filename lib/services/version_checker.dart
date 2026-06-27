// 0.3.7+20 后台强制更新 (P1 feature, 6/18 老板拍板).
//
// 职责:
//   - 启动时异步拉 GitHub releases/latest,  解析 tag_name + APK asset
//     名里的 versionCode.
//   - 对比当前 pubspec.yaml versionCode,  判断 outdated / upToDate / failed.
//   - 持久化 last_check_time / last_seen_version / dismissed_version
//     (用 sharedPreferencesProvider,  main.dart 注入).
//   - < 1h 用 cache,  24h 后再 fetch.  fail 静默 (后台任务,  弹窗会骚扰).
//
// 数据流:
//   runApp → microtask → versionCheckerProvider.notifier.checkOnStartup()
//     → 1. 读 prefs,  < 1h 跳 fetch → 直接 return cache
//     → 2. fetch GitHub API (dio + 5s timeout)
//     → 3. parse tag_name + assets[].name 里的 versionCode
//     → 4. 对比 currentVersion (pubspec 编译期 const,  传进来)
//          用 semver + build 比较 (v0.3.10.4 修): 之前只比 build int,
//          0.3.10+2 < 0.3.9+3 (2<3) → 永远判 upToDate.  现在比
//          major.minor.patch 优先, 一样再比 build.
//     → 5. 写 last_check_time,  标记 outdated → 弹 ForceUpdateDialog
//     → 6. upToDate / failed → 静默 return
//
// Riverpod Notifier 设计:
//   - VersionCheckState (sealed): idle / upToDate / outdated / failed.
//   - state 被 build 内 ref.watch 监听,  main.dart 用 ref.listen 弹 dialog.
//   - 写操作 (dismissedVersion / checkNow) 通过 notifier 方法.
//
// P0/critical:
//   - 用 release body 第一个 `**P0**` / `**critical**` 关键词识别,  命中
//     后 dialog 不显示"稍后"按钮,  必须更新.  其他 P1 提级不强制.
//   - 如果 release body 缺 P0 标记,  默认 non-critical.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/features/settings/theme_provider.dart'
    show sharedPreferencesProvider;

/// GitHub releases API endpoint fallback chain (v0.3.10.13).
/// v0.3.10.7~v0.3.10.12 历史:
///   gh-proxy.com 403 (rate limit) → cf-workers-proxy 被 CF 保护返 HTML → 链式 fallback.
/// v0.3.10.13 (6/24) 重排: 直连优先 + cf-worker 兜底.
///   curl 实测 (6/24 本机不走代理):
///     - api.github.com 直连 → 200 OK 0.6s ✅ (国内能直连, 最快最稳)
///     - cf-workers-proxy-9e9.pages.dev → 200 OK 1.3~2.8s ✅ (直连不通时兜底)
///     - gh-proxy.com → 403 rate limit (共享 IP 被限, 不再使用)
///   APP 运行环境 (用户手机/盒子) 未必能直连 GitHub,  所以保留 cf-worker 兜底.
///   gh-proxy.com 彻底弃用 (403 频率太高, chain 里放它只会浪费一次超时).
const List<String> kDefaultEndpointUrls = [
  'https://api.github.com/repos/aqiyoung/iptv-app/releases/latest', // primary: 直连 (0.6s, 6/24 实测)
];

/// 兼容老代码 — 取 chain[0]. 单元测试可 overrideWithValue.
String get kDefaultEndpointUrl => kDefaultEndpointUrls.first;

/// v0.3.7+85: 用户在设置页可改的 endpoint URL.
/// v0.3.7+92: 默认 endpoint 改为 gh-proxy.com (代理 api.github.com,
///   国内 600ms).  老板手机国内直连 api.github.com 超时.
///   老板还是能改成 gh-proxy.net / 自建镜像 (NAS + nginx 反代 api.github.com).
/// SharedPreferences 持久化.
const String kEndpointPrefsKey = 'version_checker.endpoint_url';

/// v0.3.10.13 (6/24): 默认改为直连 api.github.com.
/// 老版本可能存了 gh-proxy.com,  build() 自动迁移到直连.
/// 当前 endpoint URL — 默认 api.github.com 直连.
/// 单元测试可 overrideWithValue.
/// 用 Notifier 实现 (跟 themeMode 一样), 改 URL 时持久化.
class EndpointNotifier extends Notifier<String> {
  late final SharedPreferences _prefs;

  @override
  String build() {
    _prefs = ref.read(sharedPreferencesProvider);
    // v0.3.10.13 (6/24): 默认改为直连 api.github.com.
    // 老版本 (+85~+92) 可能在 prefs 里存了 gh-proxy.com URL.
    // 如果 prefs 里是 gh-proxy.com, 迁移到直连 api.github.com.
    // 其他自定义 URL (cf-worker / 自建镜像 / NAS) 不动.
    final stored = _prefs.getString(kEndpointPrefsKey);
    if (stored == null) return kDefaultEndpointUrl;
    // 迁移: gh-proxy.com → api.github.com 直连
    if (stored.contains('gh-proxy.com/api.github.com')) {
      final uri = Uri.tryParse(stored);
      final migrated = uri != null
          ? 'https://api.github.com${uri.path}'
          : kDefaultEndpointUrl;
      // ignore: discarded_futures
      _prefs.setString(kEndpointPrefsKey, migrated);
      debugPrint('EndpointNotifier: migrated gh-proxy -> direct: $migrated');
      // ignore: discarded_futures
      _prefs.remove(_Keys.lastCheckTime);
      return migrated;
    }
    return stored;
  }

  /// 用户改 endpoint — 持久化 + state 更新.
  /// v0.3.7+86 (6/20 老板测试反馈): 加 URL validate, 防止老板填错 URL
  /// (e.g. 拼写错, 缺 https://, 多余空格)  → fetch 失败 → 1h 内不重试.
  /// validate 规则: 非空 + 是合法 http/https URL.
  /// 返回 String? error message, null = 成功.
  String? validateEndpoint(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'URL 不能为空';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return 'URL 格式错误';
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL 必须以 http:// 或 https:// 开头';
    }
    if (uri.host.isEmpty) return 'URL 缺少域名';
    return null;
  }

  Future<void> setEndpoint(String url) async {
    final trimmed = url.trim();
    if (validateEndpoint(trimmed) != null) return; // 验证失败, 不写
    await _prefs.setString(kEndpointPrefsKey, trimmed);
    state = trimmed;
  }

  /// 重置回默认 (api.github.com 直连).
  Future<void> resetEndpoint() async {
    await _prefs.remove(kEndpointPrefsKey);
    state = kDefaultEndpointUrl;
  }
}

final endpointProvider =
    NotifierProvider<EndpointNotifier, String>(EndpointNotifier.new);

/// 兼容旧代码 — get kGitHubReleasesUrl 改成 get endpoint.
@Deprecated('Use endpointProvider instead')
String get kGitHubReleasesUrl => kDefaultEndpointUrl;

/// 当前 APP versionCode — 由 main.dart 在 ProviderContainer 初始化时
/// 注入.  编译期 const (来自 pubspec.yaml),  单元测试可 mock.
final currentVersionCodeProvider = Provider<int>((ref) {
  throw UnimplementedError(
    'currentVersionCodeProvider 必须在 ProviderContainer 里 override '
    '(用 PackageInfo 或者硬编码)',
  );
});

/// 当前 APP version string (e.g. "0.3.7") — 同上,  ProviderContainer override.
final currentVersionStringProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'currentVersionStringProvider 必须在 ProviderContainer 里 override',
  );
});

/// 持久化 key (跟 SharedPreferences 一起用).
class _Keys {
  static const lastCheckTime = 'version_checker.last_check_time';
  static const lastSeenVersion = 'version_checker.last_seen_version';
  static const dismissedVersion = 'version_checker.dismissed_version';
  static const dismissedAt = 'version_checker.dismissed_at';
}

/// Cache 有效期 — 1h 内不再 fetch (避免每启都打 GitHub).
const Duration _kCacheTtl = Duration(hours: 1);

/// 用户点"稍后"后,  24h 内不再弹 (避免 P1 反复骚扰).
const Duration _kDismissTtl = Duration(hours: 24);

/// 强制更新检测结果.
sealed class VersionCheckState {
  const VersionCheckState();
}

/// 还没 check 过,  或上次 check 失败被静默吞掉.
class VersionCheckIdle extends VersionCheckState {
  const VersionCheckIdle();
}

/// 已经是最新.
class VersionCheckUpToDate extends VersionCheckState {
  const VersionCheckUpToDate(this.currentVersion, this.latestVersion);
  final String currentVersion;
  final String latestVersion;
}

/// 有新版本.
class VersionCheckOutdated extends VersionCheckState {
  const VersionCheckOutdated({
    required this.latestVersion,
    required this.latestVersionCode,
    required this.currentVersion,
    required this.apkAssetName,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    required this.isCritical,
  });

  final String latestVersion;
  final int latestVersionCode;
  final String currentVersion;
  final String apkAssetName;
  final String apkDownloadUrl;
  final String releaseNotes;

  /// P0/critical:  release body 含 "**P0**" 或 "**critical**" 标记 → 强制更新,
  /// dialog 不显示"稍后"按钮.
  final bool isCritical;
}

/// 拉版本失败 (网络/parse).  静默,  不骚扰用户.
class VersionCheckFailed extends VersionCheckState {
  const VersionCheckFailed(this.reason);
  final String reason;
}

/// Notifier 主体.  Notifier 是 Riverpod 2.x 推荐写法 (替代 StateNotifier).
class VersionCheckerNotifier extends Notifier<VersionCheckState> {
  late final Dio _dio;
  late final SharedPreferences _prefs;
  bool _checking = false; // v0.3.8+169: 防并发 checkOnStartup.

  @override
  VersionCheckState build() {
    _dio = ref.read(dioProvider);
    _prefs = ref.read(sharedPreferencesProvider);
    return const VersionCheckIdle();
  }

  /// v0.3.10.9 (6/23 老板反馈): settings 手动点 "检查更新" 调 force check,
  /// 跳过 1h cache. 1h cache 是为启动自动 check 设计, 不应该阻塞用户手动 retry.
  Future<void> checkForce() async {
    if (_checking) return;
    _checking = true;
    try {
      // 清掉 cache + dismissed marker, 强制 fetch.
      await _prefs.remove(_Keys.lastCheckTime);
      await _prefs.remove(_Keys.dismissedVersion);
      await _prefs.remove(_Keys.dismissedAt);
      state =
          const VersionCheckIdle(); // 先清状态, 让 settings 弹个 loading / 直接 fetch
      // 复用 checkOnStartup 逻辑 (清完 cache 就走 fetch path)
      await checkOnStartup();
    } finally {
      _checking = false;
    }
  }

  /// 启动时调 — 走 cache 策略 + 异步 fetch.
  /// 立即返回 (microtask 里跑),  弹 dialog 由 main.dart listen state.
  Future<void> checkOnStartup() async {
    if (_checking) return; // v0.3.8+169: 防并发 checkOnStartup
    _checking = true;
    try {
      // 1. cache 命中 (< 1h) → 直接跳过 fetch,  state 保持 idle
      final lastCheck = _prefs.getInt(_Keys.lastCheckTime);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lastCheck != null && (now - lastCheck) < _kCacheTtl.inMilliseconds) {
        // 启动时 cache 路径不更新 state,  让 UI 不弹窗.  如果用户上次 dismiss
        // 了一个版本,  这里也不重新触发,  因为还没 fetch.
        return;
      }

      // 2. fetch GitHub API
      final release = await _fetchLatestRelease();
      final parsed = _parseRelease(release);
      if (parsed == null) {
        state = const VersionCheckFailed('parse failed');
        await _prefs.setInt(_Keys.lastCheckTime, now);
        return;
      }

      final currentCode = ref.read(currentVersionCodeProvider);
      final currentStr = ref.read(currentVersionStringProvider);

      // 写 last_seen_version (无论 outdated / upToDate 都写,  方便诊断).
      await _prefs.setString(_Keys.lastSeenVersion, parsed.tagName);

      // v0.3.10.4 (6/23 老板反馈): 之前只比 parsed.versionCode (build int)
      // vs currentCode,  semver 不比.  e.g.  老板装 0.3.9+3 (build=3),
      // 发 v0.3.10+2 (build=2) → 2 > 3 = false → 永远判 upToDate.
      // 修法: 先用 semver (major.minor.patch) 比,  一样再比 build.
      //   parsed.tagName = 'v0.3.10.2' 或 'v0.3.10.4' (GitHub tag 格式)
      //   currentStr     = '0.3.9'  或 '0.3.10+5' (pubspec current)
      //  _compareVersions 接受 'v' 前缀 + 可选 '+N',  容错.
      final cmp = _compareVersions(parsed.tagName, currentStr);
      final isOutdated =
          cmp > 0 || (cmp == 0 && parsed.versionCode > currentCode);

      if (isOutdated) {
        // 3. outdated — 检查是否被用户 dismiss 过
        final dismissedVer = _prefs.getString(_Keys.dismissedVersion);
        final dismissedAt = _prefs.getInt(_Keys.dismissedAt);
        if (dismissedVer == parsed.tagName &&
            dismissedAt != null &&
            (now - dismissedAt) < _kDismissTtl.inMilliseconds) {
          // 24h 内 dismiss 过了,  静默不弹.
          state = const VersionCheckUpToDate('current', 'current');
          await _prefs.setInt(_Keys.lastCheckTime, now);
          return;
        }

        state = VersionCheckOutdated(
          latestVersion: parsed.tagName,
          latestVersionCode: parsed.versionCode,
          currentVersion: currentStr,
          apkAssetName: parsed.apkAssetName,
          apkDownloadUrl: parsed.apkDownloadUrl,
          releaseNotes: parsed.releaseNotes,
          isCritical: parsed.isCritical,
        );
      } else {
        state = VersionCheckUpToDate(currentStr, parsed.tagName);
      }

      await _prefs.setInt(_Keys.lastCheckTime, now);
    } on DioException catch (e) {
      state = VersionCheckFailed('network: ${e.type}');
      // 失败也写 last_check_time,  避免每启都重试刷流量.  下次 1h 后再试.
      await _prefs.setInt(
          _Keys.lastCheckTime, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      state = VersionCheckFailed('error: $e');
      await _prefs.setInt(
          _Keys.lastCheckTime, DateTime.now().millisecondsSinceEpoch);
    } finally {
      _checking = false;
    }
  }

  /// 用户点"稍后" — 记录 dismissed_version + dismissed_at,  24h 不再弹.
  /// P0/critical 时调用方 (dialog) 不暴露这个按钮.
  Future<void> markDismissed() async {
    final s = state;
    if (s is! VersionCheckOutdated) return;
    await _prefs.setString(_Keys.dismissedVersion, s.latestVersion);
    await _prefs.setInt(
      _Keys.dismissedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    // 弹完后 state 回到 idle,  不让 main.dart 的 listener 二次弹.
    state = const VersionCheckIdle();
  }

  /// 强制重置 cache (测试 / 用户手动"重新检查"用).
  Future<void> resetCache() async {
    await _prefs.remove(_Keys.lastCheckTime);
    await _prefs.remove(_Keys.lastSeenVersion);
    await _prefs.remove(_Keys.dismissedVersion);
    await _prefs.remove(_Keys.dismissedAt);
  }

  /// @visibleForTesting — 跳开 fetch,  直接在 state 设 outdated/upToDate.
  /// Riverpod 的 Notifier.state setter 是 @protected,  不能从外面调,
  /// 这里包一层.  测试用,  生产代码不要调.
  @visibleForTesting
  void debugSetState(VersionCheckState newState) {
    state = newState;
  }

  // -------- private: 网络 --------

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    // v0.3.10.7: endpoint fallback chain — 主 endpoint 失败自动试下一个.
    // 老板 6/23 反馈: gh-proxy.com 突然 403 rate limit, 之前一直没换.
    // 用户在设置页可能自定义 URL (prefs.endpoint), 优先用用户的; 用户没设置
    // 或 fallback 全失败时才走 chain 默认值.
    final custom = ref.read(endpointProvider);
    final chain = <String>[
      if (custom != kDefaultEndpointUrl) custom,
      ...kDefaultEndpointUrls,
    ];
    // 去重 (用户 URL 可能在 chain 里)
    final seen = <String>{};
    final ordered = <String>[];
    for (final url in chain) {
      if (seen.add(url)) ordered.add(url);
    }

    String? lastError;
    for (final url in ordered) {
      try {
        // v0.3.10.9: responseType=plain,  让 dio 不自动 parse JSON.  我们自己
        // 检测 body 是不是 JSON (cf-workers-proxy 6/23 11:50 返 HTML 会让
        // 默认 json parser 抛 FormatException → 整个 chain 都 fail).
        final resp = await _dio.get<dynamic>(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 8),
            responseType: ResponseType.plain,
          ),
        );
        if (resp.statusCode == 200) {
          final data = resp.data;
          // v0.3.10.9 (6/23): responseType=plain → resp.data 永远是 String.
          // 手动 decode JSON,  先检测 HTML / 非 JSON 再 parse.
          if (data is String) {
            final s = data.replaceFirst(RegExp(r'^\s+'), '');
            if (s.startsWith('<') || s.startsWith('<!DOCTYPE')) {
              lastError =
                  'HTML response (CF protective registration?) from $url';
              continue;
            }
            try {
              final decoded = jsonDecode(s);
              if (decoded is Map<String, dynamic>) {
                if (url != custom) {
                  // ignore: discarded_futures
                  _prefs.setString(kEndpointPrefsKey, url);
                }
                return decoded;
              }
              lastError = 'non-Map JSON from $url';
            } catch (_) {
              lastError =
                  'invalid JSON from $url: ${s.substring(0, s.length.clamp(0, 80))}';
            }
          } else {
            lastError = 'unexpected data type from $url (${data.runtimeType})';
          }
        } else {
          lastError = 'HTTP ${resp.statusCode} from $url';
        }
      } on DioException catch (e) {
        lastError = '${e.type} from $url';
        debugPrint('version_checker: $url → $e');
      } catch (e) {
        lastError = '$e from $url';
        debugPrint('version_checker: $url → $e');
      }
    }
    throw Exception('All endpoints failed: $lastError');
  }

  _ParsedRelease? _parseRelease(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) return null;

    // 找 sanyelive-v0.3.7+20-arm64-v8a.apk 这样的 asset.
    // 优先 arm64-v8a (国内 TV/盒子主架构),  没有就拿第一个 .apk.
    final assets = json['assets'] as List<dynamic>?;
    if (assets == null) return null;

    String? apkName;
    String? apkUrl;
    for (final a in assets) {
      if (a is! Map<String, dynamic>) continue;
      final name = a['name'] as String? ?? '';
      if (!name.endsWith('.apk')) continue;
      // arm64-v8a 优先
      if (name.contains('arm64-v8a') || apkName == null) {
        apkName = name;
        apkUrl = a['browser_download_url'] as String?;
        if (name.contains('arm64-v8a')) break;
      }
    }
    if (apkName == null || apkUrl == null) return null;

    // 从 asset name 提 versionCode: sanyelive-v0.3.7+20-arm64-v8a.apk → 20
    // 用 +N 模式.
    final versionCode = _extractVersionCode(apkName);
    if (versionCode == null) return null;

    final body = (json['body'] as String?) ?? '';
    final isCritical = _isCriticalRelease(body);

    return _ParsedRelease(
      tagName: tagName,
      versionCode: versionCode,
      apkAssetName: apkName,
      apkDownloadUrl: apkUrl,
      releaseNotes: body,
      isCritical: isCritical,
    );
  }

  // -------- private: version compare (v0.3.10.4 新增) --------

  /// Semver + build 比较. 返 1 = a > b, 0 = a == b, -1 = a < b.
  /// 接受 '0.3.10+2' / '0.3.10' / 'v0.3.10+2' (带不带 v 前缀都行).
  /// 规则:
  ///   1. 先比 major.minor.patch (semver 主版本)
  ///   2. 一样再比 build number (Flutter pubspec 的 +N)
  ///   3. 任一更大 → 算 newer
  ///  解析失败 → fallback 到字符串字典序比较.
  int _compareVersions(String a, String b) {
    final aParts = _parseVersion(a);
    final bParts = _parseVersion(b);
    if (aParts == null || bParts == null) {
      // fallback: 简单字符串比较, 至少保证 a vs b 不会误判相等.
      return a.compareTo(b);
    }
    for (var i = 0; i < 3; i++) {
      if (aParts.$1[i] != bParts.$1[i]) {
        return aParts.$1[i] > bParts.$1[i] ? 1 : -1;
      }
    }
    // major.minor.patch 一样 → 比 build.  build 缺省 = 0.
    if (aParts.$2 != bParts.$2) {
      return aParts.$2 > bParts.$2 ? 1 : -1;
    }
    return 0;
  }

  /// 解析版本字符串 → ((major, minor, patch), build).
  /// 接受 '0.3.10+2' / '0.3.10' / 'v0.3.10+2' / 'v0.3.10.5'.
  /// tag 历史两种格式都有:  老版 v0.3.8+N,  新版 v0.3.10.5 (4 段, 第 4 段当 build).
  /// 返回 null = 解析失败.
  (List<int>, int)? _parseVersion(String v) {
    var cleaned = v.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1);
    }
    // 接受两种 4 段格式: '0.3.10+N' 或 '0.3.10.N'.  两者第 4 段都是 build.
    final m =
        RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:[.+](\d+))?$').firstMatch(cleaned);
    if (m == null) return null;
    return (
      [
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      ],
      m.group(4) != null ? int.parse(m.group(4)!) : 0,
    );
  }

  static int? _extractVersionCode(String apkName) {
    // 找 "+数字" —  e.g.  "v0.3.7+20-arm64-v8a.apk" → 20.
    final match = RegExp(r'\+(\d+)').firstMatch(apkName);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static bool _isCriticalRelease(String body) {
    // release body 第一个非空行含 "**P0**" 或 "**critical**" (case-insensitive).
    final firstLine = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final lower = firstLine.toLowerCase();
    return lower.contains('**p0**') || lower.contains('**critical**');
  }

  // -------- @visibleForTesting 入口 --------
  // 测试不依赖 Dio,  直接验证 parse 逻辑.  private static → 改写成 public 静态
  // 包装,  保持 production 调用路径不变.

  @visibleForTesting
  static int? debugExtractVersionCode(String apkName) =>
      _extractVersionCode(apkName);

  @visibleForTesting
  static bool debugIsCriticalRelease(String body) => _isCriticalRelease(body);

  @visibleForTesting
  int debugCompareVersions(String a, String b) => _compareVersions(a, b);

  @visibleForTesting
  static Map<String, dynamic>? debugParseRelease(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) return null;

    final assets = json['assets'] as List<dynamic>?;
    if (assets == null) return null;

    String? apkName;
    String? apkUrl;
    for (final a in assets) {
      if (a is! Map<String, dynamic>) continue;
      final name = a['name'] as String? ?? '';
      if (!name.endsWith('.apk')) continue;
      if (name.contains('arm64-v8a') || apkName == null) {
        apkName = name;
        apkUrl = a['browser_download_url'] as String?;
        if (name.contains('arm64-v8a')) break;
      }
    }
    if (apkName == null || apkUrl == null) return null;

    final versionCode = _extractVersionCode(apkName);
    if (versionCode == null) return null;

    final body = (json['body'] as String?) ?? '';
    final isCritical = _isCriticalRelease(body);

    return {
      'tagName': tagName,
      'versionCode': versionCode,
      'apkAssetName': apkName,
      'apkDownloadUrl': apkUrl,
      'releaseNotes': body,
      'isCritical': isCritical,
    };
  }
}

class _ParsedRelease {
  _ParsedRelease({
    required this.tagName,
    required this.versionCode,
    required this.apkAssetName,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    required this.isCritical,
  });
  final String tagName;
  final int versionCode;
  final String apkAssetName;
  final String apkDownloadUrl;
  final String releaseNotes;
  final bool isCritical;
}

/// 暴露给 main.dart / dialog 用的 provider.
final versionCheckerProvider =
    NotifierProvider<VersionCheckerNotifier, VersionCheckState>(
  VersionCheckerNotifier.new,
);

/// Dio provider — 默认 new Dio() (生产).  测试可 overrideWithValue 注入 mock.
/// 用了 ref.read 创建,  避免 Notifier.build() 多次跑时重建 Dio.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 8),
  ));
  ref.onDispose(dio.close);
  return dio;
});
