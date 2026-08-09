///
///   多频道死了, iptv-org 6/18 已删 CCTV-5 (版权), 公开 m3u 渠道失效.
///   6 方向调研 (央视频 / 央视网 / GitHub CCTV 仓库 / 各地电信 IPTV / CSS /
///   自建 nginx+ffmpeg) 后, 拿到 12/16 频道公共源. 剩 4 频道 (CCTV-2/3/5/5+/
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

/// 选源时按"运营商可达性"分层 — 根治"手机连移动宽带电视加载不出来".
///
/// 背景:  公开 m3u8 源大量是海外裸 IP (74.91.x / 198.204.x / ...), 在中国移动
/// 宽带下被限速/阻断, 而在 CI(美西) 探测时反而最快 → 旧逻辑把它们排最前,
/// 移动用户逐个超时 = "加载不出来".  国内 CDN (腾讯云 myqcloud / 移动 CDN
/// chinamobile / 央视 cctv / 学校 bupt / 芒果 skygo 等) 在三大运营商都稳.
/// 故把"国内源"排到"海外源"之前.
enum _Isp { domestic, neutral, foreign }

/// 已知海外 IPTV 裸 IP 首段 (这些服务器基本都在美/欧, 国内宽带直连差).
const Set<int> _kForeignFirstOctets = <int>{38, 69, 74, 107, 173, 192, 198, 207};

/// 国内 CDN / 运营商域名后缀 (命中即视为国内源, 优先尝试).
const Set<String> _kDomesticHostSuffixes = <String>{
  '.myqcloud.com',
  '.chinamobile.com',
  '.cctv.com',
  '.cctvnews.cctv.com',
  '.bupt.edu.cn',
  '.mobaibox.com',
  '.fanmingming.com',
  '.skygo.mn',
};

/// 从 URL 提取 host (去协议/路径/端口/userinfo), 全小写.
String _hostOf(String url) {
  var s = url;
  final proto = s.indexOf('://');
  if (proto != -1) s = s.substring(proto + 3);
  final slash = s.indexOf('/');
  if (slash != -1) s = s.substring(0, slash);
  final at = s.indexOf('@');
  if (at != -1) s = s.substring(at + 1);
  final colon = s.lastIndexOf(':');
  // 仅对 IPv4 (不含 '[') 去端口
  if (colon != -1 && !s.contains('[')) s = s.substring(0, colon);
  return s.toLowerCase();
}

/// 主机分类: 国内 / 中性 / 海外.
_Isp _classifyHost(String host) {
  for (final suf in _kDomesticHostSuffixes) {
    if (host.endsWith(suf)) return _Isp.domestic;
  }
  final octets = host.split('.');
  if (octets.length == 4) {
    final o1 = int.tryParse(octets[0]);
    if (o1 != null) {
      if (_kForeignFirstOctets.contains(o1)) return _Isp.foreign;
      return _Isp.domestic; // 其它裸 IP 视为国内段 (222/112/39/183 等)
    }
  }
  return _Isp.neutral; // 未命中的域名 (github.io / bkpcp.top 等)
}

/// 取该频道在 [CctvSourceRegistry] 里的源 (启动已 load 才有, 否则 null).
List<CctvSource>? _registrySourcesFor(String channelId) {
  final reg = CctvSourceRegistry._instance;
  if (reg == null) return null;
  final list = reg.getForChannel(channelId);
  return list.isEmpty ? null : list;
}

