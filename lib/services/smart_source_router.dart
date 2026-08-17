/// SmartSourceRouter — 智能源路由 + 负载均衡
///
/// 在 SourceFailover 基础上增加:
/// 1. 源健康度探测 (HEAD 请求测延迟)
/// 2. 历史成功率评分 (SharedPreferences 持久化)
/// 3. 按评分排序, 优先走高质量源
/// 4. 定期刷新评分
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'source_failover.dart';
import '../utils/crash_logger.dart';

/// 单个源的健康评分
@immutable
class SourceScore {
  const SourceScore({
    required this.url,
    required this.score,
    required this.latencyMs,
    required this.successCount,
    required this.failCount,
    required this.lastTestedAt,
  });

  final String url;
  final double score; // 0.0 ~ 1.0, 越高越好
  final int latencyMs; // 最近一次探测延迟 (ms)
  final int successCount;
  final int failCount;
  final DateTime lastTestedAt;

  double get successRate =>
      (successCount + failCount) == 0 ? 0.5 : successCount / (successCount + failCount);

  Map<String, dynamic> toJson() => {
        'url': url,
        'score': score,
        'latencyMs': latencyMs,
        'successCount': successCount,
        'failCount': failCount,
        'lastTestedAt': lastTestedAt.toIso8601String(),
      };

  factory SourceScore.fromJson(Map<String, dynamic> j) => SourceScore(
        url: j['url'] as String,
        score: (j['score'] as num).toDouble(),
        latencyMs: j['latencyMs'] as int,
        successCount: j['successCount'] as int,
        failCount: j['failCount'] as int,
        lastTestedAt: DateTime.parse(j['lastTestedAt'] as String),
      );

  SourceScore copyWith({
    String? url,
    double? score,
    int? latencyMs,
    int? successCount,
    int? failCount,
    DateTime? lastTestedAt,
  }) =>
      SourceScore(
        url: url ?? this.url,
        score: score ?? this.score,
        latencyMs: latencyMs ?? this.latencyMs,
        successCount: successCount ?? this.successCount,
        failCount: failCount ?? this.failCount,
        lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      );
}

/// 智能路由器 — 探测 + 评分 + 排序
class SmartSourceRouter {
  SmartSourceRouter({http.Client? client, SharedPreferences? prefs})
      : _client = client ?? http.Client(),
        _prefs = prefs;

  final http.Client _client;
  final SharedPreferences? _prefs;
  static const String _prefsKey = 'smart_router.scores';
  static const Duration _probeTimeout = Duration(seconds: 3);

  // 优化 (8/5): 评分落盘节流 — recordResult/getScores 调用频繁 (切台时
  // 每个源一次), 原本每次都全量序列化写 SharedPreferences.  改为 debounce
  // 合并写, 降低 IO 压力; 命中缓存则不写盘.
  static const Duration _saveDebounce = Duration(milliseconds: 1500);
  Map<String, SourceScore>? _pendingSave;
  Timer? _saveTimer;

  /// 获取评分 (从缓存或探测)
  ///
  /// [probeIfStale] 为 false 时, 缓存过期也**不实时探测**, 直接返回过期/默认评分.
  /// 播放路径用 false, 避免切台时阻塞等待 HEAD 探测.
  Future<Map<String, SourceScore>> getScores(
    List<String> urls, {
    bool probeIfStale = true,
  }) async {
    final cached = await _loadCachedScores();
    final now = DateTime.now();
    final result = <String, SourceScore>{};
    var changed = false;

    for (final url in urls) {
      final cachedScore = cached[url];
      if (cachedScore != null) {
        // 有历史记录就用, 不管是否过期 (播放路径不探测)
        result[url] = cachedScore;
      } else if (probeIfStale) {
        // 无缓存且允许探测: 探测一次
        final score = await _probeSource(url);
        result[url] = score;
        changed = true;
      } else {
        // 无缓存且不探测: 用中性默认分, 保持原始顺序
        result[url] = SourceScore(
          url: url,
          score: 0.5,
          latencyMs: 0,
          successCount: 0,
          failCount: 0,
          lastTestedAt: now,
        );
        changed = true;
      }
    }

    // 命中缓存 (无新增) 时不写盘; 有新增则 debounce 合并写.
    if (changed) _scheduleSave(result);
    return result;
  }

