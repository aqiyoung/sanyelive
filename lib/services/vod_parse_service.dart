import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

///
/// TVBox 解析引擎 (轻量版).
///
/// TVBox 配置顶层 `parses[]` 定义一组"解析规则", 用于把影视源返回的
/// 加密/重定向播放地址还原成可直接播放的 m3u8/mp4 直链. sites[].parse
/// 引用其中一条规则的 name.
///
/// 解析类型 (TVBox 规范):
///   - type 1: API 解析 — GET/POST `url`+`?url=<encoded>` 返回 JSON, 取
///     `.url` / `.playUrl` / `.parseURL` 字段.
///   - type 4: JSON 解析 — 同上 (部分配置命名为 json).
///   - type 2 / 3: JS spider 解析 — 需在设备内跑 JS (flutter_js),
///     本轻量版暂不支持, 抛出 [UnsupportedError] 标注规划 P2.
///
/// 设计: 规则全局存于 [VodParseRegistry] (按 name 查), 由 TVBox 导入时填充.
/// 播放前若源带 parseKey, 经 [VodParseService.resolve] 解析; 无规则则直连.
/// 全程 http (无原生依赖), 兼容 arm64 CI 构建.

/// 单条 TVBox 解析规则.
class TvBoxParseRule {
  const TvBoxParseRule({
    required this.name,
    required this.type,
    required this.url,
  });

  /// 规则名 (sites[].parse 引用它).
  final String name;

  /// 解析类型 (1/4 = api/json, 2/3 = js spider).
  final int type;

  /// 解析接口地址 (type 1/4: 拼 `?url=<encoded>`).
  final String url;

  static TvBoxParseRule? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final name = (j['name'] as String?)?.trim();
    final url = (j['url'] as String?)?.trim();
    final type = j['type'] is int
        ? j['type'] as int
        : (j['type'] as num?)?.toInt() ?? 1;
    if (name == null || name.isEmpty || url == null || url.isEmpty) {
      return null;
    }
    return TvBoxParseRule(name: name, type: type, url: url);
  }
}

/// 解析规则注册器 — 按 name 索引, TVBox 导入时填充.
class VodParseRegistry extends ChangeNotifier {
  final Map<String, TvBoxParseRule> _rules = {};

  /// 所有规则 (只读).
  List<TvBoxParseRule> get all => _rules.values.toList();

  /// 按 name 查规则.
  TvBoxParseRule? byName(String? name) {
    if (name == null || name.isEmpty) return null;
    return _rules[name];
  }

  /// 批量添加 (TVBox 导入). 同名覆盖.
  void addAll(List<TvBoxParseRule> rules) {
    var changed = false;
    for (final r in rules) {
      if (!_rules.containsKey(r.name) ||
          _rules[r.name]!.url != r.url ||
          _rules[r.name]!.type != r.type) {
        _rules[r.name] = r;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// 清空 (测试/重置).
  void clear() {
    if (_rules.isNotEmpty) {
      _rules.clear();
      notifyListeners();
    }
  }
}

/// VodParseRegistry Riverpod provider — 单例 (app 生命周期共享).
final vodParseRegistryProvider = ChangeNotifierProvider<VodParseRegistry>(
  (ref) => VodParseRegistry(),
);

/// VodParseService Riverpod provider — 单例 (app 生命周期共享).
final vodParseServiceProvider = Provider<VodParseService>(
  (ref) => VodParseService(),
);

/// 播放地址解析服务 — 把 (可能加密的) 播放地址还原成直链.
class VodParseService {
  VodParseService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// 解析 [playUrl].
  /// - [rule] 为 null → 直连, 直接返回 [playUrl].
  /// - rule.type 为 1/4 → http 解析, 返回直链.
  /// - rule.type 为 2/3 (JS spider) → 抛 [UnsupportedError] (需 flutter_js, P2).
  ///
  /// 任何解析失败 → 回退返回原始 [playUrl] (best-effort, 不阻断播放).
  Future<String> resolve(String playUrl, {TvBoxParseRule? rule}) async {
    if (rule == null) return playUrl;
    if (rule.type == 2 || rule.type == 3) {
      throw UnsupportedError(
        'JS spider 解析 (type ${rule.type}) 需 flutter_js 引擎, 规划 P2',
      );
    }
    // type 1 / 4: API/JSON 解析.
    try {
      final target =
          Uri.parse(rule.url).replace(queryParameters: {
        'url': playUrl,
      });
      final resp = await _client
          .get(target)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return playUrl;
      final decoded = json.decode(resp.body);
      final url = _extractUrl(decoded);
      if (url != null && url.isNotEmpty) return url;
      return playUrl;
    } catch (_) {
      // 解析异常 → 回退原始地址.
      return playUrl;
    }
  }

  /// 从解析响应 (Map/List) 提取直链. 兼容常见字段名.
  String? _extractUrl(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      for (final key in const ['url', 'playUrl', 'parseURL', 'play_url']) {
        final v = decoded[key];
        if (v is String && v.isNotEmpty) return v;
      }
      // 部分响应嵌在 data 里.
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        for (final key in const ['url', 'playUrl', 'parseURL']) {
          final v = data[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
      // 部分响应是列表.
      final list = decoded['list'] ?? decoded['data'];
      if (list is List && list.isNotEmpty) {
        final first = list.first;
        if (first is Map<String, dynamic>) {
          for (final key in const ['url', 'playUrl', 'parseURL']) {
            final v = first[key];
            if (v is String && v.isNotEmpty) return v;
          }
        }
      }
    } else if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map<String, dynamic>) {
        for (final key in const ['url', 'playUrl', 'parseURL']) {
          final v = first[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    }
    return null;
  }

  void dispose() => _client.close();
}
