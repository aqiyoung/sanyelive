import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cctv_source_model.dart';
import 'cctv_source_registry.dart';
import 'models/channel.dart';

/// CCTV 源选择器: 给定频道, 按"国内源优先 + 健康分降序"返回候选播放源 URL。
///
/// 背景: 公开 m3u8 大量是海外裸 IP, 在中国移动宽带下被限速/阻断; 而国内 CDN
/// (腾讯云 myqcloud / 移动 CDN / 央视 cctv / 芒果 skygo) 在三大运营商都稳。
/// 故选源时把国内源排到海外源之前, 根治"手机连移动宽带电视加载不出来"。

/// CCTV 频道 ID 前缀 (含 CCTV1~17, CCTV4K, CCTVPlus, CCTV 4 美国/亚洲/欧洲等)
const String kCctvIdPrefix = 'CCTV';

/// CCTV 频道 id 黑名单 (这些不是主 CCTV-1~17)
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

/// 每个 URL 健康分 (0.0-1.0), 失败降分。数值由 discover_cctv_sources.py 实测。
const Map<String, double> kCctvHealthScores = <String, double>{
  // 央视官方 (Tencent Cloud CDN, 6/18 实测 sub-stream 200 OK)
  'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8':
      0.95,
  'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv13_1/index.m3u8':
      0.95,
  // 央视 4K (198.204.240.250:82 — iptv-org 历史源)
  'http://198.204.240.250:82/live/cctv4k.m3u8': 0.7,
  // CCTV-1/6/8 主源 (198.204.240.250 — 同服务器, 6/18 实测 OK)
  'http://198.204.240.250:82/live/cctv1.m3u8': 0.7,
  'http://198.204.240.250:82/live/cctv6.m3u8': 0.7,
  'http://198.204.240.250:82/live/cctv8.m3u8': 0.7,
  // CCTV-4 (xykt-fix/a02a 跳转到 cctvnews.cctv.com — 官方 CCTVNews CDN)
  'https://xykt-fix.github.io/play/a02a/index.m3u8': 0.85,
  // CCTV-9 (xykt-fix/Y77 — kankanlive 直播)
  'https://xykt-fix.github.io/Y77.m3u8': 0.8,
  // CCTV-10/14 (cdn4.skygo.mn — 蒙古 CDN, 稳定但延迟高)
  'https://cdn4.skygo.mn/live/disk1/CCTV-10/HLSv3-FTA/CCTV-10.m3u8': 0.7,
  'https://cdn4.skygo.mn/live/disk1/CCTV-14/HLSv3-FTA/CCTV-14.m3u8': 0.7,
  // CCTV-11/15 (xykt-fix/a02b/a02e — 跳转到 CMCC TV, 每次 GET 换 token)
  'https://xykt-fix.github.io/play/a02b/index.m3u8': 0.65,
  'https://xykt-fix.github.io/play/a02e/index.m3u8': 0.65,
};

/// 从 URL 提取 host (去协议/路径/端口/userinfo), 全小写。
String _hostOf(String url) {
  var s = url;
  final proto = s.indexOf('://');
  if (proto != -1) s = s.substring(proto + 3);
  final slash = s.indexOf('/');
  if (slash != -1) s = s.substring(0, slash);
  final at = s.indexOf('@');
  if (at != -1) s = s.substring(at + 1);
  final colon = s.lastIndexOf(':');
  if (colon != -1 && !s.contains('[')) s = s.substring(0, colon);
  return s.toLowerCase();
}

enum _Isp { domestic, neutral, foreign }

/// 已知海外 IPTV 裸 IP 首段 (美/欧, 国内宽带直连差)
const Set<int> _kForeignFirstOctets = <int>{38, 69, 74, 107, 173, 192, 198, 207};

