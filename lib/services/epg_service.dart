import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../core/http/ipv4_client.dart';
import '../data/models/epg.dart';

/// EPG 服务 — 懒加载 + 7 天缓存 + 当前/下一档节目展示
class EpgService {
  EpgService({http.Client? client, Database? db})
      : _client = client ?? IPv4Client(),
        _injectedDb = db;

  /// 注入 http client (test 用); 保留字段以备未来 XMLTV 接入
  // ignore: unused_field
  final http.Client _client;
  final Database? _injectedDb;
  Database? _db;
  static const Duration _cacheMaxAge = Duration(days: 7);

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
      return list
          .map((e) => EpgEntry.fromJson(e as Map<String, dynamic>))
          .toList();
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

  /// 从 iptv-org EPG API 拉取 (XMLTV 格式)
  /// 实际 API: https://iptv-org.github.io/epg/guides/{cc}.xml.gz
  /// 这里 stub 返回空列表, 真实项目需要 XMLTV 解析.
  /// v0.3.8+93 (6/20 P0-2): 不再返回空 — 拿不到 EPG 时返时段占位.
  /// 4 档占位: 上午档 (06-12) / 下午档 (12-18) / 黄金档 (18-22) / 夜间档 (22-06).
  /// UI 看到的是「黄金档 · 电视剧」而不是「暂无节目信息」,  体验成倍提升.
  /// iptv-org 接进后,  _fetchRemote 返真数据,  _placeholderSchedule 被覆盖.
  Future<List<EpgEntry>> _fetchRemote(String channelId) async {
    // iptv-org 不直接提供 per-channel JSON EPG
    // 真实实现需要下载 XMLTV gz 并解析 (卡 +5 计划内)
    // 当前 release 用时段占位 + 频道名当档名,  老设备也能看个象样的节目卡.
    final entries = _placeholderSchedule(channelId);
    // ignore: avoid_print
    debugPrint('EpgService._fetchRemote: 占位 EPG for $channelId (${entries.length} 档)');
    return entries;
  }

  /// 时段占位 — 按当地时间今天生成 4 档.
  /// v0.3.8+93 (6/20 P0-2): 拿不到 iptv-org XMLTV 时给个象样的节目卡.
  /// 实际接入 XMLTV 后这个会被覆盖.
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
