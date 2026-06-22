import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../core/http/ipv4_client.dart';
import '../data/models/epg.dart';
import '../data/sources/epg_xmltv_source.dart';

/// EPG 服务 — 懒加载 + 缓存 + 当前/下一档节目展示
class EpgService {
  EpgService({http.Client? client, Database? db})
      : _client = client ?? IPv4Client(),
        _injectedDb = db;

  /// 注入 http client (test 用); 保留字段以备未来 XMLTV 接入
  // ignore: unused_field
  final http.Client _client;
  final Database? _injectedDb;
  Database? _db;
  static const Duration _cacheMaxAge = Duration(hours: 6);

  // v0.3.10 (6/23): 51zmt XMLTV 全量缓存. 首次 fetch 时拉 ~1MB XML,
  // 解析后存 _allEntries; 后续按 channel 查询走内存 (避免每频道重复拉).
  XmltvEpgSource? _xmltvSource;
  Map<String, List<EpgEntry>> _allEntries = const {};
  bool _xmltvLoaded = false;

  static const String _table = 'epg_cache';

  Future<Database> get _database async {
    if (_injectedDb != null) return _injectedDb;
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'iptv_epg.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            channel_id TEXT PRIMARY KEY,
            entries_json TEXT NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

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
    } catch (e) {
      debugPrint('EpgService.fetch remote failed: $e');
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
      final db = await _database;
      final rows = await db.query(
        _table,
        where: 'channel_id = ?',
        whereArgs: [channelId],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final cachedAt = row['cached_at'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > _cacheMaxAge.inMilliseconds) return null;

      final raw = row['entries_json'] as String;
      final list = json.decode(raw) as List;
      final entries = list
          .map((e) => EpgEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      // v0.3.10 (6/23): EPG 是未来时刻 — 如果缓存里的所有档位都已在过去
      // (例: 缓存是昨天拉的, 24h+2h 范围已过期), 当作 stale, 重新拉.
      // 否则 currentProgram 返回 null, UI "暂无节目".
      if (entries.isNotEmpty) {
        final latestEnd = entries.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b);
        if (!latestEnd.isAfter(DateTime.now())) return null;
      }
      return entries;
    } catch (e) {
      debugPrint('EpgService._readCache failed: $e');
      return null;
    }
  }

  Future<void> _writeCache(String channelId, List<EpgEntry> entries) async {
    try {
      final db = await _database;
      final raw = json.encode(entries.map((e) => e.toJson()).toList());
      await db.insert(
        _table,
        {
          'channel_id': channelId,
          'entries_json': raw,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('EpgService._writeCache failed: $e');
    }
  }

  // ─── 网络层 ───

  /// 拉取某频道的 EPG 列表.
  ///
  /// v0.3.10 (6/23): 接 51zmt 真实 XMLTV 数据源
  /// (http://epg.51zmt.top:8000/e.xml.gz, 老板 6/23 06:50 反馈
  /// "不应该拉真实的实时数据吗").
  ///
  /// 1) 首次调用拉全量 XML (lazy,  ~1MB, 102 频道),
  ///    解析后存 _allEntries (in-memory cache,  跟 sqflite 缓存不冲突:
  ///    sqflite 缓各频道的过滤后档位 6h,  全量 XML 只在 session 内
  ///    持有避免重复拉).
  /// 2) 映射 iptv-org channel.id (CCTV1.cn) → 51zmt channel.id (1).
  /// 3) 按时间过滤: 现在 -2h → 现在 +24h (避免给一堆昨天/明天的档).
  /// 4) 拉取 / 映射失败 → fallback _placeholderSchedule (v0.3.9+3 时区
  ///    已对齐 Beijing local).
  Future<List<EpgEntry>> _fetchRemote(String channelId) async {
    // 1) 首次: 拉全量 XMLTV
    if (!_xmltvLoaded) {
      try {
        _xmltvSource ??= XmltvEpgSource();
        final xml = await _xmltvSource!.fetchXml();
        _allEntries = await _xmltvSource!.parseXml(xml);
        _xmltvLoaded = true;
        debugPrint(
            'EpgService: 51zmt XMLTV loaded ${_allEntries.length} channels, '
            '${_allEntries.values.fold(0, (a, b) => a + b.length)} programmes');
      } catch (e) {
        debugPrint('EpgService: 51zmt fetch failed: $e, fallback to placeholder');
        return _placeholderSchedule(channelId);
      }
    }

    // 2) 映射 channel.id
    final epgChId = XmltvEpgSource.mapChannelIdToEpg(channelId);
    if (epgChId == null || !_allEntries.containsKey(epgChId)) {
      return _placeholderSchedule(channelId);
    }

    // 3) 过滤时间 (避免过期/超远未来档)
    final now = DateTime.now();
    final entries = _allEntries[epgChId]!.where((e) {
      return e.end.isAfter(now.subtract(const Duration(hours: 2))) &&
          e.start.isBefore(now.add(const Duration(hours: 24)));
    }).toList();

    // 4) 过滤后空 → fallback (避免返回空导致 UI "暂无节目")
    return entries.isEmpty ? _placeholderSchedule(channelId) : entries;
  }

  /// 时段占位 — 按当地时间今天生成 4 档.
  /// v0.3.8+93 (6/20 P0-2): 拿不到 iptv-org XMLTV 时给个象样的节目卡.
  /// 实际接入 XMLTV 后这个会被覆盖.
  /// v0.3.9+3: 改用 local time (Beijing), 跟 now_next_program.dart 的
  /// DateTime.now() 对齐.  之前用 UTC 导致占位 EPG 边界算到前一天, 凌晨
  /// 06:46 Beijing 误显 "夜间档 · 午夜剧场" (UTC 22:46 → h=22).
  /// v0.3.10 (6/23):  51zmt 接入后, 本方法只剩 fallback 角色.  保留逻辑
  /// 不变 (local time, 4 时段).
  List<EpgEntry> _placeholderSchedule(String channelId) {
    // v0.3.9+3: 改用 local time (Beijing), 跟 now_next_program.dart 的
    // DateTime.now() 对齐.  之前用 UTC 导致占位 EPG 边界算到前一天, 凌晨
    // 06:46 Beijing 误显 "夜间档 · 午夜剧场" (UTC 22:46 → h=22).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String titleFor(DateTime start) {
      final h = start.hour;
      if (h < 6) return '夜间档 · 重播精选';
      if (h < 12) return '上午档 · 资讯杂志';
      if (h < 18) return '下午档 · 综艺生活';
      if (h < 22) return '黄金档 · 电视剧';
      return '夜间档 · 午夜剧场';
    }

    final boundaries = [6, 12, 18, 22];
    final entries = <EpgEntry>[];
    DateTime start = today;
    for (final h in boundaries) {
      final end = today.add(Duration(hours: h));
      entries.add(EpgEntry(
        channelId: channelId,
        title: titleFor(start),
        start: start,
        end: end,
      ));
      start = end;
    }
    // 最后一个档到明天早上 6:00
    entries.add(EpgEntry(
      channelId: channelId,
      title: titleFor(start),
      start: start,
      end: today.add(const Duration(hours: 30)),
    ));
    return entries;
  }
}

/// Riverpod provider — 生产环境自动创建 sqflite 数据库.
/// 测试可 overrideWithValue(EpgService(db: mockDb)).
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
