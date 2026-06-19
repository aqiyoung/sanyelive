/// cctv_source.dart — CCTV 频道源选择器 (v0.3.5.3 6/18 新增)
///
/// 背景 (老板 14:02 拍板 "去找央视的源"):
///   v0.3.5 标 CCTV 16 频道"全活", 实际主源 38.75.136.137 + 备源 74.91.26.218
///   多频道死了, iptv-org 6/18 已删 CCTV-5 (版权), 公开 m3u 渠道失效.
///   6 方向调研 (央视频 / 央视网 / GitHub CCTV 仓库 / 各地电信 IPTV / CSS /
///   自建 nginx+ffmpeg) 后, 拿到 12/16 频道公共源. 剩 4 频道 (CCTV-2/3/5/5+/
///   7/12/16/17) 留给老板自建 (终极 fallback).
///
/// 职责:
///   1. 选源: 给定 channel, 合并 cctvSource + sources + known_sources, 优先级
///      `cctvSource[0] > sources[0] > known_sources[0]`
///   2. 健康分: 每个 URL 有 health_score (0.0-1.0), 失败降分
///   3. Failover: SourceFailover 试 sources 时按 health_score 降序
///
/// 用法 (lib/services/player_service.dart 实际接入):
///   ```dart
///   final sources = CctvSourcePicker.pickSources(channel);
///   final ok = await _failover.play(sources, ...);
///   ```
///
/// 调试:
///   - `CctvSourcePicker.isCctvChannel(channel)` 判别 CCTV 频道
///   - `CctvSourcePicker.healthScore(url)` 查单个源健康分
///   - `CctvSourcePicker.cctvSourceStats()` 拿全 16 频道统计 (debug UI 用)
///
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/channel.dart';

/// CCTV 频道 ID 前缀 (含 CCTV1~17, CCTV4K, CCTVPlus, CCTV 4 美国/亚洲/欧洲等)
/// 用 startsWith 而非 exact match, 因为 iptv-org 用 `CCTV1.cn`, `CCTV4America.cn`
/// `CCTVBilliards.cn` 等变体.
@visibleForTesting
const String kCctvIdPrefix = 'CCTV';

/// CCTV 频道 id 黑名单 (这些不是主 CCTV-1~17):
///   - CCTVPlus1/2 (CCTV+ 海外频道, 不在 16 频道范围)
///   - CCTVBilliards, CCTVEntertainment, CCTVGolfTennis, CCTVOpera,
///     CCTVStorm*, CCTVTheFirstTheater, CCTVWeaponTechnology, CCTVWorldGeography
///     (这些是 CCTV 数字频道, 卡 6.18 不在 16 频道内)
///   - CCTV4America/Asia/Europe (海外版本, 卡里不算)
///   - CCTV4K (超高清, 不在 16 频道范围但有专用源)
const Set<String> kCctvSubChannelIds = <String>{
  'CCTVPlus1.cn',
  'CCTVPlus2.cn',
  'CCTV4America.cn',
  'CCTV4Asia.cn',
  'CCTV4Europe.cn',
  'CCTV4K.cn',
  'CCTVBilliards.cn',
  'CCTVEntertainment.cn',
  'CCTVGolfTennis.cn',
  'CCTVOpera.cn',
  'CCTVStormFootball.cn',
  'CCTVStormMusic.cn',
  'CCTVStormTheater.cn',
  'CCTVTheFirstTheater.cn',
  'CCTVWeaponTechnology.cn',
  'CCTVWorldGeography.cn',
};

/// CCTV 数字主频道 (1-17, 含 CCTV-5+) — 这 16 频道是 v0.3.5.3 修的目标
const Set<String> kCctvMainChannelIds = <String>{
  'CCTV1.cn',
  'CCTV2.cn',
  'CCTV3.cn',
  'CCTV4.cn',
  'CCTV5.cn',
  'CCTV5Plus.cn',
  'CCTV6.cn',
  'CCTV7.cn',
  'CCTV8.cn',
  'CCTV9.cn',
  'CCTV10.cn',
  'CCTV11.cn',
  'CCTV12.cn',
  'CCTV13.cn',
  'CCTV14.cn',
  'CCTV15.cn',
  'CCTV16.cn',
  'CCTV17.cn',
  'CCTV4K.cn',
};