  /// 探测单个源
  Future<SourceScore> _probeSource(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      // HEAD 请求测延迟
      final resp = await _client
          .head(Uri.parse(url))
          .timeout(_probeTimeout);
      stopwatch.stop();

      final latencyMs = stopwatch.elapsedMilliseconds;
      final isOk = resp.statusCode >= 200 && resp.statusCode < 400;

      // 计算分数: 延迟越低越好, 成功加分
      double score;
      if (!isOk) {
        score = 0.1;
      } else if (latencyMs < 200) {
        score = 1.0;
      } else if (latencyMs < 500) {
        score = 0.8;
      } else if (latencyMs < 1000) {
        score = 0.6;
      } else if (latencyMs < 2000) {
        score = 0.4;
      } else {
        score = 0.2;
      }

      return SourceScore(
        url: url,
        score: score,
        latencyMs: latencyMs,
        successCount: isOk ? 1 : 0,
        failCount: isOk ? 0 : 1,
        lastTestedAt: DateTime.now(),
      );
    } catch (e) {
      stopwatch.stop();
      return SourceScore(
        url: url,
        score: 0.05,
        latencyMs: _probeTimeout.inMilliseconds,
        successCount: 0,
        failCount: 1,
        lastTestedAt: DateTime.now(),
      );
    }
  }

  /// 按评分排序源列表 (高分在前)
  /// 同分时保持原始顺序 (稳定), 避免无缓存时打乱用户预期的源优先级.
  List<String> rankSources(List<String> urls, Map<String, SourceScore> scores) {
    final sorted = List<String>.from(urls);
    sorted.sort((a, b) {
      final scoreA = scores[a]?.score ?? 0.5;
      final scoreB = scores[b]?.score ?? 0.5;
      if (scoreA == scoreB) return 0; // 保持原始相对顺序
      return scoreB.compareTo(scoreA); // 降序
    });
    return sorted;
  }

  /// 记录播放结果 (成功/失败)
  Future<void> recordResult(String url, bool success) async {
    final cached = await _loadCachedScores();
    final existing = cached[url];

    if (existing == null) {
      // 不在缓存中, 创建新记录
      cached[url] = SourceScore(
        url: url,
        score: success ? 0.6 : 0.3,
        latencyMs: 0,
        successCount: success ? 1 : 0,
        failCount: success ? 0 : 1,
        lastTestedAt: DateTime.now(),
      );
    } else {
      final updated = existing.copyWith(
        successCount: existing.successCount + (success ? 1 : 0),
        failCount: existing.failCount + (success ? 0 : 1),
        score: success
            ? (existing.score + 0.1).clamp(0.0, 1.0)
            : (existing.score - 0.1).clamp(0.0, 1.0),
        lastTestedAt: DateTime.now(),
      );
      cached[url] = updated;
    }

    _scheduleSave(cached);
  }

  /// 清除所有评分缓存
  Future<void> clearCache() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pendingSave = null;
    await _prefs?.remove(_prefsKey);
  }

  Future<Map<String, SourceScore>> _loadCachedScores() async {
    final jsonStr = _prefs?.getString(_prefsKey);
    if (jsonStr == null) return {};
    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, SourceScore.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  /// 调度一次评分写盘 (debounce).  多次调用在 [_saveDebounce] 窗口内合并,
  /// 只落盘一次, 降低切台频繁时的 SharedPreferences 写压力.
  void _scheduleSave(Map<String, SourceScore> scores) {
    _pendingSave ??= <String, SourceScore>{};
    _pendingSave!.addAll(scores); // 后续更新覆盖较早的, 保留窗口内最新值
    _saveTimer ??= Timer(_saveDebounce, _flushSave);
  }

  /// 实际写盘: 合并 prefs 中其它 url, 避免覆盖窗口外已持久化的数据.
  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final pending = _pendingSave;
    _pendingSave = null;
    if (pending == null || _prefs == null) return;
    final existing = await _loadCachedScores();
    existing.addAll(pending); // pending (窗口内最新) 覆盖
    final map = existing.map((k, v) => MapEntry(k, v.toJson()));
    await _prefs.setString(_prefsKey, json.encode(map));
  }

  /// 强制立即写盘 (app 退出 / 生命周期结束时调用, 避免丢失窗口内评分).
  Future<void> flush() async {
    if (_saveTimer != null) await _flushSave();
  }
}

