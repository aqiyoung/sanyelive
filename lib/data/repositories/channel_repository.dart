import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
      isNsfw: c.isNsfw,
    );
  }).toList(growable: false);
}

/// Channel Repository — 从编译时内嵌的 JSON 加载
class ChannelRepository {
  const ChannelRepository();

  Future<List<Channel>> loadBundled() async {
    final raw = await rootBundle.loadString('assets/data/channels_cn.json');
    final list = json.decode(raw) as List;
    final channels = list
        .map((e) => Channel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    // 加载 known_sources.json (国内公开 HLS 兑底) 并追加 (不覆盖) 到各 Channel.sources.
    // channels_cn.json 里已经 bake 了 iptv-org 高画质源, known_sources 是兑底,
    // 顺序 = iptv-org 先, known_sources 后 (去重).  SourceFailover 从前往后试.
    try {
      final knownRaw =
          await rootBundle.loadString('assets/data/known_sources.json');
      final known = json.decode(knownRaw) as Map<String, dynamic>;
      return mergeKnownSources(channels, known);
    } catch (_) {
      // known_sources.json 读取失败, 返回原始 channels
      return channels;
    }
  }
}

final channelRepositoryProvider = Provider<ChannelRepository>(
  (ref) => const ChannelRepository(),
);

final channelsProvider = FutureProvider<List<Channel>>((ref) async {
  final repo = ref.watch(channelRepositoryProvider);
  return repo.loadBundled();
});