/// 国内 CDN / 运营商域名后缀 (命中即视为国内源, 优先尝试)
const Set<String> _kDomesticHostSuffixes = <String>{
  '.myqcloud.com',
  '.chinamobile.com',
  '.cctv.com',
  '.cctvnews.cctv.com',
  '.bupt.edu.cn',
  '.mobaibox.com',
  '.fanmingming.com',
};

/// 明确的海外域名后缀 (国内直连慢或不稳, 排到最后兜底)
const Set<String> _kForeignHostSuffixes = <String>{
  '.skygo.mn',
  '.github.io',
};

/// 主机分类: 国内 / 中性 / 海外。
_Isp _classifyHost(String host) {
  for (final suf in _kDomesticHostSuffixes) {
    if (host.endsWith(suf)) return _Isp.domestic;
  }
  for (final suf in _kForeignHostSuffixes) {
    if (host.endsWith(suf)) return _Isp.foreign;
  }
  final octets = host.split('.');
  if (octets.length == 4) {
    final o1 = int.tryParse(octets[0]);
    if (o1 != null) {
      if (_kForeignFirstOctets.contains(o1)) return _Isp.foreign;
      return _Isp.domestic; // 其它裸 IP 视为国内段
    }
  }
  return _Isp.neutral;
}

/// 取该频道在 [CctvSourceRegistry] 里的源 (启动已 load 才有, 否则 null)。
List<CctvSource>? _registrySourcesFor(String channelId) {
  final reg = CctvSourceRegistry.instanceOrNull;
  if (reg == null) return null;
  final list = reg.getForChannel(channelId);
  return list.isEmpty ? null : list;
}

