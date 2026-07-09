import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/content.dart';
import '../models/vod_source.dart';
import '../../services/vod_api_service.dart';
import '../../services/vod_source_registry.dart';

/// v0.3.13.0: VOD API 服务 — 从 registry 取活跃源构造 (baseUrl 动态).
/// 源切换 → activeSource 变 → 此 provider rebuild → 所有 VOD providers 重建.
final vodApiServiceProvider = Provider<VodApiService>((ref) {
  final registry = ref.watch(vodSourceRegistryProvider);
  final service = VodApiService(
    baseUrl: registry.activeSource.baseUrl,
    client: http.Client(),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// 推荐内容: 混合分类的最新更新.  typeIds 从活跃源动态读取.
final vodRecommendedProvider = FutureProvider<List<Content>>((ref) async {
  final api = ref.read(vodApiServiceProvider);
  final ids = ref.read(vodSourceRegistryProvider).activeSource.typeIds;
  final movieT = ids['movie'] ?? 20;
  final seriesT = ids['series'] ?? 30;
  final varietyT = ids['variety'] ?? 45;
  final futures = [
    api.getList(typeId: movieT, page: 1, pageSize: 5),
    api.getList(typeId: seriesT, page: 1, pageSize: 3),
    api.getList(typeId: varietyT, page: 1, pageSize: 2),
  ];
  final results = await Future.wait(futures);
  // 去重 (按 vod_id)
  final seen = <int>{};
  final merged = <Map<String, dynamic>>[];
  for (final list in results) {
    for (final item in list) {
      final id = item['vod_id'] as int? ?? 0;
      if (id > 0 && seen.add(id)) merged.add(item);
    }
  }
  // 批量取详情 (拿海报和播放 URL)
  final vodIds = merged.map((e) => e['vod_id'] as int).toList();
  final details = await api.getDetail(vodIds.take(10).toList());
  return details.map((d) => api.toContent(d)).toList();
});

/// 热播电影.  typeId 从活跃源动态读取.
final vodMoviesProvider = FutureProvider<List<Content>>((ref) async {
  final api = ref.read(vodApiServiceProvider);
  final typeId = ref.read(vodSourceRegistryProvider).activeSource.typeIds['movie'] ?? 20;
  final items = await api.getList(typeId: typeId, page: 1, pageSize: 10);
  final ids = items.map((e) => e['vod_id'] as int).toList();
  final details = await api.getDetail(ids);
  return details.map((d) => api.toContent(d)).toList();
});

/// 热播剧集.  typeId 从活跃源动态读取.
final vodSeriesProvider = FutureProvider<List<Content>>((ref) async {
  final api = ref.read(vodApiServiceProvider);
  final typeId = ref.read(vodSourceRegistryProvider).activeSource.typeIds['series'] ?? 30;
  final items = await api.getList(typeId: typeId, page: 1, pageSize: 10);
  final ids = items.map((e) => e['vod_id'] as int).toList();
  final details = await api.getDetail(ids);
  return details.map((d) => api.toContent(d)).toList();
});

/// 热门综艺.  typeId 从活跃源动态读取.
final vodVarietyProvider = FutureProvider<List<Content>>((ref) async {
  final api = ref.read(vodApiServiceProvider);
  final typeId = ref.read(vodSourceRegistryProvider).activeSource.typeIds['variety'] ?? 45;
  final items = await api.getList(typeId: typeId, page: 1, pageSize: 8);
  final ids = items.map((e) => e['vod_id'] as int).toList();
  final details = await api.getDetail(ids);
  return details.map((d) => api.toContent(d)).toList();
});

/// v0.3.13.0: 海外剧场 (欧美剧).  typeId 从活跃源动态读取.
/// 默认源 bfzyapi.com = 32 (欧美剧 6322 部).  IKun/标准系 = 26.
final vodOverseasProvider = FutureProvider<List<Content>>((ref) async {
  final api = ref.read(vodApiServiceProvider);
  final registry = ref.read(vodSourceRegistryProvider);
  final typeId = registry.activeSource.typeIds['overseas'];
  // 该源没有 overseas typeId → 返空 (UI 显示 "当前源无此分类").
  if (typeId == null) return [];
  final items = await api.getList(typeId: typeId, page: 1, pageSize: 10);
  final ids = items.map((e) => e['vod_id'] as int).toList();
  final details = await api.getDetail(ids);
  return details.map((d) => api.toContent(d)).toList();
});