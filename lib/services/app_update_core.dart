//
// 统一更新检查引擎 —— sanyelive / FeiNiuMusic / synapse 共用.
//
// 本文件在三个仓库里保持【逐字一致】, 改动请三处同步 (它不依赖任何仓库特有的
// 类型: 不绑定 dio / http, 不绑定 Riverpod / Provider, 只依赖 Flutter 本体
// 和 url_launcher).
//   - sanyelive : lib/services/app_update_core.dart
//   - FeiNiuMusic: lib/app/services/app_update_core.dart
//   - synapse   : app/lib/services/app_update_core.dart
//
// 整合三仓库各自的优点:
//  1) 多路径可达 (来自 sanyelive 的教训): GitHub API 依次尝试
//     [gh-proxy.com 代理] → [直连]. 国内 / 移动宽带直连 api.github.com 会被墙,
//     代理是这些用户唯一可达的路径; 直连兜底覆盖 VPN / 海外. 任一层 403 /
//     超时 / 拿到 HTML 都静默跳过试下一层, 不会因代理偶尔抽风而整体失败.
//  2) jsDelivr meta/version.json 兜底 (最后防线, 国内 CDN, 可选).
//  3) 只比 tag_name vs PackageInfo.version, 不依赖 APK 文件名格式
//     (来自 synapse): 发版中途 / 资产命名变化都不会导致漏检.
//  4) 跳转发布页 (来自 FeiNiuMusic): 优先 GitHub App
//     (externalNonBrowserApplication, 靠 App Link 路由进已安装的 GitHub App),
//     未装 App 自动回退系统浏览器, 再失败复制链接到剪贴板.
//  5) P0/critical 强制更新: release 正文首非空行含 "**P0**" / "**critical**".
//
// 用法:
//   final core = AppUpdateCore(AppUpdateConfig(owner: 'aqiyoung', repo: 'xxx'));
//   final result = await core.check(fetch, currentVersion);
//   if (result?.hasUpdate ?? false) {
//     await core.openRelease(context, result!.releaseUrl);
//   }
// 其中 fetch 是各仓库自己的 HTTP 适配器 (见 [AppUpdateFetch]):
//   - sanyelive / FeiNiuMusic 用 dio, synapse 用 package:http, 各写 ~10 行.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

/// HTTP 响应的最小抽象 —— 让引擎不绑定 dio / http 任何一家.
class AppUpdateHttpResponse {
  const AppUpdateHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// HTTP 取数适配器. 各仓库用自己的 client 实现一个即可.
///
/// 约定:
///   - 只需返回状态码 + 原始 body 文本, 解析交给引擎.
///   - 网络异常直接 throw, 引擎会捕获并继续尝试下一条路径.
typedef AppUpdateFetch = Future<AppUpdateHttpResponse> Function(
  String url,
  Map<String, String> headers,
);

/// 仓库配置. 三个项目各传自己的 owner/repo 即可共用本引擎.
class AppUpdateConfig {
  const AppUpdateConfig({
    required this.owner,
    required this.repo,
    this.proxyPrefixes = const ['https://gh-proxy.com/', ''],
    this.useMetaFallback = true,
    this.metaBranch = 'meta',
  });

  final String owner;
  final String repo;

  /// 代理前缀链: gh-proxy.com 优先, 空串 = 直连兜底.
  final List<String> proxyPrefixes;

  /// 是否用 jsDelivr meta/version.json 作最后兜底 (仓库需有 meta 分支).
  final bool useMetaFallback;

  /// meta 分支名 (发版 workflow 每次刷新它).
  final String metaBranch;

