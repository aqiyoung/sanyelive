//
// 职责:
//   - 启动时 / 手动检查更新: 拉取 GitHub 最新 release, 解析版本号,
//     与当前安装版本比较, 判断是否 outdated.
//   - 命中 outdated → 由 main.dart / settings_page 的 listener 弹更新弹窗.
//
// ─────────────────────────────────────────────────────────────────────────
// v0.3.12.175 重构 (对齐 FeiNiuMusic 已验证可用实现):
//
// 1) 数据源顺序 —— 以 GitHub API `releases/latest` 为权威主源,
//    jsDelivr 上的 meta/version.json 仅作兜底.
//    GitHub API 在发版瞬间原子更新, 永不过期, 与 FeiNiuMusic 完全一致.
//
// 2) 比较逻辑对齐 FeiNiuMusic:
//    - 当前版本只取 PackageInfo.version (干净的 versionName, 如 "0.3.12.173"),
//      不再自作主张拼上 +versionCode (那会多出一个第 5 段数字, 造成误判).
//    - 远端 tag (如 "v0.3.12.174") 去掉前导 v, 在首个 + / - 处截断,
//      按 "." 切出数字段逐位比较.  major.minor.patch 比完再比 build.
//
// 3) 网络策略 (v0.3.12.184 修正, 参考 synapse 的"多路径可达"思路):
//    - 每个数据源 (GitHub API / jsDelivr meta) 都依次尝试
//      [gh-proxy.com 代理] → [直连] 两层, 任一成功即用.
//      gh-proxy.com 优先: 国内 / 移动宽带直连 api.github.com 会被墙,
//      经代理是这些用户唯一可达的路径 (release.yml 下载也用同款代理).
//      直连兜底: 覆盖 VPN / 海外 / 代理被局部封锁的用户.
//    - 任一层返回非 200 / 非 JSON (如代理偶发 403 HTML) 都静默跳过,
//      试下一层 —— 不会因"代理偶尔抽风"而整体失败. 这正是 v0.3.12.182
//      误删代理链、改成纯直连后, 移动宽带用户检查更新全军覆没的根因.
//    - Dio 仍用"干净" HttpClient, 绕过 main.dart 的 Ipv4HttpOverrides,
//      恢复系统默认 happy-eyeballs 行为 (与 FeiNiuMusic 一致).
//    - 每层都带 User-Agent + Accept 头 —— 缺 User-Agent 时 GitHub API 直接 403.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/features/settings/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:sanyelive/utils/crash_logger.dart';
import 'package:sanyelive/services/app_update_core.dart';

/// 统一更新引擎实例 —— 检测与跳转均委托给它 (sanyelive / FeiNiuMusic / synapse 共用).
/// 公开: force_update_dialog / settings 页直接复用同一实例做「跳转发布页」,
/// 保证三端行为一致 (GitHub App 优先 → 浏览器 → 复制链接).
const AppUpdateConfig kUpdateConfig = AppUpdateConfig(
  owner: 'aqiyoung',
  repo: 'sanyelive',
);
final AppUpdateCore appUpdateCore = AppUpdateCore(kUpdateConfig);

/// 把 sanyelive 的 Dio 适配成引擎需要的取数函数 (引擎本身不绑定 dio / http).
/// validateStatus 全放行 —— 非 200 交给引擎判定, 由它自行切换下一条路径.
AppUpdateFetch dioUpdateFetch(Dio dio) => (url, headers) async {
      final resp = await dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
          headers: headers,
          validateStatus: (_) => true,
        ),
      );
      return AppUpdateHttpResponse(
        resp.statusCode ?? 0,
        resp.data?.toString() ?? '',
      );
    };

/// SharedPreferences 持久化.
const String kEndpointPrefsKey = 'version_checker.endpoint_url';

/// 「启动时自动检查更新」开关持久化键 (默认开启).
const String kAutoCheckUpdateKey = 'version_checker.auto_check_update';

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
      final cmp = AppUpdateCore.compareVersions(parsed.tagName, currentStr);
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

  /// 拉最新版本信息 —— 全部委托统一更新引擎 [appUpdateCore]
  /// (lib/services/app_update_core.dart, sanyelive / FeiNiuMusic / synapse 共用).
  ///
  /// 引擎策略: 每个数据源 (GitHub API → jsDelivr meta) 都依次尝试
  /// [gh-proxy.com 代理] → [直连] 两条路径, 任一成功即用; 非 200 / 非 JSON
  /// (代理偶发 403 HTML) 静默跳过试下一层. 这正是 v0.3.12.182 误删代理链、
  /// 改成纯直连后, 移动宽带用户检查更新全军覆没的根因.
  /// 比较只依赖 tag_name vs PackageInfo.version, 不依赖 APK 文件名格式.
  ///
  /// 返回 (_ParsedRelease) 或 null (全部数据源失败).
  Future<_ParsedRelease?> _fetchLatestRelease() async {
    final current = ref.read(currentVersionStringProvider);
    final result = await appUpdateCore.check(dioUpdateFetch(_dio), current);
    if (result == null) return null;
    return _ParsedRelease(
      tagName: result.tagName,
      releaseName: result.releaseName,
      versionCode: result.versionCode,
      apkAssetName: result.apkAssetName ?? '',
      apkDownloadUrl: result.apkDownloadUrl ?? '',
      releaseNotes: result.releaseNotes ?? '',
      isCritical: result.isCritical,
    );
  }

  // 解析 / 版本比较 / critical 判定已全部下沉到 app_update_core.dart
  // (sanyelive / FeiNiuMusic / synapse 共用的唯一实现).
  // 相关单测直接针对 AppUpdateCore 编写, 这里不再保留重复的 debug 包装.
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

/// Dio provider —— 用于更新检查.
///
/// 关键：使用干净的 HttpClient，临时绕过 main.dart 安装的 [Ipv4HttpOverrides]，
/// 恢复系统默认的 happy-eyeballs DNS + 连接策略。FeiNiuMusic 的更新服务
/// 正是依赖这种默认行为才在用户手机上正常工作；sanyelive 之前复用全局
/// Ipv4HttpOverrides，其自定义 connectionFactory 在部分网络（尤其移动数据）
/// 下连不上 GitHub API，导致检查更新反复失败。
///
/// 测试可 overrideWithValue 注入 mock，mock 会替换掉这里的 adapter。
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final prev = HttpOverrides.current;
      HttpOverrides.global = null;
      try {
        return HttpClient();
      } finally {
        HttpOverrides.global = prev;
      }
    },
  );
  ref.onDispose(dio.close);
  return dio;
});

/// 「启动时自动检查更新」开关 —— 默认开启 (对齐 synapse: 启动即检查,
/// 仅发现新版本才弹窗, 不强制). 关闭后 checkOnStartup() 直接 return (不 fetch);
/// 手动 checkForce() 不受影响.
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
