import 'package:flutter/foundation.dart';

/// 首页「特别专区」单条 hero 视频 (运营远程推送, 临时展示).
///
/// 数据来自远程 JSON (见 [HeroVideosSource]),  App 启动时拉取; 列表为空时
/// 首页专区自动隐藏 (临时 / 可推送). 点击走内置播放器 (/player/vod?url=&title=).
@immutable
class HeroVideo {
  const HeroVideo({
    required this.id,
    required this.title,
    this.subtitle,
    required this.cover,
    required this.videoUrl,
    this.type,
    this.expiry,
    this.sort,
  });

  /// 稳定标识 (缺省回退到 videoUrl, 用于列表 key).
  final String id;

  /// 标题 (卡片底部展示).
  final String title;

  /// 副标题 (可选, 标题下方小字).
  final String? subtitle;

  /// 封面图 URL (网络图, 卡片用 Image.network 加载).
  final String cover;

  /// 播放地址 (m3u8 / mp4).
  final String videoUrl;

  /// 类型角标: 'live' | 'vod' 等 (仅展示, 不影响播放).
  final String? type;

  /// 过期时间 ISO8601 (可选); 过期后不展示.
  final String? expiry;

  /// 排序权重 (越大越靠前); 缺省按数组顺序.
  final int? sort;

  factory HeroVideo.fromJson(Map<String, dynamic> j) {
    final url = (j['url'] as String?) ?? (j['videoUrl'] as String?);
    return HeroVideo(
      id: (j['id'] as String?) ?? url ?? '',
      title: (j['title'] as String?) ?? '',
      subtitle: j['subtitle'] as String?,
      cover: (j['cover'] as String?) ?? (j['poster'] as String? ?? ''),
      videoUrl: url ?? '',
      type: j['type'] as String?,
      expiry: j['expiry'] as String?,
      sort: j['sort'] as int?,
    );
  }

  /// 从远程 JSON 解码为列表.  兼容三种顶层结构:
  ///   - 纯数组 [ {...}, ... ]
  ///   - { "items": [...] } / { "hero_videos": [...] } / { "videos": [...] }
  /// 单条解析失败跳过; 最终按 [sort] 降序.
  static List<HeroVideo> listFromJson(dynamic decoded) {
    final raw = decoded is List
        ? decoded
        : (decoded is Map<String, dynamic>
            ? (decoded['items'] ?? decoded['hero_videos'] ?? decoded['videos'])
            : null);
    if (raw is! List) return const [];
    final out = <HeroVideo>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(HeroVideo.fromJson(e));
        } catch (_) {
          // 单条损坏跳过, 不阻塞整体.
        }
      }
    }
    out.sort((a, b) => (b.sort ?? 0).compareTo(a.sort ?? 0));
    return out;
  }
}
