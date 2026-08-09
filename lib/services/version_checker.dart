//
// 职责:
//   - 启动时 / 手动检查更新: 拉取 GitHub 最新 release, 解析版本号,
//     与当前安装版本比较, 判断是否 outdated.
//   - 命中 outdated → 由 main.dart / settings_page 的 listener 弹更新弹窗.
//
// ─────────────────────────────────────────────────────────────────────────
// v0.3.12.175 重构 (对齐 FeiNiuMusic 已验证可用实现):
//
// 1) 数据源顺序反转 —— 以 GitHub API `releases/latest` 为权威主源,
//    jsDelivr 上的 meta/version.json 仅作兜底.
//    旧版反过来 (meta 为主源), 而 meta 由 release.yml 异步写回,
//    一旦那步被 `continue-on-error` 吞掉 → meta 永远落后一个版本 →
//    所有用户误判"已最新", 这正是"更新功能一次都没成功过"的根因.
//    GitHub API `releases/latest` 在发版瞬间原子更新, 永不过期,
//    与 FeiNiuMusic 完全一致.
//
// 2) 比较逻辑对齐 FeiNiuMusic:
//    - 当前版本只取 PackageInfo.version (干净的 versionName, 如 "0.3.12.173"),
//      不再自作主张拼上 +versionCode (那会多出一个第 5 段数字, 造成误判).
//    - 远端 tag (如 "v0.3.12.174") 去掉前导 v, 在首个 + / - 处截断,
//      按 "." 切出数字段逐位比较.  major.minor.patch 比完再比 build.
//    这能正确识别 0.3.12.174 > 0.3.12.173, 也正确处理
//    0.3.12.171+2171 这类历史异常包 (截断 + 后只剩 0.3.12.171).
//
// 3) 网络容错: API 走多个代理前缀 (gh.llkk.cc 已验证可直连 GitHub,
//    直连留给 VPN/海外用户), 全部失败才退回 jsDelivr (国内 CDN, 通常可用).
//    每层都带 User-Agent + Accept 头 —— 缺 User-Agent 时 GitHub API 直接 403.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/features/settings/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:sanyelive/utils/crash_logger.dart';

/// GitHub API 基础 URL (直连).  镜像 fallback 会在前面加前缀.
const String _kGitHubApiBaseUrl =
    'https://api.github.com/repos/aqiyoung/sanyelive/releases/latest';

/// API 代理前缀列表 —— 国内/弱网环境直连 api.github.com 会被墙,
/// 依次尝试这些代理;  空串 '' 表示直连 (VPN/海外用户).
/// 顺序: gh.llkk.cc 已实测可穿透到 GitHub API, 直连兜底给翻墙用户.
const List<String> _kApiProxyPrefixes = [
  'https://gh.llkk.cc/',
  '',
];

/// 兜底版本源 —— 放在 `raw.githubusercontent.com` 的 `meta` 分支 (经 jsDelivr CDN).
/// 每次发版由 CI (release.yml) 自动刷新;  作为 API 全部失败时的最后防线.
/// 注意: 这些都是**完整 URL**,  循环时不再拼前缀,  prefix=''.
const List<String> _kVersionMetaUrls = [
  'https://cdn.jsdelivr.net/gh/aqiyoung/sanyelive@meta/version.json',
];

/// FeiNiuMusic 同款请求头 —— GitHub API 必须有 User-Agent, 否则 403.
const Map<String, String> kGitHubApiHeaders = {
  'User-Agent': 'sanyelive',
  'Accept': 'application/vnd.github.v3+json',
};

/// meta 版本源请求头 —— 用通用 Accept, 避免某些代理对 GitHub API 专用 Accept
/// 返回 406/403.
const Map<String, String> kMetaHeaders = {
  'User-Agent': 'sanyelive',
  'Accept': 'application/json',
};

/// 兼容老代码 — 取基础 URL. 单元测试可 overrideWithValue.
const List<String> kDefaultEndpointUrls = [_kGitHubApiBaseUrl];

