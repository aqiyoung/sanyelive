//
// TVBox 配置解析器 — 兼容 TVBox 顶层格式:
//   { spider, sites[], lives[], rules[], parses[], urls[] }
//
// 我们只取两类可直连的内容:
//   - sites[] 中 type == 1 (MacCMS JSON API)  → 转 VodSource (影视点播)
//   - lives[] 中直播频道 (内联 channels[] 或 lives[].url 指向的 m3u/JSON)
//       → 转 TvBoxLiveChannel (直播), 并进现有直播 SourceFailover 管线
//
// 关键设计:
//   - lives[].url 可能是指向 m3u 播放列表 / JSON 频道表的链接, 直接复用
//     ChannelFormatRegistry (已支持 m3u + iptv-org json) 解析, 不重复造轮子.
//   - urls[] 是"多仓订阅", 递归拉取 (bounded, 去重) 实现"一个接口聚合多源".
//   - 手动导入: 上层传入用户粘贴的接口链接 (urls 参数), 不再只用内置 4 个 URL.
//
// 容错: 单个 URL 拉取失败 / 超时 / 非 JSON / 无有效内容 → 跳过该 URL (不抛错),
// 返回其他 URL 解析成功的. 跟 app 现有 IPv4 / 远程容错一致.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/format/format_registry.dart' show ChannelFormatRegistry;
import '../data/models/vod_source.dart';
import 'vod_parse_service.dart' show TvBoxParseRule;

const List<String> kTvBoxSourceUrls = [
  'https://9280.kstore.space/wex.json',
  'https://dxawi.github.io/0/0.json',
  'https://raw.liucn.cc/box/m.json',
  'https://github.com/YuanHsing/freed/raw/master/TVBox/meow.json',
];

/// 单 URL 拉取超时.
const Duration kTvBoxFetchTimeout = Duration(seconds: 15);

/// 多仓递归最大跟随深度 (防爆炸).
const int kTvBoxMaxSubUrls = 50;

/// 单条 TVBox 直播频道 (lives[].channels[] 或 lives[].url 解析出的频道).
class TvBoxLiveChannel {
  const TvBoxLiveChannel({
    required this.name,
    required this.urls,
    this.logoUrl,
  });

  final String name;
  final List<String> urls;
  final String? logoUrl;

  factory TvBoxLiveChannel.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] as String?)?.trim() ?? '';
    final urls = <String>[];
    final rawUrls = j['urls'];
    if (rawUrls is String) {
      final u = rawUrls.trim();
      if (u.isNotEmpty) urls.add(u);
    } else if (rawUrls is List) {
      for (final u in rawUrls) {
        if (u is String && u.trim().isNotEmpty) urls.add(u.trim());
      }
    }
    final logo = (j['logo'] as String?)?.trim();
    return TvBoxLiveChannel(
      name: name,
      urls: urls,
      logoUrl: logo != null && logo.isNotEmpty ? logo : null,
    );
  }
}

/// 一组 TVBox 直播频道 (lives[] 的一个元素 = 一个分组).
class TvBoxLiveGroup {
  const TvBoxLiveGroup({
    required this.name,
    required this.channels,
  });

  final String name;
  final List<TvBoxLiveChannel> channels;
}

/// 解析后的完整 TVBox 配置 (影视源 + 直播源 + 解析规则).
class TvBoxConfig {
  const TvBoxConfig({
    this.vodSources = const [],
    this.liveGroups = const [],
    this.parseRules = const [],
  });

  final List<VodSource> vodSources;
  final List<TvBoxLiveGroup> liveGroups;
  final List<TvBoxParseRule> parseRules;

  int get liveChannelCount =>
      liveGroups.fold(0, (sum, g) => sum + g.channels.length);
}

/// 单个 URL 解析出的局部配置 (便于多仓递归聚合).
class _PartialConfig {
  const _PartialConfig({
    this.vodSources = const [],
    this.liveGroups = const [],
    this.subUrls = const [],
    this.parseRules = const [],
  });
  final List<VodSource> vodSources;
  final List<TvBoxLiveGroup> liveGroups;
  final List<String> subUrls;
  final List<TvBoxParseRule> parseRules;
}

