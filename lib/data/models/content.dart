/// 通用内容模型 — 点播/直播统一
///
/// v0.3.11 (三页影视): 从 Channel 模型扩展, 支持电影/电视剧/综艺等点播类型.
/// 直播频道通过 [ChannelPlayable] 扩展实现统一接口.
class Content {
  const Content({
    required this.id,
    required this.title,
    this.subtitle,
    this.posterUrl,
    this.backdropUrl,
    required this.type,
    this.rating,
    this.duration,
    this.year,
    this.genres = const [],
    this.description,
    this.sourceUrls = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? posterUrl;
  final String? backdropUrl;
  final String type; // "movie" | "series" | "variety" | "live"
  final double? rating;
  final String? duration;
  final String? year;
  final List<String> genres;
  final String? description;
  final List<String> sourceUrls;

  bool get isLive => type == 'live';
  bool get isVod => !isLive;

  /// 是否有海报图
  bool get hasPoster => posterUrl != null && posterUrl!.isNotEmpty;

  /// 显示评分 (格式化)
  final String? ratingText =
      null; // placeholder, actual getter below

  String get displayRating {
    if (rating == null) return '';
    return rating! >= 9.0 ? '${rating}' : '${rating}';
  }

  factory Content.fromJson(Map<String, dynamic> j) {
    return Content(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      subtitle: j['subtitle'] as String?,
      posterUrl: j['poster_url'] as String?,
      backdropUrl: j['backdrop_url'] as String?,
      type: (j['type'] as String?) ?? 'movie',
      rating: (j['rating'] as num?)?.toDouble(),
      duration: j['duration'] as String?,
      year: j['year'] as String?,
      genres: ((j['genres'] as List?) ?? const []).cast<String>(),
      description: j['description'] as String?,
      sourceUrls: ((j['source_urls'] as List?) ?? const []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'poster_url': posterUrl,
        'backdrop_url': backdropUrl,
        'type': type,
        'rating': rating,
        'duration': duration,
        'year': year,
        'genres': genres,
        'description': description,
        'source_urls': sourceUrls,
      };
}

/// 统一播放接口 — Channel 和 Content 都实现
abstract class Playable {
  String get id;
  String get title;
  String get posterUrl;
  List<String> get sourceUrls;
  bool get isLive;
}

/// Content 实现 Playable
extension ContentPlayable on Content {
  bool get playableIsLive => type == 'live';
  String get playablePosterUrl => posterUrl ?? '';
}
