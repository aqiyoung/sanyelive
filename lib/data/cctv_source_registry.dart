import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'cctv_source_model.dart';

/// CCTV 源 registry — 加载 assets/data/cctv_sources.json (按 channel.id 分组)。
///
/// 加载策略: 启动时 [CctvSourceRegistry.load] 异步加载, 缓存到 [_instance];
/// 加载失败 (文件缺失 / 解析错) 时降级到空表。后续 release 可通过
/// discover_cctv_sources.py 重新跑健康分写到 cctv_sources.json 覆盖, 不用 rebuild APK。
class CctvSourceRegistry {
  CctvSourceRegistry._({required this.sourcesByChannel});

  static CctvSourceRegistry? _instance;

  /// 已加载的实例, 未加载时为 null (picker 据此判断是否走 registry 候选)。
  static CctvSourceRegistry? get instanceOrNull => _instance;

  static Future<CctvSourceRegistry> load() async {
    if (_instance != null) return _instance!;
    try {
      final raw = await rootBundle.loadString('assets/data/cctv_sources.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      _instance = CctvSourceRegistry._fromJson(map);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('CctvSourceRegistry.load failed, falling back to static: $e');
      }
      _instance = CctvSourceRegistry._(
          sourcesByChannel: const <String, List<CctvSource>>{});
    }
    return _instance!;
  }

  static CctvSourceRegistry get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('CctvSourceRegistry not loaded. Call load() first.');
    }
    return i;
  }

  @visibleForTesting
  static void debugSet(CctvSourceRegistry? registry) {
    _instance = registry;
  }

  @visibleForTesting
  static CctvSourceRegistry debugFromJson(Map<String, dynamic> json) =>
      CctvSourceRegistry._fromJson(json);

  factory CctvSourceRegistry._fromJson(Map<String, dynamic> json) {
    final sourcesByChannel = <String, List<CctvSource>>{};
    // 实际 schema: {_comment, _generated_at, _source_count, channels:{CCTV1.cn:[...]}}
    // 老 schema 兼容: 顶层直接是 {CCTV1.cn:[...]}.
    final root = json['channels'] is Map<String, dynamic>
        ? json['channels'] as Map<String, dynamic>
        : json;
    for (final entry in root.entries) {
      final channelId = entry.key;
      if (channelId.startsWith('_')) continue; // 跳过 _meta 字段
      final value = entry.value;
      if (value is! List) continue; // 单条脏数据不拖垮整表
      final parsed = <CctvSource>[];
      for (final e in value) {
        if (e is! Map<String, dynamic>) continue;
        if (e['url'] is! String) continue;
        parsed.add(CctvSource.fromJson(e));
      }
      if (parsed.isNotEmpty) {
        sourcesByChannel[channelId] = List<CctvSource>.unmodifiable(parsed);
      }
    }
    return CctvSourceRegistry._(sourcesByChannel: sourcesByChannel);
  }

  /// Public read-only view of the sources map.
  final Map<String, List<CctvSource>> sourcesByChannel;

  /// 拿指定 channel 的所有 CCTV 源 (按 health_score 降序)。
  List<CctvSource> getForChannel(String channelId) {
    return sourcesByChannel[channelId] ?? const <CctvSource>[];
  }

  /// 所有 channel id 列表 (debug UI 遍历用)。
  Iterable<String> get channelIds => sourcesByChannel.keys;
}