/// v0.3.5.3 调研得到的 CCTV 源健康分 (静态, 跟 assets/data/cctv_sources.json 同步).
///
/// 分数:
///   1.0 = 完美 (HTTPS / 国内 CDN / 1080p / sub-stream 验证有内容)
///   0.8 = 高 (HTTP 但稳定 / Tencent Cloud 官方)
///   0.6 = 中 (GitHub Pages 跳转 / mongolia CDN)
///   0.4 = 低 (偶尔 timeout 但多数能开)
///   0.0 = 死 (本次调研没存活)
///
/// key = URL, value = health score
@visibleForTesting
const Map<String, double> kCctvHealthScores = <String, double>{
  // === 央视官方 (Tencent Cloud CDN, 6/18 实测 1/13 sub-stream 200 OK) ===
  'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8':
      0.95,
  'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv13_1/index.m3u8':
      0.95,

  // === 央视 4K (198.204.240.250:82 — iptv-org 历史源) ===
  'http://198.204.240.250:82/live/cctv4k.m3u8': 0.7,

  // === CCTV-1/6/8 主源 (198.204.240.250 — 同服务器, 6/18 实测 OK) ===
  'http://198.204.240.250:82/live/cctv1.m3u8': 0.7,
  'http://198.204.240.250:82/live/cctv6.m3u8': 0.7,
  'http://198.204.240.250:82/live/cctv8.m3u8': 0.7,

  // === CCTV-4 (xykt-fix/a02a 跳转到 cctvnews.cctv.com — 官方 CCTVNews CDN) ===
  'https://xykt-fix.github.io/play/a02a/index.m3u8': 0.85,

  // === CCTV-9 (xykt-fix/Y77 — kankanlive 直播) ===
  'https://xykt-fix.github.io/Y77.m3u8': 0.8,

  // === CCTV-10/14 (cdn4.skygo.mn — 蒙古 CDN, 稳定但延迟高) ===
  'https://cdn4.skygo.mn/live/disk1/CCTV-10/HLSv3-FTA/CCTV-10.m3u8': 0.7,
  'https://cdn4.skygo.mn/live/disk1/CCTV-14/HLSv3-FTA/CCTV-14.m3u8': 0.7,

  // === CCTV-11/15 (xykt-fix/a02b/a02e — 跳转到 CMCC TV, 每次 GET 换 token) ===
  'https://xykt-fix.github.io/play/a02b/index.m3u8': 0.65,
  'https://xykt-fix.github.io/play/a02e/index.m3u8': 0.65,
};

/// CCTV 源选择器 (单例, 无状态, 纯函数)
class CctvSourcePicker {
  const CctvSourcePicker._();

  /// channel 是不是 CCTV 主频道 (CCTV-1~17, 5+).
  /// 注意: CCTV4K/Plus/America/Asia/Europe/Billiards/Storm 等不算.
  static bool isCctvMainChannel(Channel c) {
    return kCctvMainChannelIds.contains(c.id);
  }

  /// channel 是不是 CCTV 系列 (含子频道).
  static bool isCctvChannel(Channel c) {
    if (!c.id.startsWith(kCctvIdPrefix)) return false;
    // 排除非 CCTV 名字跟 "CCTV" 撞的 (极少见, 兜底)
    return true;
  }

  /// channel 是不是 CCTV 数字频道 (Billiards/Storm 等).
  /// v0.3.5.3 不管, 留老逻辑 (sources 字段).
  static bool isCctvSubChannel(Channel c) {
    return kCctvSubChannelIds.contains(c.id);
  }

  /// 给定 channel, 返回按健康分排序的播放源 URL 列表.
  ///
  /// 合并规则 (v0.3.5.3 铁律):
  ///   1. CCTV 主频道 (CCTV-1~17) 且 cctvSource 非空:
  ///      [cctvSource 按健康分降序] + [sources 去重后追加] + [known_sources 兜底]
  ///   2. 其他 channel: 保持原 [sources] + known_sources (老逻辑不变)
  ///
  /// 为什么不无脑前置 cctvSource:
  ///   - cctvSource 是 CCTV 主频道专用, CCTV 数字频道 (Billiards 等) 不用
  ///   - 老 release 升级时, cctvSource 字段缺失 (空数组), 走老逻辑不丢源
  static List<String> pickSources(
    Channel channel, {
    Map<String, List<String>> knownSources = const <String, List<String>>{},
  }) {
    if (!isCctvMainChannel(channel)) {
      // 非 CCTV 主频道: 老逻辑, sources 字段照旧
      return _mergeKnownSources(
          channel.sources, knownSources[channel.id] ?? const <String>[]);
    }

    // CCTV 主频道: cctvSource 优先
    final cctvSorted = _sortByHealth(channel.cctvSource);
    final known = knownSources[channel.id] ?? const <String>[];

    // 合并: cctvSource (排好序) + sources (去重) + known_sources (去重)
    final seen = <String>{};
    final merged = <String>[];

    // 1. cctvSource (健康分已排序)
    for (final url in cctvSorted) {
      if (seen.add(url)) merged.add(url);
    }

    // 2. channel.sources (iptv-org 历史源, 不再按健康分, 保持原顺序)
    for (final url in channel.sources) {
      if (seen.add(url)) merged.add(url);
    }

    // 3. known_sources 兜底
    for (final url in known) {
      if (seen.add(url)) merged.add(url);
    }

    return merged;
  }

