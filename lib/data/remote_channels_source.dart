/// v0.3.8+125 (6/21 老板拍):  远程分类频道数据源.
///
/// 数据源:  aqiyoung/iptv-channels-organized repo (每周一 cron 自动生成).
/// JSON schema 跟 iptv-org 单条 Channel 兼容 (id/name/country/categories/
/// alt_names/logo/sources/cctvSource/is_nsfw/website),  直接走
/// Channel.fromJson 解析.
///
/// 失败策略:  拉不到 / 超时 / 解析错 → 抛 RemoteChannelsException,
/// caller (channelsProvider) 用本地 assets/data/channels_cn.json 兜底.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'models/channel.dart';

/// v0.3.8+125:  远程 repo raw base.  raw.githubusercontent.com 公开访问
/// (假设 repo public);  若改 private 必须换 github API + token.  当前
/// schema 见 meta.json + channels/*.json 顶层 { _meta, groups } 结构.
const _repoBase =
    'https://raw.githubusercontent.com/aqiyoung/iptv-channels-organized/main';

/// 远程频道数据源 — 启动时拉一次.
class RemoteChannelsSource {
  RemoteChannelsSource({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  /// 拉远程 meta + 4 个分类 JSON.  返回 RemoteChannelsBundle.
  /// 超时 10s,  失败抛 RemoteChannelsException,  caller fallback 本地.
  Future<RemoteChannelsBundle> fetch({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // 5 个并发请求 — meta + 4 个分类.  Future.wait 让所有延迟并行.
    // 显式 List<Map<String, dynamic>> 让 results[i] 类型推断,  避免
    // analyze unnecessary_cast warning.
    final List<Map<String, dynamic>> results = await Future.wait([
      _fetchJson('meta.json', timeout),
      _fetchJson('channels/cctv.json', timeout),
      _fetchJson('channels/satellite.json', timeout),
      _fetchJson('channels/local.json', timeout),
      _fetchJson('channels/international.json', timeout),
    ]);
    return RemoteChannelsBundle(
      meta: results[0],
      cctv: _parseChannels(results[1]),
      satellite: _parseChannels(results[2]),
      local: _parseChannels(results[3]),
      international: _parseChannels(results[4]),
    );
  }

  Future<Map<String, dynamic>> _fetchJson(String path, Duration timeout) async {
    final resp =
        await _client.get(Uri.parse('$_repoBase/$path')).timeout(timeout);
    if (resp.statusCode != 200) {
      throw RemoteChannelsException('GET $path → ${resp.statusCode}');
    }
    final decoded = json.decode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw RemoteChannelsException(
          'GET $path: 顶层不是 Map (${decoded.runtimeType})');
    }
    return decoded;
  }

  /// 解析 channels/{cat}.json — 顶层 { _meta, groups|provinces|countries: { ... } }.
  /// cctv.json 用 groups (按 CCTV 序号分).  satellite.json / local.json 用
  /// provinces (按省/直辖市分).  international.json 用 countries (按 ISO 国家码).
  /// 兼容二个字段名 — fetch 付一个不报错.  flatten 所有 group 进单一 List<Channel>.
  List<Channel> _parseChannels(Map<String, dynamic> json) {
    // v0.3.8+126 (6/21 老板反馈 "卫视怎么还在地方分类"):
    // 之前只查 json['groups'] — satellite/local 用 'provinces',  international
    // 用 'countries'.  查不到 → 报 "channels JSON 缺 groups 字段",  bundle.all
    // 退化成只含 cctv 部分.  app 读取时本地 fallback 被跳过,  CategoryGrid 拿到
    // bundle.all (cctv only) → ChannelFilter 重新分 → "卫视" 分类里出现地方频道.
    // 修法:  兼容 'groups' / 'provinces' / 'countries' 三个字段名.  都不在时报错.
    final groups = (json['groups'] ?? json['provinces'] ?? json['countries'])
        as Map<String, dynamic>?;
    if (groups == null) {
      throw RemoteChannelsException(
          'channels JSON 缺 groups/provinces/countries 字段 (${json.runtimeType})');
    }
    final all = <Channel>[];
    for (final entry in groups.entries) {
      final list = entry.value;
      if (list is! List) continue;
      for (final c in list) {
        if (c is Map<String, dynamic>) {
          try {
            all.add(Channel.fromJson(c));
          } catch (e) {
            // 单条 channel 解析失败不阻塞整体 — 跳过 + 打 log.
            debugPrint('RemoteChannelsSource: skip channel ${c['id']}: $e');
          }
        }
      }
    }
    return all;
  }
}

/// v0.3.8+125:  远程 bundle — 4 大分类 + meta + flat all list.
class RemoteChannelsBundle {
  RemoteChannelsBundle({
    required this.meta,
    required this.cctv,
    required this.satellite,
    required this.local,
    required this.international,
  });

  final Map<String, dynamic> meta;
  final List<Channel> cctv;
  final List<Channel> satellite;
  final List<Channel> local;
  final List<Channel> international;

  /// 合并所有分类 — UI 喂这个 list (跟 ChannelFilter / ChannelRepository
  /// 兼容:  都是 List<Channel>,  ChannelFilter.cctv/satellite/local 不动).
  List<Channel> get all => [...cctv, ...satellite, ...local, ...international];

  /// meta.sources.iptv_app 字段 — release version stamp.
  String get iptvAppStamp {
    final sources = meta['sources'];
    if (sources is Map && sources['iptv_app'] is String) {
      return sources['iptv_app'] as String;
    }
    return '';
  }
}

class RemoteChannelsException implements Exception {
  RemoteChannelsException(this.message);
  final String message;
  @override
  String toString() => 'RemoteChannelsException: $message';
}

/// v0.3.8+125:  Riverpod provider — 单例 RemoteChannelsSource.
final remoteChannelsSourceProvider = Provider<RemoteChannelsSource>((ref) {
  // ProviderScope dispose 时自动关 client — 避免 http leak.
  final source = RemoteChannelsSource();
  ref.onDispose(() {
    // ignore: discarded_futures
    source._client.close();
  });
  return source;
});

/// v0.3.8+125:  AsyncNotifier — 启动时拉一次,  失败 throw 让 caller fallback.
/// 显式 refresh() 触发重拉 (settings / 强制刷新入口).
class RemoteChannelsNotifier extends AsyncNotifier<RemoteChannelsBundle> {
  @override
  Future<RemoteChannelsBundle> build() async {
    final source = ref.read(remoteChannelsSourceProvider);
    return source.fetch();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final source = ref.read(remoteChannelsSourceProvider);
      return source.fetch();
    });
  }
}

final remoteChannelsProvider =
    AsyncNotifierProvider<RemoteChannelsNotifier, RemoteChannelsBundle>(
  RemoteChannelsNotifier.new,
);
