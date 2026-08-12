import 'package:flutter/foundation.dart';

/// CCTV 单条播放源: URL + 健康分 + 探测方法。
@immutable
class CctvSource {
  const CctvSource({
    required this.url,
    required this.score,
    this.method = '',
    this.lastChecked = '',
    this.rttMs = 0,
    this.alive = true,
  });

  final String url;

  /// 0.0-1.0 健康分
  final double score;

  /// 探测方法 (e.g. "tencent_cloud", "skygo", "xykt_fix", "cmcc")
  final String method;

  /// ISO 8601 last checked 时间
  final String lastChecked;

  /// 首屏 RTT (毫秒)
  final int rttMs;

  /// 探活结果: false = 上次探测已死 (failover 时垫底)
  final bool alive;

  factory CctvSource.fromJson(Map<String, dynamic> j) {
    return CctvSource(
      url: j['url'] as String,
      score: (j['score'] as num?)?.toDouble() ?? 0.5,
      method: (j['method'] as String?) ?? '',
      lastChecked: (j['lastChecked'] as String?) ?? '',
      rttMs: (j['rttMs'] as num?)?.toInt() ?? 0,
      alive: (j['alive'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'score': score,
        'method': method,
        'lastChecked': lastChecked,
        'rttMs': rttMs,
        'alive': alive,
      };

  @override
  String toString() =>
      'CctvSource(url: $url, score: ${(score * 100).round()}%, method: $method, rtt: ${rttMs}ms)';
}

/// CCTV 源健康统计 (UI 展示用)
@immutable
class CctvSourceStats {
  const CctvSourceStats({
    required this.sourceCount,
    required this.avgHealth,
  });
  final int sourceCount;
  final double avgHealth;

  /// UI 文案: "CCTV-1: 3 源, 平均健康 0.87"
  String describe(String channelId) {
    if (sourceCount == 0) {
      return '$channelId: 无验证源 (标 "全活" 但本次未测到)';
    }
    final pct = (avgHealth * 100).round();
    return '$channelId: $sourceCount 源, 平均健康 $pct%';
  }
}

/// 按健康分(降序)对 CCTV 源排序; 同分保持稳定顺序 (stable sort).
///
/// 原为 [cctv_source.dart] 顶层函数, 模块化拆分 (+187) 时被漏带,
/// 这里收归到模型层. [CctvSourcePicker] 内部按 URL 健康分选源,
/// 此函数按 [CctvSource.score] 字段排序, 用于单测与显式预排序.
List<CctvSource> sortByHealthScore(List<CctvSource> sources) {
  final indexed = sources.asMap().entries.toList();
  indexed.sort((a, b) {
    final cmp = b.value.score.compareTo(a.value.score);
    if (cmp != 0) return cmp;
    return a.key.compareTo(b.key); // 同分保序
  });
  return indexed.map((e) => e.value).toList();
}
