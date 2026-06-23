/// v0.3.10.8 (6/23 老板拍): 远程视频源数据源.
///
/// 数据源: aqiyoung/iptv-channels-organized repo (每天 cron 自动生成).
/// JSON schema:
///   sources/known.json → { _meta: { generated_at, count, ... }, channels: [{ channel_id, urls: [...] }] }
///   sources/dead.json  → { _meta: { generated_at, count, ... }, channels: [{ channel_id, url, ... }] }
///
/// 失败策略: 拉不到 / 超时 / 解析错 → 抛 RemoteSourcesException,
/// caller (channel_repository) fallback 本地 assets/data/known_sources.json.
///
/// 设计: 跟 RemoteChannelsSource 同模板 (Provider + AsyncNotifier),
/// 保持 codebase 风格一致. 单一来源原则 (known.json 已含 135 频道),
/// dead.json 备用 — 当前实现读 known, dead 不强制 fetch (留接口).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// v0.3.10.8: 远端 repo raw base. 跟 RemoteChannelsSource 同根.
const String _repoBase =
    'https://raw.githubusercontent.com/aqiyoung/iptv-channels-organized/main';

/// v0.3.10.8: 视频源 bundle — known 频道 URL 表 + meta + (预留) dead URLs.
/// known: Map<channelId, urls[]> — 跟本地 known_sources.json 结构兼容.
/// dead:  Map<channelId, urls[]> — 备用, 未来可用来过滤掉死链.
class RemoteSourcesBundle {
  const RemoteSourcesBundle({
    required this.meta,
    required this.known,
    required this.dead,
  });

  final Map<String, dynamic> meta;

  /// channel_id → URLs.  schema: { "CCTV1.cn": ["url1", "url2", ...] }
  final Map<String, List<String>> known;

  /// channel_id → dead URLs (本次未用到, 留接口给未来过滤).
  final Map<String, List<String>> dead;

  /// meta._meta.generated_at ISO 字符串 — 用于 cache key (没变 → cache 命中).
  String get generatedAt {
    final inner = meta['_meta'];
    if (inner is Map && inner['generated_at'] is String) {
      return inner['generated_at'] as String;
    }
    if (meta['generated_at'] is String) {
      return meta['generated_at'] as String;
    }
    return '';
  }

  /// meta._meta.count — 已知有效源总数 (远端报告).
  int get knownCount {
    final inner = meta['_meta'];
    if (inner is Map && inner['count'] is int) {
      return inner['count'] as int;
    }
    return known.length;
  }
}

class RemoteSourcesException implements Exception {
  RemoteSourcesException(this.message);
  final String message;
  @override
  String toString() => 'RemoteSourcesException: $message';
}

/// v0.3.10.8: 视频源远端 fetcher — 启动时拉一次 known.json (+ 可选 dead.json).
class RemoteSourcesSource {
  RemoteSourcesSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 拉 known.json. 失败抛 RemoteSourcesException.
  /// 注: dead.json 当前未用, 不在这里 fetch (省 1 个 HTTP 请求).
  /// 留 `fetchWithDead()` 接口供未来需要 dead 列表时用.
  Future<RemoteSourcesBundle> fetch({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final knownJson = await _fetchJson('sources/known.json', timeout);
    return RemoteSourcesBundle(
      meta: knownJson,
      known: _parseChannels(knownJson),
      dead: const <String, List<String>>{},
    );
  }

  /// 拉 known + dead — 给未来需要 dead 列表的 caller 用.
  Future<RemoteSourcesBundle> fetchWithDead({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final results = await Future.wait([
      _fetchJson('sources/known.json', timeout),
      _fetchJson('sources/dead.json', timeout),
    ]);
    return RemoteSourcesBundle(
      meta: results[0],
      known: _parseChannels(results[0]),
      dead: _parseDeadChannels(results[1]),
    );
  }

  Future<Map<String, dynamic>> _fetchJson(String path, Duration timeout) async {
    final resp =
        await _client.get(Uri.parse('$_repoBase/$path')).timeout(timeout);
    if (resp.statusCode != 200) {
      throw RemoteSourcesException('GET $path → ${resp.statusCode}');
    }
    final decoded = json.decode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw RemoteSourcesException(
          'GET $path: 顶层不是 Map (${decoded.runtimeType})');
    }
    return decoded;
  }

  /// 解析 sources/known.json: { _meta, channels: [{ channel_id, urls: [...] }] }
  /// → Map<channelId, urls>. 跳过 url 列表为空的频道.
  Map<String, List<String>> _parseChannels(Map<String, dynamic> json) {
    final out = <String, List<String>>{};
    final list = json['channels'];
    if (list is! List) return out;
    for (final c in list) {
      if (c is! Map<String, dynamic>) continue;
      final id = c['channel_id'];
      final urls = c['urls'];
      if (id is! String) continue;
      if (urls is! List) continue;
      final urlList = urls.whereType<String>().toList(growable: false);
      if (urlList.isEmpty) continue;
      out[id] = urlList;
    }
    return out;
  }

  /// 解析 sources/dead.json: { _meta, channels: [{ channel_id, url }] }
  /// → Map<channelId, [url]>. 同一 channel 多个死链合并到一个 list.
  Map<String, List<String>> _parseDeadChannels(Map<String, dynamic> json) {
    final out = <String, List<String>>{};
    final list = json['channels'];
    if (list is! List) return out;
    for (final c in list) {
      if (c is! Map<String, dynamic>) continue;
      final id = c['channel_id'];
      final url = c['url'];
      if (id is! String || url is! String) continue;
      out.putIfAbsent(id, () => <String>[]).add(url);
    }
    return out;
  }

  void close() => _client.close();
}

/// v0.3.10.8: Riverpod provider — 单例 RemoteSourcesSource.
/// ProviderScope dispose 时自动关 client — 避免 http leak.
final remoteSourcesSourceProvider = Provider<RemoteSourcesSource>((ref) {
  final source = RemoteSourcesSource();
  ref.onDispose(source.close);
  return source;
});

/// v0.3.10.8: AsyncNotifier — 启动时拉一次, 失败 throw 让 caller fallback.
/// 显式 refresh() 触发重拉 (后台 03:00 调度走 invalidate).
class RemoteSourcesNotifier extends AsyncNotifier<RemoteSourcesBundle> {
  @override
  Future<RemoteSourcesBundle> build() async {
    final source = ref.read(remoteSourcesSourceProvider);
    return source.fetch();
  }

  /// 强制重拉 — 给 startSourcesAutoRefresh 03:00 调度 + 启动 >1 天重拉用.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final source = ref.read(remoteSourcesSourceProvider);
      return source.fetch();
    });
  }
}

/// v0.3.10.8: 远端 video sources provider.  失败 throw → channelRepository fallback 本地.
final remoteSourcesProvider =
    AsyncNotifierProvider<RemoteSourcesNotifier, RemoteSourcesBundle>(
  RemoteSourcesNotifier.new,
);
