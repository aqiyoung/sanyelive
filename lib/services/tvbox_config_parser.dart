//
// 这 4 个 URL 是行业公开的 TVBox / 影视聚合配置 (俗称 "盒子源"):
//   - TVBox 格式顶层 { spider, sites[], lives[], rules[], parses[] }
//   - sites[] 每个站点 { key, name, type, api, searchable, ... }
//   - type:  1 = MacCMS JSON API (直接 ac=list/detail,  我们的 VodApiService
//               能直接用),  2/3 = Spider JS 采集 (需 JS 引擎,  Flutter 跑不了)
//
// 我们只取 type == 1 且 api 非空的站点,  转成 VodSource.
//
// 常见中文分类名 (电影/连续剧/综艺/动漫/纪录片/体育/海外),  映射到 app 的
// category keys.  检测失败则 fallback 到 bfzyapiTypeIds.
//
// 容错:  单个 URL 拉取失败 / 超时 / 非 JSON / 无 type:1 站点 → 跳过该 URL
// (不抛错),  返回其他 URL 解析成功的.  跟 app 现有 IPv4 / 远程容错一致.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models/vod_source.dart';

const List<String> kTvBoxSourceUrls = [
  'https://9280.kstore.space/wex.json',
  'https://dxawi.github.io/0/0.json',
  'https://raw.liucn.cc/box/m.json',
  'https://github.com/YuanHsing/freed/raw/master/TVBox/meow.json',
];

/// 单 URL 拉取超时.
const Duration kTvBoxFetchTimeout = Duration(seconds: 15);

class TvBoxConfigParser {
  TvBoxConfigParser({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// 拉取所有 TVBox URL,  解析出 type:1 MacCMS 站点,  去重 (同 host 留第一个).
  /// 失败 URL 静默跳过.
  Future<List<VodSource>> fetchTvBoxSources({
    List<String> urls = kTvBoxSourceUrls,
  }) async {
    final found = <String, VodSource>{}; // host → source (去重)
    for (final url in urls) {
      final sources = await _fetchOne(url);
      for (final s in sources) {
        if (s.baseUrl.isEmpty) continue;
        final host = s.host;
        if (found.containsKey(host)) continue; // 同 host 留第一个
        found[host] = s;
      }
    }
    return found.values.toList();
  }

  /// 拉取单个 TVBox URL → type:1 VodSource 列表.
  Future<List<VodSource>> _fetchOne(String url) async {
    try {
      final resp =
          await _client.get(Uri.parse(url)).timeout(kTvBoxFetchTimeout);
      if (resp.statusCode != 200) {
        debugPrint('TvBoxParser: $url → HTTP ${resp.statusCode}, skip');
        return [];
      }
      // 这 4 个 URL 有些在 JSON 前带 // 或 # 注释行 (如 m.json),  清理掉.
      final cleaned = _stripComments(resp.body);
      final decoded = json.decode(cleaned);
      if (decoded is! Map<String, dynamic>) return [];
      final sites = decoded['sites'];
      if (sites is! List) return [];

      final List<VodSource> result = [];
      for (final site in sites) {
        if (site is! Map<String, dynamic>) continue;
        // 只取 type:1 (MacCMS JSON API).  type:2/3 是 JS spider,  跳过.
        final type = site['type'];
        if (type is! int || type != 1) continue;
        final api = (site['api'] as String?)?.trim() ?? '';
        if (api.isEmpty) continue;
        final rawName = (site['name'] as String?)?.trim() ?? '';
        if (rawName.isEmpty) continue;
        final name = VodSource.cleanName(rawName);
        // id = host + 序号 (避免同 URL 内重名).
        String host;
        try {
          host = Uri.parse(api).host;
        } catch (_) {
          host = 'tvbox';
        }
        final detected = await _detectTypeIds(api);
        result.add(VodSource(
          id: '${host}_${result.length}',
          name: name,
          baseUrl: api,
          typeIds: detected ?? bfzyapiTypeIds,
        ));
      }
      debugPrint('TvBoxParser: $url → ${result.length} type:1 sources');
      return result;
    } catch (e) {
      debugPrint('TvBoxParser: $url fetch failed: $e');
      return [];
    }
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
      // 多个关键词匹配同一个 category 时取第一个匹配的 type_id.
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

      debugPrint(
          'TvBoxParser: typeId detected for $baseUrl → $result');
      return result.isNotEmpty ? result : null;
    } catch (e) {
      debugPrint('TvBoxParser: typeId detection failed for $baseUrl: $e');
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