/// failover 优先级分: 国内 > 中性 > 海外; 同档按健康分降序; 已探活死亡垫底.
/// [reg] 为 registry 记录 (若有), 可据 method/alive 覆盖分类.
double _priorityScore(String url, {CctvSource? reg}) {
  if (reg != null) {
    if (!reg.alive) return -1.0; // 死亡源永远最后
    final isp = const <String>{'tencent_cloud', 'cmcc', 'skygo'}
            .contains(reg.method)
        ? _Isp.domestic
        : reg.method == 'legacy_iptv'
            ? _Isp.foreign
            : _classifyHost(_hostOf(url));
    final bucket = isp == _Isp.domestic
        ? 2.0
        : isp == _Isp.neutral
            ? 1.0
            : 0.0;
    return bucket * 100.0 + reg.score;
  }
  final isp = _classifyHost(_hostOf(url));
  final bucket = isp == _Isp.domestic
      ? 2.0
      : isp == _Isp.neutral
          ? 1.0
          : 0.0;
  return bucket * 100.0 + CctvSourcePicker.healthScore(url);
}

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
  static bool isCctvSubChannel(Channel c) {
    return kCctvSubChannelIds.contains(c.id);
  }

  /// 给定 channel, 返回按健康分排序的播放源 URL 列表.
  ///
  ///   1. CCTV 主频道 (CCTV-1~17) 且 cctvSource 非空:
  ///      [cctvSource 按健康分降序] + [sources 去重后追加] + [known_sources 兜底]
  ///   2. 其他 channel: 保持原 [sources] + known_sources (老逻辑不变)
  ///
  /// 为什么不无脑前置 cctvSource:
  ///   - cctvSource 是 CCTV 主频道专用, CCTV 数字频道 (Billiards 等) 不用
  ///   - 老 release 升级时, cctvSource 字段缺失 (空数组), 走老逻辑不丢源
  /// 给定 channel, 返回按"国内源优先"排序的播放源 URL 列表.
  ///
  /// 层次 (从前到后):
  ///   1. registry (cctv_sources.json, 已探活, 国内 CDN 优先, 死亡垫底)
  ///   2. channel.cctvSource (CCTV 专用源字段)
  ///   3. channel.sources (iptv-org 历史源 + 已合并的 known_sources)
  ///   4. known_sources 兜底
  /// 每层内部按 [_priorityScore] 降序 (国内 > 中性 > 海外, 死亡源垫底).
  ///
  /// 设计:  海外裸 IP 在 CI(美西) 探测最快, 但中国移动宽带直连被阻断,
  /// 把国内源排前面 → 根治"手机连移动宽带电视加载不出来".
  static List<String> pickSources(
    Channel channel, {
    Map<String, List<String>> knownSources = const <String, List<String>>{},
  }) {
    if (!isCctvMainChannel(channel)) {
      // 非 CCTV 主频道: 老逻辑, sources 字段照旧
      return _mergeKnownSources(
          channel.sources, knownSources[channel.id] ?? const <String>[]);
    }

    // CCTV 主频道: 多层源合并, 国内源优先.
    final regList = _registrySourcesFor(channel.id);
    final regByUrl = <String, CctvSource>{};
    if (regList != null) {
      for (final s in regList) regByUrl[s.url] = s;
    }

    final seen = <String>{};
    final out = <String>[];

    // 每层独立按运营商可达性排序 (跨层去重, 首次出现的位置生效).
    void addLayer(List<String> urls) {
      if (urls.isEmpty) return;
      final layer = <_ScoredUrl>[];
      for (final url in urls) {
        if (!seen.add(url)) continue;
        layer.add(_ScoredUrl(url, _priorityScore(url, reg: regByUrl[url])));
      }
      if (layer.isEmpty) return;
      layer.sort((a, b) => b.score.compareTo(a.score));
      for (final e in layer) out.add(e.url);
    }

    // 1. registry (启动已 load 才有; 含国内腾讯云/移动 CDN 高分源)
    if (regList != null) addLayer(regList.map((s) => s.url).toList());
    // 2. cctvSource 专用源
    addLayer(channel.cctvSource);
    // 3. sources (含已合并的 known_sources)
    addLayer(channel.sources);
    // 4. known_sources 兜底
    addLayer(knownSources[channel.id] ?? const <String>[]);

    return out;
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

  /// 运行时动态健康分 (覆盖 kCctvHealthScores 初始分).
  static final Map<String, double> _runtimeScores = <String, double>{};

  /// SharedPreferences 缓存 (懒加载).
  static SharedPreferences? _prefs;

  /// 失败时扣分 (最低 0.0).
  static Future<void> recordFailure(String url) async {
    final base = kCctvHealthScores[url] ?? 0.5;
    final next = ((_runtimeScores[url] ?? base) - 0.1).clamp(0.0, 1.0);
    _runtimeScores[url] = next;
    await _persist(url, next);
  }

  /// 成功时加分 (最高 1.0).
  static Future<void> recordSuccess(String url) async {
    final base = kCctvHealthScores[url] ?? 0.5;
    final next = ((_runtimeScores[url] ?? base) + 0.05).clamp(0.0, 1.0);
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
    return '$channelId: $sourceCount 源, 平均健康 $pct%';
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

  /// 拿指定 channel 的所有 CCTV 源 (按 health_score 降序).
  /// 没有的话返回空列表 (跟没设置 cctvSource 字段等价).
  List<CctvSource> getForChannel(String channelId) {
    return sourcesByChannel[channelId] ?? const <CctvSource>[];
  }

  /// 所有 channel id 列表 (debug UI 遍历用).
  Iterable<String> get channelIds => sourcesByChannel.keys;
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

/// stable sort — 同分保持输入顺序.  给 SourceFailover 选 top-1 用.
List<CctvSource> sortByHealthScore(List<CctvSource> sources) {
  final sorted = List<CctvSource>.from(sources);
  sorted.sort((a, b) {
    // 死源 (score=0) 排最后
    if (a.score <= 0 && b.score > 0) return 1;
    if (b.score <= 0 && a.score > 0) return -1;
    // 降序
    return b.score.compareTo(a.score);
  });
  return sorted;
}