/// failover 优先级分: 国内 > 中性 > 海外; 同档按健康分降序; 已探活死亡垫底。
double _priorityScore(String url, {CctvSource? reg}) {
  if (reg != null) {
    if (!reg.alive) return -1.0; // 死亡源永远最后
    // 只按 host 分类, 不信 registry 的 method 标签 —— 标签不可靠:
    // method="cmcc" 实际指向 GitHub Pages, method="skygo" 是蒙古 CDN。
    final isp = _classifyHost(_hostOf(url));
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

@immutable
class _ScoredUrl {
  const _ScoredUrl(this.url, this.score);
  final String url;
  final double score;
}

/// CCTV 源选择器 (单例, 无状态, 纯函数)
class CctvSourcePicker {
  const CctvSourcePicker._();

  static bool isCctvMainChannel(Channel c) {
    return kCctvMainChannelIds.contains(c.id);
  }

  static bool isCctvChannel(Channel c) {
    if (!c.id.startsWith(kCctvIdPrefix)) return false;
    return true;
  }

  static bool isCctvSubChannel(Channel c) {
    return kCctvSubChannelIds.contains(c.id);
  }

  /// 央视腾讯云源改写: 仅对 **CCTV-1 / CCTV-13** 改写为 720p 渐进子码流
  /// (`.../cdrmldcctvN_1_td.m3u8`)。
  ///
  /// 关键事实(6/18 调研 + 8/19 复测双重确认): 腾讯云 `ldncctvwbcd` CDN 的
  /// `index.m3u8` 对全部 CCTV1~17 + 5+ 都返回 200, 但其 **sub-stream 仅 CCTV-1/13
  /// 真实存在**(`_td`=1280x720 渐进)。CCTV2~17 的 master 虽 200, 但指向的
  /// `_hd`/`_td` 子码流在 CDN 上 **404** —— 若一刀切把全部频道改写成 `_td.m3u8`,
  /// 会制造一堆 404 死链("资源有问题" 的根因之一)。故:
  ///   - 仅 CCTV-1/13 改写 `_td`(720p 渐进, 与卫视同构, 不花屏且更快);
  ///   - 其余腾讯云 URL 保持 `index.m3u8` 原样(由播放器从 master 选码流), 不臆造 404。
  /// 仅匹配腾讯云央视专属路径, 其它源(卫视/其它 CDN)原样返回, 不误伤。
  static const Set<String> _kTencentRewritableTokens = <String>{
    'cdrmldcctv1_1',
    'cdrmldcctv13_1',
  };

  static String _rewriteCctvTencent720p(String url) {
    final u = url.trim();
    final m = RegExp(
      r'^(https?://[^\s]+?/ldncctvwbcd/)(cdrmldcctv(?:5plus|\d+)_1)/index\.m3u8$',
    ).firstMatch(u);
    if (m == null) return u;
    final token = m.group(2)!;
    if (!_kTencentRewritableTokens.contains(token)) return u; // 2~17: 保持 master, 避免 404
    return '${m.group(1)}$token' '_td.m3u8';
  }

  /// 给定 channel, 返回按"国内源优先"排序的播放源 URL 列表。
  ///
  /// 层次 (从前到后):
  ///   1. registry (cctv_sources.json, 已探活, 国内 CDN 优先, 死亡垫底)
  ///   2. channel.cctvSource (CCTV 专用源字段)
  ///   3. channel.sources (iptv-org 历史源 + 已合并的 known_sources)
  ///   4. known_sources 兜底
  /// 每层内部按 [_priorityScore] 降序 (国内 > 中性 > 海外, 死亡源垫底)。
  static List<String> pickSources(
    Channel channel, {
    Map<String, List<String>> knownSources = const <String, List<String>>{},
  }) {
    if (!isCctvMainChannel(channel)) {
      return _mergeKnownSources(
          channel.sources, knownSources[channel.id] ?? const <String>[]);
    }

    final regList = _registrySourcesFor(channel.id);
    final regByUrl = <String, CctvSource>{};
    if (regList != null) {
      for (final s in regList) regByUrl[s.url] = s;
    }

    final seen = <String>{};
    final out = <String>[];

    void addLayer(List<String> urls) {
      if (urls.isEmpty) return;
      final layer = <_ScoredUrl>[];
      for (final url in urls) {
        // 腾讯云央视源改写为 720p 渐进子码流(避免拉 1080i 主码流 → 花屏+慢加载)
        final rewritten = _rewriteCctvTencent720p(url);
        if (!seen.add(rewritten)) continue;
        // 回查 reg: 用原始 url 的探活信息(改写后 host 不变, 分类一致)
        final reg = regByUrl[url] ?? regByUrl[rewritten];
        layer.add(_ScoredUrl(rewritten, _priorityScore(rewritten, reg: reg)));
      }
      if (layer.isEmpty) return;
      layer.sort((a, b) => b.score.compareTo(a.score));
      for (final e in layer) out.add(e.url);
    }

    if (regList != null) addLayer(regList.map((s) => s.url).toList());
    addLayer(channel.cctvSource);
    addLayer(channel.sources);
    addLayer(knownSources[channel.id] ?? const <String>[]);

    return out;
  }

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

  /// 运行时动态健康分 (覆盖 kCctvHealthScores 初始分)
  static final Map<String, double> _runtimeScores = <String, double>{};

  static SharedPreferences? _prefs;

  static Future<void> recordFailure(String url) async {
    final base = kCctvHealthScores[url] ?? 0.5;
    final next = ((_runtimeScores[url] ?? base) - 0.1).clamp(0.0, 1.0);
    _runtimeScores[url] = next;
    await _persist(url, next);
  }

  static Future<void> recordSuccess(String url) async {
    final base = kCctvHealthScores[url] ?? 0.5;
    final next = ((_runtimeScores[url] ?? base) + 0.05).clamp(0.0, 1.0);
    _runtimeScores[url] = next;
    await _persist(url, next);
  }

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

  static Future<void> _persist(String url, double score) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setDouble('iptv_health_${url.hashCode}', score);
  }

  static double healthScore(String url) {
    return _runtimeScores[url] ?? kCctvHealthScores[url] ?? 0.5;
  }

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
