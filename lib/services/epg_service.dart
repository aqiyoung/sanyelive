import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/epg.dart';

/// EPG 服务 — 懒加载 + 7 天缓存 + 当前/下一档节目展示
class EpgService {
  EpgService({http.Client? client}) : _client = client ?? http.Client();

  /// 注入 http client (test 用); 保留字段以备未来 XMLTV 接入
  // ignore: unused_field
  final http.Client _client;

  static const String _cachePrefix = 'epg_cache_';
  static const String _cacheMetaPrefix = 'epg_meta_';
  static const Duration _cacheMaxAge = Duration(days: 7);

  /// 获取某个频道的 EPG 列表 (优先缓存, 过期则拉取)
  Future<List<EpgEntry>> fetch(String channelId) async {
    // 1. 尝试缓存
    final cached = await _readCache(channelId);
    if (cached != null) return cached;

    // 2. 懒加载 — 仅在有网络时拉取
    try {
      final entries = await _fetchRemote(channelId);
      await _writeCache(channelId, entries);
      return entries;
    } catch (_) {
      // 拉取失败 → 返回空列表 (不阻塞 UI)
      return const [];
    }
  }

  /// 获取当前正在播出的节目
  Future<EpgEntry?> currentProgram(String channelId) async {
    final entries = await fetch(channelId);
    final now = DateTime.now().toUtc();
    for (final e in entries) {
      if (!e.start.isAfter(now) && e.end.isAfter(now)) return e;
    }
    return null;
  }

  /// 获取下一个节目
  Future<EpgEntry?> nextProgram(String channelId) async {
    final entries = await fetch(channelId);
    final now = DateTime.now().toUtc();
    EpgEntry? best;
    for (final e in entries) {
      if (e.start.isAfter(now)) {
        if (best == null || e.start.isBefore(best.start)) best = e;
      }
    }
    return best;
  }

  // ─── 缓存层 ───

  Future<List<EpgEntry>?> _readCache(String channelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metaKey = '$_cacheMetaPrefix$channelId';
      final meta = prefs.getString(metaKey);
      if (meta == null) return null;

      final metaMap = json.decode(meta) as Map<String, dynamic>;
      final ts = metaMap['ts'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _cacheMaxAge.inMilliseconds) return null;

      final dataKey = '$_cachePrefix$channelId';
      final raw = prefs.getString(dataKey);
      if (raw == null) return null;

      final list = json.decode(raw) as List;
      return list
          .map((e) => EpgEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String channelId, List<EpgEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataKey = '$_cachePrefix$channelId';
      final metaKey = '$_cacheMetaPrefix$channelId';

      final raw = json.encode(entries.map((e) => e.toJson()).toList());
      await prefs.setString(dataKey, raw);
      await prefs.setString(
        metaKey,
        json.encode({'ts': DateTime.now().millisecondsSinceEpoch}),
      );
    } catch (_) {
      // 缓存写入失败不影响功能
    }
  }

  // ─── 网络层 ───

  /// 从 iptv-org EPG API 拉取 (XMLTV 格式)
  /// 实际 API: https://iptv-org.github.io/epg/guides/{cc}.xml.gz
  /// 这里 stub 返回空列表, 真实项目需要 XMLTV 解析.
  Future<List<EpgEntry>> _fetchRemote(String channelId) async {
    // iptv-org 不直接提供 per-channel JSON EPG
    // 真实实现需要下载 XMLTV gz 并解析
    // 此处返回空列表作为占位, UI 层已有空态处理
    // TODO: 接入真实 XMLTV EPG 数据源
    return const [];
  }
}

/// Riverpod provider
final epgServiceProvider = Provider<EpgService>((ref) => EpgService());

/// 某频道当前/下一档节目 provider
final epgProgramsProvider =
    FutureProvider.family<({EpgEntry? current, EpgEntry? next}), String>(
        (ref, channelId) async {
  final svc = ref.watch(epgServiceProvider);
  final entries = await svc.fetch(channelId);
  final now = DateTime.now().toUtc();

  EpgEntry? current;
  EpgEntry? next;

  for (final e in entries) {
    if (!e.start.isAfter(now) && e.end.isAfter(now)) {
      current = e;
    }
    if (e.start.isAfter(now)) {
      if (next == null || e.start.isBefore(next.start)) next = e;
    }
  }

  return (current: current, next: next);
});
