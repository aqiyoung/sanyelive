import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models/content.dart';

/// v0.3.11.64: 暴风TVBox JSON API 封装 — 真实影视点播源
///
/// 列表 API (ac=list): 标题/分类/备注, 无海报/播放URL (第 N+1)
/// 详情 API (ac=detail&ids=xxx): 含海报/播放URL, 支持批量
class VodApiService {
  VodApiService({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// v0.3.13.0: base URL 改成实例字段 — 支持多 MacCMS 源.
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
  /// [firstEpisodeOnly] 为 true 时只取第一集播放 URL (适合海报墙展示)
  Content toContent(Map<String, dynamic> item, {bool firstEpisodeOnly = true}) {
    final playUrl = _parsePlayUrl(
      item['vod_play_url'] as String? ?? '',
      firstEpisodeOnly: firstEpisodeOnly,
    );
    return Content(
      id: 'vod_${item['vod_id']}',
      title: item['vod_name'] as String? ?? '',
      subtitle: item['vod_remarks'] as String?,
      posterUrl: item['vod_pic'] as String?,
      type: _inferType(item['type_name'] as String? ?? 'movie'),
      rating: (item['vod_score'] as num?)?.toDouble(),
      year: item['vod_year'] as String?,
      genres: [item['type_name'] as String? ?? ''],
      description: item['vod_content'] as String?,
      sourceUrls: playUrl != null ? [playUrl] : [],
    );
  }

  /// 解析 vod_play_url 格式: "第1集$url#第2集$url"
  String? _parsePlayUrl(String raw, {bool firstEpisodeOnly = true}) {
    if (raw.isEmpty) return null;
    // 格式: "第1集$url#第2集$url" 或 "$url"
    final episodes = raw.split('#');
    if (episodes.isEmpty) return null;
    final first = episodes.first;
    final dollarIdx = first.indexOf('\$');
    if (dollarIdx < 0) return first.trim(); // 无 $ 分隔, 直接是 URL
    return first.substring(dollarIdx + 1).trim();
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