  String get apiLatestUrl =>
      'https://api.github.com/repos/$owner/$repo/releases/latest';
  String get apiListUrl =>
      'https://api.github.com/repos/$owner/$repo/releases';
  String get metaUrl =>
      'https://cdn.jsdelivr.net/gh/$owner/$repo@$metaBranch/version.json';
  String get releasePageUrl =>
      'https://github.com/$owner/$repo/releases/latest';
  String releaseTagUrl(String tag) =>
      'https://github.com/$owner/$repo/releases/tag/$tag';
}

/// openRelease 的结果, 供调用方决定是否提示"已复制链接".
enum OpenReleaseResult { openedApp, openedBrowser, copied }

/// 检查结果.
class AppUpdateResult {
  const AppUpdateResult({
    required this.tagName,
    required this.latestVersion,
    required this.releaseUrl,
    required this.hasUpdate,
    this.releaseName = '',
    this.releaseNotes,
    this.isCritical = false,
    this.source = 'github',
    this.versionCode = 0,
    this.apkAssetName,
    this.apkDownloadUrl,
  });

  /// 远端 tag, 如 "v0.3.12.184".
  final String tagName;

  /// 去掉前导 v 的版本串, 如 "0.3.12.184".
  final String latestVersion;

  /// 该版本的 GitHub Release 页面地址 (跳转用).
  final String releaseUrl;

  /// 远端是否比本地新.
  final bool hasUpdate;

  /// Release 标题 (json['name']); 缺省回落 tag.
  final String releaseName;

  /// Release 正文 (变更日志).
  final String? releaseNotes;

  /// P0/critical → 调用方应强制升级 (不显示"稍后").
  final bool isCritical;

  /// 'github' | 'meta' —— 命中的数据源, 便于诊断.
  final String source;

  /// 从 tag 末段推导的数字, 仅作展示 / 诊断, 不参与比较.
  final int versionCode;

  final String? apkAssetName;
  final String? apkDownloadUrl;
}

class AppUpdateCore {
  AppUpdateCore(this.config);
  final AppUpdateConfig config;

  static const Map<String, String> _apiHeaders = {
    // 缺 User-Agent 时 GitHub API 直接 403.
    'User-Agent': 'app-update-core',
    'Accept': 'application/vnd.github.v3+json',
  };
  static const Map<String, String> _metaHeaders = {
    'User-Agent': 'app-update-core',
    'Accept': 'application/json',
  };

  /// 检查更新. 返回 null = 所有数据源都失败 (调用方应提示"网络不可达", 不要
  /// 误报"已是最新").
  ///
  /// [channel] 'stable' (默认) 或 'beta'; beta 走 /releases 列表取首个 prerelease.
  Future<AppUpdateResult?> check(
    AppUpdateFetch fetch,
    String currentVersion, {
    String channel = 'stable',
  }) async {
    final failures = <String>[];
    final isBeta = channel == 'beta';

    // ── 1) GitHub API: 代理链 (gh-proxy 优先, 直连兜底) ──
    final base = isBeta ? config.apiListUrl : config.apiLatestUrl;
    for (final prefix in config.proxyPrefixes) {
      final url = prefix.isEmpty ? base : '$prefix$base';
      try {
        final resp = await fetch(url, _apiHeaders);
        if (resp.statusCode != 200) {
          failures.add('api $url → HTTP ${resp.statusCode}');
          continue;
        }
        final data = _decode(resp.body);
        if (isBeta && data is List) {
          for (final e in data) {
            if (e is Map<String, dynamic> && e['prerelease'] == true) {
              final parsed = _parseRelease(e);
              if (parsed != null) {
                return _toResult(parsed, currentVersion, 'github', channel);
              }
              break;
            }
          }
          failures.add('api $url → 无 prerelease');
        } else if (data is Map<String, dynamic>) {
          final parsed = _parseRelease(data);
          if (parsed != null) {
            return _toResult(parsed, currentVersion, 'github', channel);
          }
          failures.add('api $url → 解析失败 (无 tag_name)');
        } else {
          // 代理没干活 / 返回 HTML 错误页.
          failures.add('api $url → 非 JSON');
        }
      } catch (e) {
        failures.add('api $url → $e');
      }
    }

    // ── 2) jsDelivr meta 兜底 (国内 CDN, 仅 stable) ──
    if (config.useMetaFallback && !isBeta) {
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      for (final prefix in config.proxyPrefixes) {
        final url = '$prefix${config.metaUrl}?_t=$cacheBuster';
        try {
          final resp = await fetch(url, _metaHeaders);
          if (resp.statusCode != 200) {
            failures.add('meta $url → HTTP ${resp.statusCode}');
            continue;
          }
          final data = _decode(resp.body);
          if (data is Map<String, dynamic> &&
              data.containsKey('tag') &&
              data.containsKey('versionCode')) {
            final parsed = _parseMeta(data);
            if (parsed != null) {
              return _toResult(parsed, currentVersion, 'meta', channel);
            }
          }
          failures.add('meta $url → 解析失败');
        } catch (e) {
          failures.add('meta $url → $e');
        }
      }
    }

    debugPrint('app_update_core: 全部数据源失败\n${failures.join('\n')}');
    return null;
  }