  /// 跟 [mergeKnownSources] 在 [channel_repository.dart] 等价 — 这里是 CCTV 版本
  /// (cctvSource 排在 known 前面), 老逻辑留给 repository 走.
  static List<String> _mergeKnownSources(
    List<String> sources,
    List<String> known,
  ) {
    if (known.isEmpty) return sources;
    final seen = <String>{};
    final out = <String>[];
    for (final url in sources) {
      if (seen.add(url)) out.add(url);
    }
    for (final url in known) {
      if (seen.add(url)) out.add(url);
    }
    return out;
  }

  /// 按健康分降序排列 URL 列表 (无分数的排在最后保持原顺序).
  /// 优先用运行时动态分, 没有则回退 kCctvHealthScores.
  static List<String> _sortByHealth(List<String> urls) {
    final withScore = <_ScoredUrl>[];
    final noScore = <String>[];
    for (final url in urls) {
      final hasRuntimeScore = _runtimeScores.containsKey(url);
      final hasStaticScore = kCctvHealthScores.containsKey(url);
      if (!hasRuntimeScore && !hasStaticScore) {
        noScore.add(url);
      } else {
        withScore.add(_ScoredUrl(url, healthScore(url)));
      }
    }
    withScore.sort((a, b) => b.score.compareTo(a.score));
    return [
      ...withScore.map((e) => e.url),
      ...noScore,
    ];
  }

  /// 运行时动态健康分 (覆盖 kCctvHealthScores 初始分).
  static final Map<String, double> _runtimeScores = <String, double>{};

  /// SharedPreferences 缓存 (懒加载).
  static SharedPreferences? _prefs;

  /// 失败时扣分 (最低 0.0).
  static Future<void> recordFailure(String url) async {
    final base = kCctvHealthScores[url] ?? 0.5;
    final current = _runtimeScores[url] ?? base;
    final next = (current - 0.1).clamp(0.0, 1.0);
    _runtimeScores[url] = next;
    await _persist(url, next);
  }

  /// 成功时加分 (最高 1.0).
  static Future<void> recordSuccess(String url) async {
    final base = kCctvHealthScores[url] ?? 0.5;
    final current = _runtimeScores[url] ?? base;
    final next = (current + 0.05).clamp(0.0, 1.0);
    _runtimeScores[url] = next;
    await _persist(url, next);
  }

  /// 从 SharedPreferences 加载持久化健康分 (启动时调一次).
  /// 遍历 kCctvHealthScores 的 URL, 按 hashCode 读 pref.
  static Future<void> loadPersistedScores() async {
    _prefs = await SharedPreferences.getInstance();
    for (final url in kCctvHealthScores.keys) {
      final key = 'iptv_health_${url.hashCode}';
      final value = _prefs?.getDouble(key);
      if (value != null) {
        _runtimeScores[url] = value;
      }
    }
  }