/// 兼容老代码 — 取基础 URL.
String get kDefaultEndpointUrl => _kGitHubApiBaseUrl;

/// SharedPreferences 持久化.
const String kEndpointPrefsKey = 'version_checker.endpoint_url';

/// 「启动时自动检查更新」开关持久化键 (默认开启).
const String kAutoCheckUpdateKey = 'version_checker.auto_check_update';

/// 兼容旧代码 — get kGitHubReleasesUrl 改成 get endpoint.
@Deprecated('Use endpointProvider instead')
String get kGitHubReleasesUrl => kDefaultEndpointUrl;

/// 当前 APP versionCode —— 由 main.dart 在 ProviderContainer 初始化时
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

/// Cache 有效期 —— 1h 内不再 fetch (避免每启都打 GitHub).
const Duration _kCacheTtl = Duration(hours: 1);

/// 用户点"稍后"后, 24h 内不再弹 (避免 P1 反复骚扰).
const Duration _kDismissTtl = Duration(hours: 24);

/// 强制更新检测结果.
sealed class VersionCheckState {
  const VersionCheckState();
}

/// 还没 check 过, 或上次 check 失败被静默吞掉.
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

  /// P0/critical: release body 含 "**P0**" 或 "**critical**" 标记 → 强制更新,
  /// dialog 不显示"稍后"按钮.
  final bool isCritical;
}

/// 拉版本失败 (网络/parse).  静默, 不骚扰用户.
class VersionCheckFailed extends VersionCheckState {
  const VersionCheckFailed(this.reason);
  final String reason;
}

/// Notifier 主体.  Notifier 是 Riverpod 2.x 推荐写法 (替代 StateNotifier).
class VersionCheckerNotifier extends Notifier<VersionCheckState> {
  late final Dio _dio;
  late final SharedPreferences _prefs;
  bool _checking = false;

  /// 飞牛音乐同款：本会话是否已执行过启动自动检查。
  /// 防止 widget 重建 / provider 刷新导致重复弹窗。
  bool _hasCheckedThisSession = false;

  @override
  VersionCheckState build() {
    _dio = ref.read(dioProvider);
    _prefs = ref.read(sharedPreferencesProvider);
    // 清理旧版残留的自定义更新源 (已停止支持), 防止死链导致检查失败.
    _prefs.remove(kEndpointPrefsKey);
    return const VersionCheckIdle();
  }

  /// 手动检查 —— 设置页"检查更新"按钮调用.
  /// 绕过 1h cache + 24h dismiss, 且**不受**「启动时自动检查更新」开关影响.
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

