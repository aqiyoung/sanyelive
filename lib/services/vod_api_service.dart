import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models/content.dart';

///
/// 列表 API (ac=list): 标题/分类/备注, 无海报/播放URL (第 N+1)
/// 详情 API (ac=detail&ids=xxx): 含海报/播放URL, 支持批量
class VodApiService {
  VodApiService({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// 例: "https://bfzyapi.com/api.php/provide/vod".
  final String baseUrl;

  final http.Client _client;

  /// 安全解析 JSON，失败时返回 null
  Map<String, dynamic>? _safeJsonDecode(String body) {
    try {
      return json.decode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// 获取分类列表
  Future<List<Map<String, dynamic>>> getCategories() async {
    final uri = Uri.parse('$baseUrl?ac=list&t=1');
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      final data = _safeJsonDecode(res.body);
      if (data == null) return [];
      return (data['class'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  /// 获取指定分类的列表 (无海报/播放URL)
  Future<List<Map<String, dynamic>>> getList({
    int? typeId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, String>{
      'ac': 'list',
      'pg': '$page',
      'pagesize': '$pageSize',
    };
    if (typeId != null) params['t'] = '$typeId';
    final uri = Uri.parse(baseUrl).replace(queryParameters: params);
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    final data = _safeJsonDecode(res.body);
    if (data == null) return [];
    return (data['list'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 搜索内容 — MacCMS search 接口 (含海报/播放URL)
  Future<List<Map<String, dynamic>>> search(String keyword) async {
    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'ac': 'detail',
      'wd': keyword,
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    final data = _safeJsonDecode(res.body);
    if (data == null) return [];
    return (data['list'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 批量获取详情 (含海报、播放URL)
  Future<List<Map<String, dynamic>>> getDetail(List<int> ids) async {
    if (ids.isEmpty) return [];
    final uri = Uri.parse('$baseUrl?ac=detail&ids=${ids.join(',')}');
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    final data = _safeJsonDecode(res.body);
    if (data == null) return [];
    return (data['list'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 将 API 条目转为 Content 模型
  /// 始终解析全集到 [Content.episodes]; [sourceUrls] 保留首集 URL (兼容旧 UI).
  Content toContent(Map<String, dynamic> item, {bool firstEpisodeOnly = true}) {
    final raw = (item['vod_play_url'] as String?) ?? '';
    final episodes = parseEpisodes(raw);
    final firstUrl = episodes.isNotEmpty ? episodes.first.url : null;
    return Content(
      id: 'vod_${item['vod_id']}',
      vodId: '${item['vod_id']}',
      title: item['vod_name'] as String? ?? '',
      subtitle: item['vod_remarks'] as String?,
      posterUrl: item['vod_pic'] as String?,
      type: _inferType(item['type_name'] as String? ?? 'movie'),
      rating: (item['vod_score'] as num?)?.toDouble(),
      year: item['vod_year'] as String?,
      genres: [item['type_name'] as String? ?? ''],
      description: item['vod_content'] as String?,
      episodes: episodes,
      sourceUrls: firstUrl != null ? [firstUrl] : [],
    );
  }

  /// 解析 vod_play_url → 全集列表.
  /// 格式: "第1集$url#第2集$url" 或 "组1$...#...$$$组2$..." (多播放源用 $$$ 分隔).
  /// 多源时取第一组. 返回空列表表示无播放地址.
  List<Episode> parseEpisodes(String raw) {
    if (raw.isEmpty) return const [];
    // 多播放源用 $$$ 分隔, 取第一组.
    final group = raw.split('\$\$\$').first;
    final parts =
        group.split('#').where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return const [];
    final out = <Episode>[];
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      final dollarIdx = p.indexOf('\$');
      final name =
          dollarIdx >= 0 ? p.substring(0, dollarIdx).trim() : '第${i + 1}集';
      final url =
          (dollarIdx >= 0 ? p.substring(dollarIdx + 1) : p).trim();
      if (url.isNotEmpty) {
        out.add(Episode(name: name.isNotEmpty ? name : '第${i + 1}集', url: url));
      }
    }
    return out;
  }

  String _inferType(String typeName) {
    // 直播类
    if (typeName.contains('直播') || typeName.contains('体育') || typeName.contains('NBA')) {
      return 'live';
    }
    // 剧集类
    if (typeName.contains('剧') || typeName.contains('动漫')) {
      return 'series';
    }
    // 综艺类
    if (typeName.contains('综艺')) {
      return 'variety';
    }
    return 'movie';
  }

  void dispose() {
    _client.close();
  }
}