/// 增强版 SourceFailover — 集成智能路由
class SmartSourceFailover extends SourceFailover {
  SmartSourceFailover({
    required super.opener,
    super.perSourceTimeout,
    SmartSourceRouter? router,
  }) : _router = router ?? SmartSourceRouter();

  final SmartSourceRouter _router;

  @override
  Future<String> play(
    List<String> sources, {
    void Function(SourceAttemptEvent event)? onAttempt,
    bool Function()? shouldAbort,
    String? label,
    bool preferSoftwareDecode = false,
  }) async {
    final tag = label != null ? ' ($label)' : '';
    if (sources.isEmpty) {
      await CrashLogger.log('failover: play EMPTY sources$tag');
      throw const AllSourcesFailedException([]);
    }

    // 只有一个源, 直接走
    if (sources.length == 1) {
      if (shouldAbort?.call() ?? false) {
        await CrashLogger.log('failover: ABORTED (single)$tag');
        throw const SourcePlayAbortedException();
      }
      final url = sources.first;
      onAttempt?.call(SourceAttemptEvent(index: 1, total: 1, url: url));
      final ok = await opener.open(
        url,
        timeout: perSourceTimeout,
        preferSoftwareDecode: preferSoftwareDecode,
      );
      if (ok) {
        await _router.recordResult(url, true);
        await CrashLogger.log('failover: single OK$tag url=$url');
        return url;
      }
      await _router.recordResult(url, false);
      await CrashLogger.log('failover: single FAILED$tag url=$url');
      throw AllSourcesFailedException([(url: url, error: 'single source failed')]);
    }

    // 多个源: 用**缓存的**历史评分排序 (不实时探测, 避免切台卡顿)
    // 无缓存的源给中性默认分, 保持原始顺序
    final scores = await _router.getScores(sources, probeIfStale: false);
    final ranked = _router.rankSources(sources, scores);

    await CrashLogger.log('failover: play START ${ranked.length} source(s)$tag');

    final attempts = <({int index, String url, String error})>[];

    for (var i = 0; i < ranked.length; i++) {
      if (shouldAbort?.call() ?? false) {
        await CrashLogger.log('failover: ABORTED before src#${i + 1}$tag');
        throw const SourcePlayAbortedException();
      }
      final url = ranked[i];
      final score = scores[url];
      onAttempt?.call(SourceAttemptEvent(
        index: i + 1,
        total: ranked.length,
        url: '${url.length > 60 ? url.substring(0, 60) : url}... (score: ${score?.score.toStringAsFixed(2) ?? "?"})',
      ));

      try {
        final ok = await opener.open(
          url,
          timeout: perSourceTimeout,
          preferSoftwareDecode: preferSoftwareDecode,
        );
        if (ok) {
          await _router.recordResult(url, true);
          await CrashLogger.log(
              'failover: src#${i + 1}/${ranked.length} OK$tag url=$url');
          return url;
        }
        attempts.add((index: i + 1, url: url, error: 'opener returned false'));
        await _router.recordResult(url, false);
        await CrashLogger.log(
            'failover: src#${i + 1}/${ranked.length} FAILED(opener=false)$tag url=$url');
      } on TimeoutException {
        await opener.cancel(url);
        attempts.add((
          index: i + 1,
          url: url,
          error: 'timeout after ${perSourceTimeout.inMilliseconds}ms',
        ));
        await _router.recordResult(url, false);
        await CrashLogger.log(
            'failover: src#${i + 1}/${ranked.length} TIMEOUT(${perSourceTimeout.inMilliseconds}ms)$tag url=$url');
      } catch (e) {
        await opener.cancel(url);
        attempts.add((index: i + 1, url: url, error: e.toString()));
        await _router.recordResult(url, false);
        await CrashLogger.log(
            'failover: src#${i + 1}/${ranked.length} ERROR: $e$tag url=$url');
      }
    }

    await CrashLogger.log('failover: ALL ${ranked.length} sources FAILED$tag');
    throw AllSourcesFailedException(
      attempts.map((a) => (url: a.url, error: a.error)).toList(growable: false),
    );
  }
}