  /// 启动时调 —— 走 cache 策略 + 异步 fetch, 受「自动检查」开关控制.
  /// 立即返回, 弹 dialog 由 main.dart / settings_page 的 listener 处理.
  ///
  /// 对齐飞牛音乐: 本会话只检查一次; 开关关闭 / cache 命中 / 失败 / 已最新
  /// 都静默, 只有发现新版本 (outdated) 才弹窗.
  Future<void> checkOnStartup() async {
    if (_checking) return;
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;
    _checking = true;
    try {
      // 用户关闭了「启动时自动检查更新」→ 直接跳过 (手动 checkForce 不受影响).
      if (!ref.read(autoCheckUpdateProvider)) return;

      // 1. cache 命中 (< 1h) → 直接跳过 fetch, state 保持 idle
      final lastCheck = _prefs.getInt(_Keys.lastCheckTime);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lastCheck != null && (now - lastCheck) < _kCacheTtl.inMilliseconds) {
        // 启动时 cache 路径不更新 state, 让 UI 不弹窗.
        return;
      }

      await _performCheck();
    } finally {
      _checking = false;
    }
  }

  /// 实际执行一次检查 (fetch + 比较 + 写 state). checkOnStartup / checkForce 共用.
  Future<void> _performCheck() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      // 2. fetch GitHub 最新 release (API 主源 + meta 兜底)
      final parsed = await _fetchLatestRelease();
      if (parsed == null) {
        state = const VersionCheckFailed('无法获取版本信息，请检查网络后重试');
        await _prefs.setInt(_Keys.lastCheckTime, now);
        return;
      }

      final currentStr = ref.read(currentVersionStringProvider);

      // 写 last_seen_version (无论 outdated / upToDate 都写, 方便诊断).
      await _prefs.setString(_Keys.lastSeenVersion, parsed.tagName);

      // 对齐 FeiNiuMusic: 提取 major.minor.patch(+build) 数字段逐位比较.
      // sanyelive 固定 0.3.12 只涨 build, 因此 .N 与 +N 都参与比较,
      // 像 0.3.12.171+2171 这种历史异常包也能正确识别 v0.3.12.172 比它新.
      final cmp = _compareVersions(parsed.tagName, currentStr);
      final isOutdated = cmp > 0;

      if (isOutdated) {
        // 检查是否被用户 dismiss 过 (24h 内同版本不再弹).
        final dismissedVer = _prefs.getString(_Keys.dismissedVersion);
        final dismissedAt = _prefs.getInt(_Keys.dismissedAt);
        if (dismissedVer == parsed.tagName &&
            dismissedAt != null &&
            (now - dismissedAt) < _kDismissTtl.inMilliseconds) {
          // 24h 内 dismiss 过了, 静默不弹.
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
      await CrashLogger.log('version_checker network: $e');
      state = const VersionCheckFailed(
        '网络连接失败，请检查网络或稍后重试\n也可手动前往 GitHub Releases 查看更新',
      );
      // 失败也写 last_check_time, 避免每启都重试刷流量. 下次 1h 后再试.
      await _prefs.setInt(_Keys.lastCheckTime, now);
    } catch (e) {
      debugPrint('version_checker: unexpected error → $e');
      await CrashLogger.log('version_checker error: $e');
      // 把具体错误简短附在提示里, 方便用户截图反馈; 太长截断.
      var detail = e.toString();
      if (detail.length > 120) detail = '${detail.substring(0, 120)}…';
      state = VersionCheckFailed(
        '检查更新时出错，请稍后重试\n也可手动前往 GitHub Releases 查看更新\n($detail)',
      );
      await _prefs.setInt(_Keys.lastCheckTime, now);
    }
  }

  /// 用户点"稍后" —— 记录 dismissed_version + dismissed_at, 24h 不再弹.
  /// P0/critical 时调用方 (dialog) 不暴露这个按钮.
  Future<void> markDismissed() async {
    final s = state;
    if (s is! VersionCheckOutdated) return;
    await _prefs.setString(_Keys.dismissedVersion, s.latestVersion);
    await _prefs.setInt(
      _Keys.dismissedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    // 弹完后 state 回到 idle, 不让 main.dart 的 listener 二次弹.
    state = const VersionCheckIdle();
  }

  /// 强制重置 cache (测试 / 用户手动"重新检查"用).
  Future<void> resetCache() async {
    await _prefs.remove(_Keys.lastCheckTime);
    await _prefs.remove(_Keys.lastSeenVersion);
    await _prefs.remove(_Keys.dismissedVersion);
    await _prefs.remove(_Keys.dismissedAt);
  }

  /// @visibleForTesting —— 跳开 fetch, 直接在 state 设 outdated/upToDate.
  /// Riverpod 的 Notifier.state setter 是 @protected, 不能从外面调,
  /// 这里包一层.  测试用, 生产代码不要调.
  @visibleForTesting
  void debugSetState(VersionCheckState newState) {
    state = newState;
  }

  // -------- private: 网络 --------

  /// 拉最新版本信息.
  /// 策略 (对齐 FeiNiuMusic):
  ///   1) GitHub API `releases/latest` 为主源 (权威, 发版即更新, 永不过期),
  ///      经代理前缀链穿透 GFW; 任一代理成功即用.
  ///   2) jsDelivr 上的 meta/version.json 为兜底 (国内 CDN, 通常可用,
  ///      仅在 API 全失败时启用, 可能滞后一个版本).
  /// 返回 (_ParsedRelease) 或 null (全部失败).
  Future<_ParsedRelease?> _fetchLatestRelease() async {
    // 1) GitHub API (经代理链) —— 权威主源
    for (final prefix in _kApiProxyPrefixes) {
      final url =
          prefix.isEmpty ? _kGitHubApiBaseUrl : '$prefix$_kGitHubApiBaseUrl';
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
          final data = _decodeJson(resp.data);
          if (data != null) {
            final parsed = _parseRelease(data, prefix);
            if (parsed != null) return parsed;
          }
        }
      } on DioException catch (e) {
        debugPrint('version_checker: api $url → $e');
      } catch (e) {
        debugPrint('version_checker: api $url → $e');
      }
    }

    // 2) jsDelivr meta 兜底 (国内 CDN)
    for (final url in _kVersionMetaUrls) {
      try {
        final resp = await _dio.get<dynamic>(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 10),
            responseType: ResponseType.plain,
            headers: kMetaHeaders,
          ),
        );
        if (resp.statusCode == 200) {
          final data = _decodeJson(resp.data);
          if (data is Map<String, dynamic> &&
              data.containsKey('tag') &&
              data.containsKey('versionCode')) {
            final parsed = _parseMeta(data, '');
            if (parsed != null) return parsed;
          }
        }
      } on DioException catch (e) {
        debugPrint('version_checker: meta $url → $e');
      } catch (e) {
        debugPrint('version_checker: meta $url → $e');
      }
    }
    return null;
  }

  /// 把 Dio 返回的 data (String / Map) 解析成 Map; 拿到 HTML 或非法 JSON 返回 null.
  static Map<String, dynamic>? _decodeJson(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      final s = data.trim();
      // 拿到 HTML (代理没干活 / 404 页) 直接返回 null.
      if (s.startsWith('<')) return null;
      try {
        final decoded = jsonDecode(s);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static _ParsedRelease? _parseRelease(dynamic json, String proxyPrefix) {
    Map<String, dynamic>? release;
    if (json is Map<String, dynamic>) {
      release = json;
    } else if (json is List<dynamic> && json.isNotEmpty) {
      // 兜底: 个别代理把单对象包成列表, 取首个 Map.
      for (final e in json) {
        if (e is Map<String, dynamic>) {
          release = e;
          break;
        }
      }
    }
    if (release == null) return null;

    final tagName = release['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) return null;

    final assets = release['assets'] as List<dynamic>?;
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

    final body = (release['body'] as String?) ?? '';
    final releaseName = (release['name'] as String?)?.trim() ?? tagName;
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

  /// 按来源格式分流解析: meta 版本源 (含 versionCode/tag) 走 _parseMeta,
  /// 其余 (GitHub API 格式, 含 assets/tag_name) 走 _parseRelease.
  static _ParsedRelease? _parseAny(
    Map<String, dynamic> json,
    String proxyPrefix,
  ) {
    if (json.containsKey('versionCode') && json.containsKey('tag')) {
      return _parseMeta(json, proxyPrefix);
    }
    return _parseRelease(json, proxyPrefix);
  }

  /// 解析 meta 版本源 (version.json) 格式.
  static _ParsedRelease? _parseMeta(
    Map<String, dynamic> json,
    String proxyPrefix,
  ) {
    final tag = json['tag'] as String?;
    if (tag == null || tag.isEmpty) return null;
    final code = json['versionCode'];
    if (code is! int) return null;

    // apk 下载链接: 优先 arm64-v8a, 其次 armeabi-v7a / x86_64.
    final apks = json['apk'];
    String? apkUrl;
    String? apkName;
    if (apks is Map) {
      final cand = <dynamic>[
        apks['arm64-v8a'],
        apks['armeabi-v7a'],
        apks['x86_64'],
      ];
      for (final c in cand) {
        if (c is String && c.isNotEmpty) {
          apkUrl = (proxyPrefix.isNotEmpty) ? '$proxyPrefix$c' : c;
          apkName = c.split('/').last;
          break;
        }
      }
    }
    if (apkUrl == null || apkName == null) return null;

    final releaseName = (json['releaseName'] as String?)?.trim() ?? tag;
    final notes = (json['notes'] as String?) ?? '';
    final critical = json['critical'] == true;

    return _ParsedRelease(
      tagName: tag,
      releaseName: releaseName,
      versionCode: code,
      apkAssetName: apkName,
      apkDownloadUrl: apkUrl,
      releaseNotes: notes,
      isCritical: critical,
    );
  }

  /// 版本号比较. 返 1 = a > b, 0 = a == b, -1 = a < b.
  ///
  /// 对齐 FeiNiuMusic 思路: 提取版本字符串中所有连续数字段, 逐位比较.
  /// 与 FeiNiuMusic 一致, 比较前会:
  ///   - 去掉前导 v / V (tag 形如 v0.3.12.174)
  ///   - 在首个 + 或 - 处截断 (忽略 build / prerelease 后缀)
  /// 这样 0.3.12.171+2171 这种历史异常包会被规整成 0.3.12.171 再比较,
  /// 不会因多出的 build 段误判.
  ///
  /// 示例:
  ///   v0.3.12.174      → [0, 3, 12, 174]
  ///   0.3.12.173        → [0, 3, 12, 173]
  ///   0.3.12.173+2173   → [0, 3, 12, 173]  (截断 + 后)
  ///
  /// 位数不够补 0.
  static int _compareVersions(String a, String b) {
    List<int> release(String v) {
      var s = _normalizeVersion(v);
      final cut = s.indexOf(RegExp(r'[+\-]'));
      if (cut >= 0) s = s.substring(0, cut);
      return s
          .split('.')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .toList();
    }

    final left = release(a);
    final right = release(b);
    final len = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < len; i++) {
      final av = i < left.length ? left[i] : 0;
      final bv = i < right.length ? right[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static String _normalizeVersion(String version) {
    final value = version.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      return value.substring(1);
    }
    return value;
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
  // 测试不依赖 Dio, 直接验证 parse 逻辑.  private static → 改写成 public 静态
  // 包装, 保持 production 调用路径不变.

  @visibleForTesting
  static int? debugExtractVersionCode(String apkName) =>
      _extractVersionCode(apkName);

  @visibleForTesting
  static bool debugIsCriticalRelease(String body) => _isCriticalRelease(body);

  @visibleForTesting
  static int debugCompareVersions(String a, String b) => _compareVersions(a, b);

  @visibleForTesting
  static Map<String, dynamic>? debugParseRelease(
    Map<String, dynamic> json, {
    String proxyPrefix = '',
  }) {
    // 走 _parseAny, 同时覆盖 meta 版本源 与 GitHub API 两种格式.
    final parsed = _parseAny(json, proxyPrefix);
    if (parsed == null) return null;
    return _parsedToMap(parsed);
  }

  /// 把 _ParsedRelease 转成 Map, 供测试断言.
  static Map<String, dynamic> _parsedToMap(_ParsedRelease r) => {
        'tagName': r.tagName,
        'releaseName': r.releaseName,
        'versionCode': r.versionCode,
        'apkAssetName': r.apkAssetName,
        'apkDownloadUrl': r.apkDownloadUrl,
        'releaseNotes': r.releaseNotes,
        'isCritical': r.isCritical,
      };
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

/// Dio provider —— 默认 new Dio() (生产).  测试可 overrideWithValue 注入 mock.
/// 用了 ref.read 创建, 避免 Notifier.build() 多次跑时重建 Dio.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// 「启动时自动检查更新」开关 —— 默认关闭.
/// 关闭后 checkOnStartup() 直接 return (不 fetch); 手动 checkForce() 不受影响.
class AutoCheckUpdateNotifier extends Notifier<bool> {
  late final SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _prefs.getBool(kAutoCheckUpdateKey) ?? false;
  }

  Future<void> set(bool value) async {
    await _prefs.setBool(kAutoCheckUpdateKey, value);
    state = value;
  }
}

final autoCheckUpdateProvider =
    NotifierProvider<AutoCheckUpdateNotifier, bool>(AutoCheckUpdateNotifier.new);
