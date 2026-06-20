import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';

/// 把 [known] 里跟 channel.id 匹配的 URL 列表追加到 [c].sources 后面,
/// 去重但保留首次出现的顺序.  不修改传入的 channel, 返回新实例.
/// 卡 6: channels_cn.json 里 bake 的 iptv-org 高画质源必须保留在前面,
/// known_sources.json 是兑底, SourceFailover 从前往后试.
@visibleForTesting
List<Channel> mergeKnownSources(
  List<Channel> channels,
  Map<String, dynamic> known,
) {
  return channels.map((c) {
    final knownForChannel =
        (known[c.id] as List?)?.cast<String>() ?? const <String>[];
    if (knownForChannel.isEmpty) return c;
    final merged = <String>[];
    final seen = <String>{};
    for (final url in c.sources) {
      if (seen.add(url)) merged.add(url);
    }
    for (final url in knownForChannel) {
      if (seen.add(url)) merged.add(url);
    }
    return Channel(
      id: c.id,
      name: c.name,
      country: c.country,
      categories: c.categories,
      altNames: c.altNames,
      website: c.website,
      logoUrl: c.logoUrl,
      sources: merged,
      cctvSource:
          c.cctvSource, // v0.3.5.3 (6/18): 保留 CCTV 专属源不被 known_sources 覆盖
      isNsfw: c.isNsfw,
    );
  }).toList(growable: false);
}

/// Channel Repository — 从编译时内嵌的 JSON 加载
class ChannelRepository {
  const ChannelRepository();

  /// v0.3.7+50 (6/19): 内存缓存 — 避免每次 [channelsProvider] rebuild 都
  /// `rootBundle.loadString` 2 份 assets + `json.decode`.  首屏 (home_page)
  /// 一次读完后,  push 到 player_page 又 pop 回 home 不会重新 IO.
  ///
  /// 注意:  - 用 `static` 字段而不是 Provider/ChangeNotifier,  因为这份
  /// 缓存是"读一次就不变"的数据 (assets 在 APP 生命周期里不变).
  /// - 不放 Provider 是因为 Riverpod 的 `ref.watch(channelsProvider)` 已经
  /// 会 dedup,  但 PlayerPage 自己 `ref.read(channelsProvider.future)` 会
  /// bypass FutureProvider 的 cache,  走 repo 的 cache 才能真正零 IO.
  static List<Channel>? _cached;
  static Future<List<Channel>>? _pending;

  Future<List<Channel>> loadBundled() async {
    // 命中缓存 → 零 IO,  直接返回.
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    // 并发去重: 多个 widget 同时 init 调 loadBundled() 时,  只跑一次
    // rootBundle.loadString,  其余 await 同一个 Future.
    final pending = _pending;
    if (pending != null) {
      return pending;
    }
    final future = _loadBundledImpl();
    _pending = future;
    try {
      final result = await future;
      _cached = result;
      return result;
    } finally {
      _pending = null;
    }
  }

  /// 实际 IO 路径.  拆出来让 [loadBundled] 缓存逻辑更清晰.
  Future<List<Channel>> _loadBundledImpl() async {
    // v0.3.8+110 (6/20 老板加国际频道模块):  并行加载 CN + I18N,  合并为一个
    // [Channel] 列表.  CN 中国频道 + I18N 1886 国际频道.  合并顺序:  CN 先
    // (首页分类依 country='CN' / id.startsWith('CCTV') 路由),  I18N 后.
    // i18n channels 都有 country (US/UK/FR/DE/RU/IN/JP).
    final cnFuture = _loadChannels('assets/data/channels_cn.json');
    final i18nFuture = _loadChannels('assets/data/channels_i18n.json');
    final knownFuture = _loadKnownSources();

    final cn = await cnFuture;
    final i18n = await i18nFuture;
    final known = await knownFuture;

    final merged = <Channel>[...cn, ...i18n];
    if (known != null) {
      return mergeKnownSources(merged, known);
    }
    return merged;
  }

  /// v0.3.8+110 (6/20):  抽 CN/I18N 公共加载逻辑 (JSON -> List<Channel>).
  /// 加载失败返回空数组 (call 端合并时正常).
  Future<List<Channel>> _loadChannels(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      final list = json.decode(raw) as List;
      return list
          .map((e) => Channel.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('ChannelRepository._loadChannels($path) failed: $e');
      return const <Channel>[];
    }
  }

  /// v0.3.8+110 (6/20):  known_sources.json 单独抽 — 加载失败返 null
  /// (call 端选不 merge,  避免隐式吞错).
  Future<Map<String, dynamic>?> _loadKnownSources() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/known_sources.json');
      return json.decode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ChannelRepository._loadKnownSources failed: $e');
      return null;
    }
  }

  /// v0.3.7+50 (6/19) — 测试钩子.  单元测试 setUp 里清缓存,  避免
  /// "上一个测试改了 mock data,  这个测试还看到老 cache" 的状态泄漏.
  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _pending = null;
  }
}

final channelRepositoryProvider = Provider<ChannelRepository>(
  (ref) => const ChannelRepository(),
);

final channelsProvider = FutureProvider<List<Channel>>((ref) async {
  final repo = ref.watch(channelRepositoryProvider);
  return repo.loadBundled();
});
