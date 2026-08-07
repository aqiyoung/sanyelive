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

///   FeiNiuMusic 标准做法 (已验证可用): 用 `/releases/latest` 单请求拿最新
///   stable release, 并带 `User-Agent` + `Accept` 头.  GitHub API 对**没有
///   User-Agent 的请求会直接 403 拒掉** — 这正是旧版"检查不到更新"的根因
///   (请求被静默失败, 不弹窗).  参照 FeiNiuMusic 补上请求头后即稳定.
///   sanyelive 的 release 非 pre-release, `/releases/latest` 即最新版.
/// GitHub API 基础 URL (直连).  镜像 fallback 会在此基础上加前缀.
const String _kGitHubApiBaseUrl =
    'https://api.github.com/repos/aqiyoung/sanyelive/releases/latest';

/// 国内 GitHub 镜像前缀列表.  当直连 `api.github.com` 失败时, 自动依次尝试.
/// 用法: `$prefix$_kGitHubApiBaseUrl`, APK 下载链接同理由 `$prefix$originalUrl` 代理.
/// 顺序: 直连优先 → 公共镜像.  这些镜像在国内移动网络通常可用.
const List<String> _kGitHubProxyPrefixes = [
  '', // 直连
  'https://gh-proxy.com/',
  'https://ghps.cc/',
  'https://github.moeyy.xyz/',
  'https://gh.api.99988866.xyz/',
];

/// 兼容老代码 — 取基础 URL. 单元测试可 overrideWithValue.
const List<String> kDefaultEndpointUrls = [_kGitHubApiBaseUrl];

/// FeiNiuMusic 同款请求头 — GitHub API 必须有 User-Agent, 否则 403.
const Map<String, String> kGitHubApiHeaders = {
  'User-Agent': 'sanyelive',
  'Accept': 'application/vnd.github.v3+json',
};

/// 兼容老代码 — 取基础 URL. 单元测试可 overrideWithValue.
String get kDefaultEndpointUrl => _kGitHubApiBaseUrl;

/// SharedPreferences 持久化.
const String kEndpointPrefsKey = 'version_checker.endpoint_url';

/// 「启动时自动检查更新」开关持久化键 (默认开启).
const String kAutoCheckUpdateKey = 'version_checker.auto_check_update';

/// 旧版支持自定义更新源 (gh-proxy / 自建镜像),  v0.3.12+128 起停止支持,
/// 统一走 kDefaultEndpointUrls (api.github.com 直连).  残留的自定义 URL
/// 在 VersionCheckerNotifier.build() 里清理, 防止死链导致检查失败.

/// 「启动时自动检查更新」开关 — 默认开启.
/// 关闭后 checkOnStartup() 直接 return (不 fetch);  手动 checkForce() 不受影响.
class AutoCheckUpdateNotifier extends Notifier<bool> {
  late final SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _prefs.getBool(kAutoCheckUpdateKey) ?? true;
  }

  Future<void> set(bool value) async {
    await _prefs.setBool(kAutoCheckUpdateKey, value);
    state = value;
  }
}

