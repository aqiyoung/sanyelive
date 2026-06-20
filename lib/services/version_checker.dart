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
//     → 4. 对比 currentVersionCode (pubspec 编译期 const,  传进来)
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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/features/settings/theme_provider.dart'
    show sharedPreferencesProvider;

/// GitHub releases API endpoint — 默认国内中转 gh-proxy.com.
/// v0.3.7+85 (6/20 老板反馈): 老板手机国内访问 api.github.com 经常超时,
/// v0.3.7+92 (6/20 08:42 老板反馈): 老板手机上 '更新提示网络错误',  加 endpointProvider
///   还不够,  默认 endpoint 必须本身是国内可达的.  测试下来:
///     - gh-proxy.com/api.github.com/...  (600ms,  OK)
///     - ghproxy.com/https://api.github.com/...  (timeout,  废)
///     - mirror.ghproxy.com/...  (timeout,  废)
///     - api.npmmirror.com/...  (DNS 解析不到)
///     - gh-proxy.net/...  (域名被劫持到广告,  废)
///     - cf-workers-proxy-9e9.pages.dev/...  (已拄,  protective registration)
///     - github.moeyy.cn/...  (DNS 解析不到)
///   唯一可靠 = https://gh-proxy.com/api.github.com/...  (Cloudflare CDN,  河南郑州高防)
///   格式: 不要带 https://,  直接 https://gh-proxy.com/api.github.com/...
///   (不要试 https://gh-proxy.com/https://api.github.com/...,  403 rate limit)
const String kDefaultEndpointUrl =
    'https://gh-proxy.com/api.github.com/repos/aqiyoung/iptv-app/releases/latest';

/// v0.3.7+85: 用户在设置页可改的 endpoint URL.
/// v0.3.7+92: 默认 endpoint 改为 gh-proxy.com (代理 api.github.com,
///   国内 600ms).  老板手机国内直连 api.github.com 超时.
///   老板还是能改成 gh-proxy.net / 自建镜像 (NAS + nginx 反代 api.github.com).
/// SharedPreferences 持久化.
const String kEndpointPrefsKey = 'version_checker.endpoint_url';

/// v0.3.7+92: 老默认 endpoint (api.github.com 直连) — 用于迁移.
/// 老板已装 +85~+91 版本,  prefs 里可能存了老 URL,  build() 会
/// 检测到然后升级到 gh-proxy.com.  kLegacyEndpointUrl 是常量化.
/// 迁移后这个常量可删 (加个 v0.3.8 + N release 清理).
const String kLegacyEndpointUrl =
    'https://api.github.com/repos/aqiyoung/iptv-app/releases/latest';

/// 当前 endpoint URL — 默认 gh-proxy.com 代理 api.github.com.
/// 单元测试可 overrideWithValue.
/// 用 Notifier 实现 (跟 themeMode 一样), 改 URL 时持久化.
class EndpointNotifier extends Notifier<String> {
  late final SharedPreferences _prefs;

  @override
  String build() {
    _prefs = ref.read(sharedPreferencesProvider);
    // v0.3.7+92 (6/20 08:42 老板反馈): 老板已装 +85~+91 时在 prefs 里存了老默认
    // api.github.com 直连 (国内超时).  APP 升级到 +92 后,  启动时检测到 prefs 里的
    // URL == 老默认,  自动迁移到新默认 gh-proxy.com (国内 600ms 响应).
    // v0.3.8+95 (6/20 12:35 老板反馈): 不限于精确匹配 kLegacyEndpointUrl.
    // 老板可能手动改过 URL (例如 上一版他填了自己的中转), 但如果 URL 还含
    // api.github.com/repos/* 就自动迁移到 gh-proxy.com 包起来.
    // 手动填的非 github URL (e.g. NAS 自建镜像) 不动.
    // 之前 exact-match 迁不到, 老板装 +94 后还会看到老 URL 报网络错.
    final stored = _prefs.getString(kEndpointPrefsKey);
    if (stored == null) return kDefaultEndpointUrl;
    // 迁移规则: URL 含 'api.github.com/repos/' 且 不含 'gh-proxy.com'
    // → 包成 'https://gh-proxy.com/api.github.com/repos/.../releases/latest'
    final migrated = _migrateGithubUrl(stored);
    if (migrated != stored) {
      // ignore: discarded_futures
      _prefs.setString(kEndpointPrefsKey, migrated);
      debugPrint('EndpointNotifier: migrated $stored -> $migrated');
      return migrated;
    }
    return stored;
  }

  /// 迁移老 api.github.com URL 到 gh-proxy.com 代理.
  /// 返回 null = 不需要迁移 (URL 已经是新格式 或 用户自填的).
  /// 返回非空 = 迁移后 URL.
  String _migrateGithubUrl(String url) {
    // 已经是 gh-proxy.com 包过的 → 不动
    if (url.contains('gh-proxy.com')) return url;
    // 含 api.github.com/repos/ → 包成 gh-proxy.com
    if (url.contains('api.github.com/repos/')) {
      // 提取 path 部分 (api.github.com/ 之后的所有)
      final uri = Uri.tryParse(url);
      if (uri == null) return url;
      // 重组: https://gh-proxy.com/api.github.com/repos/{owner}/{repo}/releases/latest
      return 'https://gh-proxy.com/api.github.com${uri.path}';
    }
    return url;
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

  /// 重置回默认 (gh-proxy.com 代理 api.github.com).
  Future<void> resetEndpoint() async {
    await _prefs.remove(kEndpointPrefsKey);
    state = kDefaultEndpointUrl;
  }
}

final endpointProvider = NotifierProvider<EndpointNotifier, String>(EndpointNotifier.new);

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

  @override
  VersionCheckState build() {
    _dio = ref.read(dioProvider);
    _prefs = ref.read(sharedPreferencesProvider);
    return const VersionCheckIdle();
  }

  /// 启动时调 — 走 cache 策略 + 异步 fetch.
  /// 立即返回 (microtask 里跑),  弹 dialog 由 main.dart listen state.
  Future<void> checkOnStartup() async {
    // 1. cache 命中 (< 1h) → 直接跳过 fetch,  state 保持 idle
    final lastCheck = _prefs.getInt(_Keys.lastCheckTime);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastCheck != null && (now - lastCheck) < _kCacheTtl.inMilliseconds) {
      // 启动时 cache 路径不更新 state,  让 UI 不弹窗.  如果用户上次 dismiss
      // 了一个版本,  这里也不重新触发,  因为还没 fetch.
      return;
    }

    // 2. fetch GitHub API
    try {
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

      if (parsed.versionCode > currentCode) {
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
      await _prefs.setInt(_Keys.lastCheckTime, now);
    } catch (e) {
      state = VersionCheckFailed('error: $e');
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

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    // v0.3.7+85: 用 endpointProvider 而不是 const URL.  让老板在设置页改.
    final url = ref.read(endpointProvider);
    final resp = await _dio.get<dynamic>(url);
    final data = resp.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('GitHub API 返回非 JSON object');
    }
    return data;
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
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 8),
  ));
});