  AppUpdateResult _toResult(
    _Parsed p,
    String currentVersion,
    String source,
    String channel,
  ) {
    final newer = compareVersions(p.tagName, currentVersion) > 0;
    // 通道保护: beta 用户不被 stable 拉回, stable 用户不被 prerelease 骚扰.
    final crossChannel = (channel == 'beta' && !p.isPrerelease) ||
        (channel != 'beta' && p.isPrerelease && !newer);
    return AppUpdateResult(
      tagName: p.tagName,
      latestVersion: p.latestVersion,
      releaseName: p.releaseName,
      releaseUrl: config.releaseTagUrl(p.tagName),
      releaseNotes: p.notes,
      isCritical: p.isCritical,
      hasUpdate: newer && !crossChannel,
      source: source,
      versionCode: p.versionCode,
      apkAssetName: p.apkAssetName,
      apkDownloadUrl: p.apkDownloadUrl,
    );
  }

  /// 跳转发布页: GitHub App 优先 → 系统浏览器 → 复制链接.
  /// 返回结果供调用方决定是否提示"已复制".
  Future<OpenReleaseResult> openRelease(
    BuildContext context,
    String releaseUrl,
  ) async {
    final uri = Uri.parse(releaseUrl);
    // externalNonBrowserApplication 让系统优先把 github.com 链接交给已安装的
    // GitHub App (Android App Link / iOS Universal Link); 未安装时返回 false.
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      )) {
        return OpenReleaseResult.openedApp;
      }
    } catch (_) {
      // 未安装 GitHub App 时部分 ROM 直接抛 PlatformException, 继续回退.
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return OpenReleaseResult.openedBrowser;
      }
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: releaseUrl));
    return OpenReleaseResult.copied;
  }

  /// 用 gh-proxy 包裹 GitHub 链接, 给直连打不开的用户兜底.
  String proxyUrl(String url) => 'https://gh-proxy.com/$url';

  // ────────────────────────────────────────────────────────────
  // 纯函数 (版本比较 / 解析) —— 三仓库一致, 单测直接覆盖
  // ────────────────────────────────────────────────────────────

  /// 版本比较. >0 = a 比 b 新, 0 = 相同, <0 = a 更旧.
  ///
  /// 规则: 去前导 v/V → 在首个 `+` / `-` 处截断 (忽略 build / prerelease 后缀)
  /// → 按 "." 切成数字段逐位比较, 位数不足补 0.
  ///   v0.3.12.174 vs 0.3.12.173      → 1
  ///   0.3.12.173+2173 vs 0.3.12.173  → 0
  static int compareVersions(String a, String b) {
    List<int> release(String v) {
      var s = _normalizeVersion(v);
      final cut = s.indexOf(RegExp(r'[+\-]'));
      if (cut >= 0) s = s.substring(0, cut);
      return s.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
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

  /// release 正文首非空行含 "**P0**" / "**critical**" (大小写不敏感) → 重要更新,
  /// 调用方应强制升级 (不显示"稍后").
  static bool isCritical(String body) {
    final firstLine = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final lower = firstLine.toLowerCase();
    return lower.contains('**p0**') || lower.contains('**critical**');
  }

  /// @visibleForTesting —— 解析 GitHub release JSON 或 meta version.json,
  /// 返回扁平 Map 供断言; 无法解析 (缺 tag) 时返回 null.
  @visibleForTesting
  static Map<String, dynamic>? debugParse(Map<String, dynamic> json) {
    final p = (json.containsKey('tag') && json.containsKey('versionCode'))
        ? _parseMeta(json)
        : _parseRelease(json);
    if (p == null) return null;
    return <String, dynamic>{
      'tagName': p.tagName,
      'latestVersion': p.latestVersion,
      'releaseName': p.releaseName,
      'versionCode': p.versionCode,
      'apkAssetName': p.apkAssetName,
      'apkDownloadUrl': p.apkDownloadUrl,
      'releaseNotes': p.notes,
      'isCritical': p.isCritical,
      'isPrerelease': p.isPrerelease,
    };
  }

  /// 把 body 文本解析成 JSON (Map 或 List); 拿到 HTML / 非法 JSON 返回 null.
  static dynamic _decode(String body) {
    final s = body.trim();
    if (s.isEmpty || s.startsWith('<')) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static _Parsed? _parseRelease(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String?)?.trim();
    if (tagName == null || tagName.isEmpty) return null;

    String? apkName;
    String? apkUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map<String, dynamic>) continue;
        final name = (a['name'] as String?) ?? '';
        if (!name.endsWith('.apk')) continue;
        // arm64-v8a 优先, 否则取第一个 apk.
        if (name.contains('arm64-v8a') || apkName == null) {
          apkName = name;
          apkUrl = a['browser_download_url'] as String?;
          if (name.contains('arm64-v8a')) break;
        }
      }
    }

    final body = (json['body'] as String?) ?? '';
    final name = (json['name'] as String?)?.trim();
    return _Parsed(
      tagName: tagName,
      latestVersion: _stripV(tagName),
      releaseName: (name == null || name.isEmpty) ? tagName : name,
      notes: body,
      isCritical: isCritical(body),
      isPrerelease: json['prerelease'] == true,
      versionCode: _versionCodeFromTag(tagName),
      apkAssetName: apkName,
      apkDownloadUrl: apkUrl,
    );
  }

  static _Parsed? _parseMeta(Map<String, dynamic> json) {
    final tag = (json['tag'] as String?)?.trim();
    if (tag == null || tag.isEmpty) return null;
    final code = json['versionCode'];
    if (code is! int) return null;

    String? apkUrl;
    String? apkName;
    final apks = json['apk'];
    if (apks is Map) {
      for (final c in [apks['arm64-v8a'], apks['armeabi-v7a'], apks['x86_64']]) {
        if (c is String && c.isNotEmpty) {
          apkUrl = c;
          apkName = c.split('/').last;
          break;
        }
      }
    }

    final body = (json['notes'] as String?) ?? '';
    final name = (json['releaseName'] as String?)?.trim();
    return _Parsed(
      tagName: tag,
      latestVersion: _stripV(tag),
      releaseName: (name == null || name.isEmpty) ? tag : name,
      notes: body,
      isCritical: json['critical'] == true || isCritical(body),
      isPrerelease: false,
      versionCode: code,
      apkAssetName: apkName,
      apkDownloadUrl: apkUrl,
    );
  }

  static String _normalizeVersion(String version) {
    final value = version.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      return value.substring(1);
    }
    return value;
  }

  static String _stripV(String tag) => _normalizeVersion(tag);

  /// 从 tag (如 "v0.3.12.184") 取末段数字作为 versionCode; 仅供展示 / 诊断.
  static int _versionCodeFromTag(String tag) {
    final segs = _normalizeVersion(tag).split('.');
    for (var i = segs.length - 1; i >= 0; i--) {
      final n = int.tryParse(segs[i].trim());
      if (n != null) return n;
    }
    return 0;
  }
}

class _Parsed {
  _Parsed({
    required this.tagName,
    required this.latestVersion,
    required this.releaseName,
    required this.notes,
    required this.isCritical,
    required this.isPrerelease,
    required this.versionCode,
    this.apkAssetName,
    this.apkDownloadUrl,
  });
  final String tagName;
  final String latestVersion;
  final String releaseName;
  final String? notes;
  final bool isCritical;
  final bool isPrerelease;
  final int versionCode;
  final String? apkAssetName;
  final String? apkDownloadUrl;
}