final autoCheckUpdateProvider =
    NotifierProvider<AutoCheckUpdateNotifier, bool>(AutoCheckUpdateNotifier.new);

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
    this.releaseName = '',
    required this.latestVersion,
    required this.latestVersionCode,
    required this.currentVersion,
    required this.apkAssetName,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    required this.isCritical,
  });

  final String releaseName;
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
  bool _checking = false;

  @override
  VersionCheckState build() {
    _dio = ref.read(dioProvider);
    _prefs = ref.read(sharedPreferencesProvider);
    // 清理旧版残留的自定义更新源 (已停止支持), 防止死链导致检查失败.
    _prefs.remove(kEndpointPrefsKey);
    return const VersionCheckIdle();
  }

  /// 手动检查 — 设置页"检查更新"按钮调用.
  /// 绕过 1h cache + 24h dismiss, 且**不受**「启动时自动检查更新」开关影响
  /// (旧版错误地调用 checkOnStartup, 开关一关手动检查就直接 return,
  ///  loading 弹窗永不关闭、什么也不显示 — 这正是"检查不到更新"的根因之一).
  Future<void> checkForce() async {
    if (_checking) return;
    _checking = true;
    try {
      // 清掉 cache + dismissed marker, 强制 fetch.
      await _prefs.remove(_Keys.lastCheckTime);
      await _prefs.remove(_Keys.dismissedVersion);
      await _prefs.remove(_Keys.dismissedAt);
      await _performCheck();
    } finally {
      _checking = false;
    }
  }

  /// 启动时调 — 走 cache 策略 + 异步 fetch, 受「自动检查」开关控制.
  /// 立即返回 (microtask 里跑),  弹 dialog 由 main.dart listen state.
  Future<void> checkOnStartup() async {
    if (_checking) return;
    _checking = true;
    try {
      // 用户关闭了「启动时自动检查更新」→ 直接跳过 (手动 checkForce 不受影响).
      if (!ref.read(autoCheckUpdateProvider)) return;

      // 1. cache 命中 (< 1h) → 直接跳过 fetch,  state 保持 idle
      final lastCheck = _prefs.getInt(_Keys.lastCheckTime);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lastCheck != null && (now - lastCheck) < _kCacheTtl.inMilliseconds) {
        // 启动时 cache 路径不更新 state,  让 UI 不弹窗.
        return;
      }

      await _performCheck();
    } finally {
      _checking = false;
    }
  }

  /// 实际执行一次检查 (fetch + 比较 + 写 state).  checkOnStartup / checkForce 共用.
  Future<void> _performCheck() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      // 2. fetch GitHub API (带镜像 fallback)
      final (release, proxyPrefix) = await _fetchLatestRelease();
      final parsed = _parseRelease(release, proxyPrefix);
      if (parsed == null) {
        state = const VersionCheckFailed('parse failed');
        await _prefs.setInt(_Keys.lastCheckTime, now);
        return;
      }

      final currentCode = ref.read(currentVersionCodeProvider);
      final currentStr = ref.read(currentVersionStringProvider);

      // 写 last_seen_version (无论 outdated / upToDate 都写,  方便诊断).
      await _prefs.setString(_Keys.lastSeenVersion, parsed.tagName);

      // 先用 semver (major.minor.patch) 比,  一样再比 build (+N).
      // sanyelive 固定 0.3.12 只涨 build,  必须比 build 才不误判"已最新".
      final cmp = _compareVersions(parsed.tagName, currentStr);
      final isOutdated =
          cmp > 0 || (cmp == 0 && parsed.versionCode > currentCode);

      if (isOutdated) {
        // 检查是否被用户 dismiss 过 (24h 内同版本不再弹).
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
          releaseName: parsed.releaseName,
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
      debugPrint('version_checker: network error → $e');
      state = const VersionCheckFailed('网络连接失败，请检查网络或稍后重试');
      // 失败也写 last_check_time,  避免每启都重试刷流量.  下次 1h 后再试.
      await _prefs.setInt(_Keys.lastCheckTime, now);
    } catch (e) {
      debugPrint('version_checker: unexpected error → $e');
      state = const VersionCheckFailed('检查更新时出错，请稍后重试');
      await _prefs.setInt(_Keys.lastCheckTime, now);
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

  /// 返回 (release JSON, 成功使用的镜像前缀).  前缀用于后续把 APK 下载链接
  /// 也走同一镜像, 避免 API 通了但下载地址被墙.
  Future<(Map<String, dynamic>, String)> _fetchLatestRelease() async {
    String? lastError;
    for (final prefix in _kGitHubProxyPrefixes) {
      final url = prefix.isEmpty ? _kGitHubApiBaseUrl : '$prefix$_kGitHubApiBaseUrl';
      try {
        final resp = await _dio.get<dynamic>(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 10),
            responseType: ResponseType.plain,
            headers: kGitHubApiHeaders,
          ),
        );
        if (resp.statusCode == 200) {
          final data = resp.data;
          if (data is String) {
            final s = data.replaceFirst(RegExp(r'^\s+'), '');
            if (s.startsWith('<') || s.startsWith('<!DOCTYPE')) {
              lastError = 'HTML response from $url';
              continue;
            }
            try {
              final decoded = jsonDecode(s);
              Map<String, dynamic> release;
              if (decoded is List<dynamic>) {
                if (decoded.isEmpty) {
                  lastError = 'empty releases list from $url';
                  continue;
                }
                final first = decoded.first;
                if (first is! Map<String, dynamic>) {
                  lastError = 'first release not a Map from $url';
                  continue;
                }
                release = first;
              } else if (decoded is Map<String, dynamic>) {
                release = decoded;
              } else {
                lastError = 'non-Map/List JSON from $url';
                continue;
              }
              return (release, prefix);
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

  _ParsedRelease? _parseRelease(Map<String, dynamic> json, String proxyPrefix) {
    final tagName = json['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) return null;

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
        final originalUrl = a['browser_download_url'] as String?;
        apkUrl = (originalUrl != null && proxyPrefix.isNotEmpty)
            ? '$proxyPrefix$originalUrl'
            : originalUrl;
        if (name.contains('arm64-v8a')) break;
      }
    }
    if (apkName == null || apkUrl == null) return null;

    // 用 +N 模式.
    final versionCode = _extractVersionCode(apkName);
    if (versionCode == null) return null;

    final body = (json['body'] as String?) ?? '';
    final releaseName = (json['name'] as String?)?.trim() ?? tagName;
    final isCritical = _isCriticalRelease(body);

    return _ParsedRelease(
      tagName: tagName,
      releaseName: releaseName,
      versionCode: versionCode,
      apkAssetName: apkName,
      apkDownloadUrl: apkUrl,
      releaseNotes: body,
      isCritical: isCritical,
    );
  }


  /// Semver + build 比较. 返 1 = a > b, 0 = a == b, -1 = a < b.
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
  /// 返回 null = 解析失败.
  (List<int>, int)? _parseVersion(String v) {
    var cleaned = v.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1);
    }
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
  static Map<String, dynamic>? debugParseRelease(
    Map<String, dynamic> json, {
    String proxyPrefix = '',
  }) {
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
        final originalUrl = a['browser_download_url'] as String?;
        apkUrl = (originalUrl != null && proxyPrefix.isNotEmpty)
            ? '$proxyPrefix$originalUrl'
            : originalUrl;
        if (name.contains('arm64-v8a')) break;
      }
    }
    if (apkName == null || apkUrl == null) return null;

    final versionCode = _extractVersionCode(apkName);
    if (versionCode == null) return null;

    final body = (json['body'] as String?) ?? '';
    final releaseName = (json['name'] as String?)?.trim() ?? tagName;
    final isCritical = _isCriticalRelease(body);

    return {
      'tagName': tagName,
      'releaseName': releaseName,
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
    required this.releaseName,
    required this.versionCode,
    required this.apkAssetName,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    required this.isCritical,
  });
  final String tagName;
  final String releaseName;
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
