import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';

/// Channel Repository — 从编译时内嵌的 JSON 加载
class ChannelRepository {
  const ChannelRepository();

  Future<List<Channel>> loadBundled() async {
    final raw = await rootBundle.loadString('assets/data/channels_cn.json');
    final list = json.decode(raw) as List;
    final channels = list
        .map((e) => Channel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    // 加载 known_sources.json (国内公开 HLS 兑底) 并合并到各 Channel.sources
    try {
      final knownRaw =
          await rootBundle.loadString('assets/data/known_sources.json');
      final known = json.decode(knownRaw) as Map<String, dynamic>;
      return channels.map((c) {
        final sources =
            (known[c.id] as List?)?.cast<String>() ?? const <String>[];
        if (sources.isEmpty) return c;
        return Channel(
          id: c.id,
          name: c.name,
          country: c.country,
          categories: c.categories,
          altNames: c.altNames,
          website: c.website,
          logoUrl: c.logoUrl,
          sources: sources,
          isNsfw: c.isNsfw,
        );
      }).toList(growable: false);
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