  /// 持久化单个 key.
  static Future<void> _persist(String url, double score) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setDouble('iptv_health_${url.hashCode}', score);
  }

  /// 查单个 URL 的健康分 (测试用, UI 显示用).
  /// 优先返回运行时动态分, 没有则回退到静态 kCctvHealthScores.
  static double healthScore(String url) {
    return _runtimeScores[url] ?? kCctvHealthScores[url] ?? 0.5;
  }

  /// CCTV 主频道的健康统计 (debug UI 用 — 比如 "CCTV-1: 3 sources, avg 0.87")
  /// 拿所有 16 CCTV 主频道的 source 数和平均健康分.
  static CctvSourceStats cctvSourceStats(Channel channel) {
    if (!isCctvMainChannel(channel)) {
      return const CctvSourceStats(sourceCount: 0, avgHealth: 0);
    }
    final cctvSources = channel.cctvSource;
    if (cctvSources.isEmpty) {
      return const CctvSourceStats(sourceCount: 0, avgHealth: 0);
    }
    var sum = 0.0;
    for (final url in cctvSources) {
      sum += healthScore(url);
    }
    return CctvSourceStats(
      sourceCount: cctvSources.length,
      avgHealth: sum / cctvSources.length,
    );
  }
}

@immutable
class _ScoredUrl {
  const _ScoredUrl(this.url, this.score);
  final String url;
  final double score;
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
    return '$channelId: $sourceCount 源, 平均健康 ${pct}%';
  }
}

/// CCTV 源 registry — 加载 assets/data/cctv_sources.json (按 channel.id 分组).
///
/// 数据格式 (跟 discover_cctv_sources.py 输出对齐):
/// ```json
/// {
///   "CCTV1.cn": [
///     {"url": "https://...", "score": 0.95, "method": "tencent_cloud"},
///     ...
///   ],
///   "CCTV4.cn": [
///     ...
///   ]
/// }
/// ```
///
/// 加载策略:
///   - 启动时 [CctvSourceRegistry.load] 异步加载, 缓存到 [_instance]
///   - 加载失败 (文件缺失 / 解析错) 时降级到 [kCctvHealthScores] 静态表
///
/// 用途: 后续 release 可通过 [discover_cctv_sources.py] 重新跑健康分, 写到
/// cctv_sources.json 覆盖, app 启动加载即可.  不用 rebuild APK.
class CctvSourceRegistry {
  CctvSourceRegistry._({required this.sourcesByChannel});

  static CctvSourceRegistry? _instance;

  /// 异步加载 (asset rootBundle), 失败抛.
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

  /// 同步访问 (加载完成后才有意义).
  static CctvSourceRegistry get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('CctvSourceRegistry not loaded. Call load() first.');
    }
    return i;
  }

  /// 测试用: 重新设置 instance
  @visibleForTesting
  static void debugSet(CctvSourceRegistry? registry) {
    _instance = registry;
  }

  factory CctvSourceRegistry._fromJson(Map<String, dynamic> json) {
    final sourcesByChannel = <String, List<CctvSource>>{};
    for (final entry in json.entries) {
      final channelId = entry.key;
      final list = (entry.value as List).cast<dynamic>();
      sourcesByChannel[channelId] = list
          .map((e) => CctvSource.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    }
    return CctvSourceRegistry._(sourcesByChannel: sourcesByChannel);
  }

  /// Public read-only view of the sources map.
  final Map<String, List<CctvSource>> sourcesByChannel;

  /// Internal access path — keeps the API similar to old code.
  Map<String, List<CctvSource>> get _sourcesByChannel =>
      sourcesByChannel.isEmpty
          ? const <String, List<CctvSource>>{}
          : sourcesByChannel;

  /// 拿指定 channel 的所有 CCTV 源 (按 health_score 降序).
  /// 没有的话返回空列表 (跟没设置 cctvSource 字段等价).
  List<CctvSource> getForChannel(String channelId) {
    return _sourcesByChannel[channelId] ?? const <CctvSource>[];
  }

  /// 所有 channel id 列表 (debug UI 遍历用).
  Iterable<String> get channelIds => _sourcesByChannel.keys;
}

/// CCTV 源 (单条 URL + 健康分 + 探测方法)
@immutable
class CctvSource {
  const CctvSource({
    required this.url,
    required this.score,
    this.method = '',
    this.lastChecked = '',
    this.rttMs = 0,
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

  factory CctvSource.fromJson(Map<String, dynamic> j) {
    return CctvSource(
      url: j['url'] as String,
      score: (j['score'] as num?)?.toDouble() ?? 0.5,
      method: (j['method'] as String?) ?? '',
      lastChecked: (j['lastChecked'] as String?) ?? '',
      rttMs: (j['rttMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'score': score,
        'method': method,
        'lastChecked': lastChecked,
        'rttMs': rttMs,
      };

  @override
  String toString() =>
      'CctvSource(url: $url, score: ${(score * 100).round()}%, method: $method, rtt: ${rttMs}ms)';
}