class TvBoxConfigParser {
  TvBoxConfigParser({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// 拉取 TVBox 配置, 解析出 type:1 MacCMS 站点 + 直播频道.
  /// 支持 [urls] 手动传入 (用户粘贴的接口链接) 与多仓递归 (urls 字段).
  /// 失败 URL 静默跳过, 返回其他 URL 解析成功的聚合结果.
  Future<TvBoxConfig> fetchTvBoxConfig({
    List<String> urls = kTvBoxSourceUrls,
  }) async {
    final vod = <String, VodSource>{}; // host → source (去重)
    final liveGroups = <TvBoxLiveGroup>[];
    final parseRules = <String, TvBoxParseRule>{}; // name → rule (去重)
    final seen = <String>{};
    final queue = List<String>.from(urls);

    var followed = 0;
    while (queue.isNotEmpty && followed < kTvBoxMaxSubUrls) {
      final url = queue.removeAt(0);
      if (!seen.add(url)) continue; // 同 URL 只处理一次
      followed++;
      final partial = await _fetchOne(url);
      for (final s in partial.vodSources) {
        if (s.baseUrl.isEmpty) continue;
        final host = s.host;
        if (!vod.containsKey(host)) vod[host] = s; // 同 host 留第一个
      }
      liveGroups.addAll(partial.liveGroups);
      for (final r in partial.parseRules) {
        parseRules[r.name] = r; // 同名覆盖
      }
      // 跟多仓订阅 (urls 字段) — 入队递归拉取.
      for (final u in partial.subUrls) {
        if (!seen.contains(u)) queue.add(u);
      }
    }

    return TvBoxConfig(
      vodSources: vod.values.toList(),
      liveGroups: liveGroups,
      parseRules: parseRules.values.toList(),
    );
  }

  /// 兼容旧调用 — 只返回影视源 (type:1). 内部走统一解析.
  Future<List<VodSource>> fetchTvBoxSources({
    List<String> urls = kTvBoxSourceUrls,
  }) async {
    final cfg = await fetchTvBoxConfig(urls: urls);
    return cfg.vodSources;
  }

  /// 拉取单个 URL → 局部配置 (sites + lives + subUrls).
  Future<_PartialConfig> _fetchOne(String url) async {
    try {
      final body = await _fetchRaw(url);
      if (body == null) return const _PartialConfig();
      final cleaned = _stripComments(body);
      final decoded = json.decode(cleaned);
      if (decoded is! Map<String, dynamic>) return const _PartialConfig();

      final vodSources = await _parseSites(decoded);
      final liveGroups = await _parseLives(decoded);
      final subUrls = _parseSubUrls(decoded);
      final parseRules = _parseParses(decoded);

      debugPrint(
          'TvBoxParser: $url → ${vodSources.length} vod, '
          '${liveGroups.fold(0, (s, g) => s + g.channels.length)} live, '
          '${subUrls.length} sub, ${parseRules.length} parse');
      return _PartialConfig(
        vodSources: vodSources,
        liveGroups: liveGroups,
        subUrls: subUrls,
        parseRules: parseRules,
      );
    } catch (e) {
      debugPrint('TvBoxParser: $url fetch failed: $e');
      return const _PartialConfig();
    }
  }

  /// 解析 sites[] → type:1 MacCMS 站点 (VodSource). 自动检测 typeId 方案.
  Future<List<VodSource>> _parseSites(Map<String, dynamic> decoded) async {
    final sites = decoded['sites'];
    if (sites is! List) return const [];

    final result = <VodSource>[];
    for (final site in sites) {
      if (site is! Map<String, dynamic>) continue;
      // 只取 type:1 (MacCMS JSON API). type:2/3 是 JS spider, 跳过.
      final type = site['type'];
      if (type is! int || type != 1) continue;
      final api = (site['api'] as String?)?.trim() ?? '';
      if (api.isEmpty) continue;
      final rawName = (site['name'] as String?)?.trim() ?? '';
      if (rawName.isEmpty) continue;
      final name = VodSource.cleanName(rawName);
      String host;
      try {
        host = Uri.parse(api).host;
      } catch (_) {
        host = 'tvbox';
      }
      final detected = await _detectTypeIds(api);
      // sites[].parse 引用 parses[].name — 非空时播放地址需解析.
      final parseKey = (site['parse'] as String?)?.trim();
      result.add(VodSource(
        id: '${host}_${result.length}',
        name: name,
        baseUrl: api,
        typeIds: detected ?? bfzyapiTypeIds,
        parseKey: (parseKey != null && parseKey.isNotEmpty) ? parseKey : null,
      ));
    }
    return result;
  }

  /// 解析 parses[] → 解析规则列表 (TVBox 规范: name/type/url).
  List<TvBoxParseRule> _parseParses(Map<String, dynamic> decoded) {
    final parses = decoded['parses'];
    if (parses is! List) return const [];
    final out = <TvBoxParseRule>[];
    for (final p in parses) {
      if (p is! Map<String, dynamic>) continue;
      final rule = TvBoxParseRule.fromJson(p);
      if (rule != null) out.add(rule);
    }
    return out;
  }

  /// 解析 lives[] → 直播分组 (内联 channels[] + lives[].url 指向的 m3u/JSON).
  Future<List<TvBoxLiveGroup>> _parseLives(Map<String, dynamic> decoded) async {
    final lives = decoded['lives'];
    if (lives is! List) return const [];

    final groups = <TvBoxLiveGroup>[];
    for (final g in lives) {
      if (g is! Map<String, dynamic>) continue;
      final gName = (g['name'] as String?)?.trim() ?? '直播';
      final channels = <TvBoxLiveChannel>[];

      // 1) 内联 channels[]
      final chList = g['channels'];
      if (chList is List) {
        for (final c in chList) {
          if (c is! Map<String, dynamic>) continue;
          final ch = TvBoxLiveChannel.fromJson(c);
          if (ch.name.isEmpty) continue;
          // urls 全部是 proxy 列表代理 → 解码真实列表 URL, 走 _parseLiveUrl 展开
          final listProxies = ch.urls
              .map((u) => decodeTvBoxProxy(u))
              .whereType<String>()
              .toList();
          if (ch.urls.isNotEmpty && listProxies.length == ch.urls.length) {
            for (final lu in listProxies) {
              channels.addAll(await _parseLiveUrl('$gName/${ch.name}', lu));
            }
            continue;
          }
          if (ch.urls.isNotEmpty) channels.add(ch);
        }
      }

      // 2) lives[].url → 拉取 m3u / JSON (复用 ChannelFormatRegistry)
      final url = (g['url'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        final sub = await _parseLiveUrl(gName, url);
        channels.addAll(sub);
      }

      if (channels.isNotEmpty) {
        groups.add(TvBoxLiveGroup(name: gName, channels: channels));
      }
    }
    return groups;
  }

  /// 解码 TVBox proxy:// 协议.
  ///
  /// 仅支持 type=txt/m3u/json 的"直播列表代理" (如
  /// `proxy://do=live&type=txt&ext=<base64>`), 返回真实列表 URL (供 parser
  /// 再次 fetch + 解析). 单流代理 (type=m3u8 等) 返回 null — 本 app 播放链路
  /// 不认 proxy:// 协议. 解析失败 / 非 proxy 返回 null.
  String? decodeTvBoxProxy(String proxyUrl) {
    if (!proxyUrl.startsWith('proxy://')) return null;
    final q = proxyUrl.substring('proxy://'.length);
    final params = <String, String>{};
    for (final seg in q.split('&')) {
      final idx = seg.indexOf('=');
      if (idx < 0) continue;
      params[seg.substring(0, idx)] =
          Uri.decodeComponent(seg.substring(idx + 1));
    }
    final type = params['type'] ?? '';
    final ext = params['ext'];
    if (ext == null || ext.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Decode(ext));
      if (type == 'txt' || type == 'm3u' || type == 'json') return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 解析单个 lives[].url (m3u / JSON / TVBox live.txt 频道表) → 直播频道.
  /// url 为 proxy:// 列表代理时先解码出真实列表 URL 再递归.
  Future<List<TvBoxLiveChannel>> _parseLiveUrl(String groupName, String url) async {
    if (url.startsWith('proxy://')) {
      final real = decodeTvBoxProxy(url);
      if (real == null) return const [];
      return _parseLiveUrl(groupName, real);
    }
    try {
      final body = await _fetchRaw(url);
      if (body == null) return const [];
      final channels = ChannelFormatRegistry.instance.parse(body);
      return channels
          .where((c) => c.sources.isNotEmpty)
          .map((c) => TvBoxLiveChannel(
                name: c.displayName,
                urls: c.sources,
                logoUrl: c.logoUrl,
              ))
          .toList();
    } catch (e) {
      debugPrint('TvBoxParser: lives url $url parse failed: $e');
      return const [];
    }
  }

  /// 解析多仓订阅 urls 字段 (string 或 list).
  List<String> _parseSubUrls(Map<String, dynamic> decoded) {
    final sub = decoded['urls'];
    final out = <String>[];
    if (sub is String && sub.trim().isNotEmpty) {
      out.add(sub.trim());
    } else if (sub is List) {
      for (final u in sub) {
        if (u is String && u.trim().isNotEmpty) out.add(u.trim());
      }
    }
    return out;
  }

  /// 自动检测 typeId 方案: 拉取 class 列表, 匹配中文分类名.
  /// 返回 null 表示检测失败 (fallback 到 bfzyapiTypeIds).
  Future<Map<String, int>?> _detectTypeIds(String baseUrl) async {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        'ac': 'list',
        't': '1',
        'pg': '1',
        'pagesize': '1',
      });
      final resp = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final cleaned = _stripComments(resp.body);
      final decoded = json.decode(cleaned);
      if (decoded is! Map<String, dynamic>) return null;
      final classes = decoded['class'];
      if (classes is! List) return null;

      // 常见中文分类名 → app category key 映射.
      final categoryKeywords = <String, List<String>>{
        'movie': ['电影', '电影片', '电影'],
        'series': ['连续剧', '电视剧', '剧集', '电视剧'],
        'variety': ['综艺', '综艺片', '综艺节目'],
        'anime': ['动漫', '动漫片', '动画片', '动画'],
        'documentary': ['纪录片', '纪录', '记录片'],
        'sports': ['体育', '体育赛事', '体育节目'],
        'overseas': ['海外', '欧美剧', '海外剧', '海外看'],
      };

      final result = <String, int>{};
      for (final entry in classes) {
        if (entry is! Map<String, dynamic>) continue;
        final typeId = entry['type_id'] is int
            ? entry['type_id'] as int
            : (entry['type_id'] as num?)?.toInt();
        final typeName = (entry['type_name'] as String?) ?? '';
        if (typeId == null || typeName.isEmpty) continue;

        for (final cat in categoryKeywords.entries) {
          if (result.containsKey(cat.key)) continue; // 已有匹配
          for (final kw in cat.value) {
            if (typeName.contains(kw)) {
              result[cat.key] = typeId;
              break;
            }
          }
        }
      }

      debugPrint('TvBoxParser: typeId detected for $baseUrl → $result');
      return result.isNotEmpty ? result : null;
    } catch (e) {
      debugPrint('TvBoxParser: typeId detection failed for $baseUrl: $e');
      return null;
    }
  }

  /// GET 一个 URL → 响应体 (失败返回 null).
  Future<String?> _fetchRaw(String url) async {
    try {
      final resp =
          await _client.get(Uri.parse(url)).timeout(kTvBoxFetchTimeout);
      if (resp.statusCode != 200) {
        debugPrint('TvBoxParser: $url → HTTP ${resp.statusCode}, skip');
        return null;
      }
      return resp.body;
    } catch (e) {
      debugPrint('TvBoxParser: $url GET failed: $e');
      return null;
    }
  }

  /// 去掉 JSON 前导的 //xxx 和 #xxx 注释行 (m.json 第一行有 // 中文注释).
  String _stripComments(String raw) {
    final lines = raw.split('\n');
    final buf = StringBuffer();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('#')) continue;
      buf.writeln(line);
    }
    return buf.toString();
  }

  void dispose() {
    _client.close();
  }
}

void debugPrint(String msg) {
  // ignore: avoid_print
  print(msg);
}
