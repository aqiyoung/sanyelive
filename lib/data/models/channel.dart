/// iptv-org 频道模型
library;
import '../channel_name_zh.dart';

class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.country,
    required this.categories,
    this.altNames = const <String>[],
    this.website,
    this.logoUrl,
    this.sources = const <String>[],
    this.cctvSource = const <String>[],
    this.isNsfw = false,
  });

  final String id;
  final String name;
  final String country;
  final List<String> categories;
  final List<String> altNames;
  final String? website;
  final String? logoUrl;
  final List<String> sources;

  /// v0.3.5.3 (6/18): CCTV 专属播放源 — 经过真机 fetch 验证的健康 CDN 列表.
  /// 跟 [sources] 不冲突, 播放时优先级 cctvSource[0] > sources[0] > known_sources.
  /// 存放位置: assets/data/channels_cn.json 18 个 CCTV entry 的 cctvSource 字段.
  /// 优点: sources 字段保留 iptv-org / known_sources 历史兼容, 老的 release
  /// 升级到 v0.3.5.3 不会丢源, 只是优先用 cctvSource.
  final List<String> cctvSource;
  final bool isNsfw;

  /// 主分类（取第一个）
  String get primaryCategory =>
      categories.isNotEmpty ? categories.first : 'general';

  /// 中文 channel 筛选
  bool get isChinese {
    if (country == 'CN' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO') {
      return true;
    }
    if (_hasChinese(name)) return true;
    for (final a in altNames) {
      if (_hasChinese(a)) return true;
    }
    return false;
  }

  /// UI 实际显示名称 — 优先中文 (alt_names 第一个含中文的),
  /// 兑底手工中文表 (channel_name_zh.dart), 最后原始 name.
  String get displayName {
    if (isChinese) {
      // 优先 alt_names 里第一个含中文的
      for (final a in altNames) {
        if (_hasChinese(a)) return a;
      }
    }
    // 兑底手工中文表
    final mapped = _manualZhMap[id] ?? _manualZhMap[name];
    if (mapped != null) return mapped;
    return name;
  }

  /// 中英对照的副标题 — 原名跟 displayName 不同时才返, 否则 null
  String? get displaySubtitle {
    // v0.3.10.13 (6/24): 副标题显示分类名 (中文), 不再显示英文原名.
    final cats = categories;
    if (cats.isEmpty) return null;
    // v0.3.10.16: 英文分类名映射为中文
    const enToZh = {
      'general': '综合',
      'news': '新闻',
      'movies': '影视',
      'kids': '少儿',
      'sports': '体育',
      'education': '科教',
      'entertainment': '娱乐',
      'culture': '文化',
      'documentary': '纪录片',
      'animation': '动画',
      'lifestyle': '生活',
      'science': '科学',
      'travel': '旅游',
      'finance': '财经',
    };
    return enToZh[cats.first] ?? cats.first;
  }

  static final RegExp _chineseRe = RegExp(r'[\u4e00-\u9fff]');
  static bool _hasChinese(String s) => _chineseRe.hasMatch(s);

  /// 手工中文映射表 — 兑底用, 避免循环引用.
  /// 实际定义在 lib/data/channel_name_zh.dart, 运行时通过 import 注入.
  static const Map<String, String> _manualZhMap = kChannelNameZh;

  /// v0.3.10.16: 从频道属性推导中文分类.
  /// 远端 iptv-org 数据是英文分类 (general/cctv/satellite), 这里统一转为中文.
  static List<String> _deriveCategories(Channel ch) {
    final cid = ch.id;
    final name = ch.name;
    final altNames = ch.altNames;
    final country = ch.country;

    // 央视
    if (RegExp(r'CCTV', caseSensitive: false).hasMatch(cid)) return ['央视'];

    // 卫视: id 含 Satellite/TVInternational/卫视, 或省级 TV 频道 (HunanTV/GansuTV 等)
    if (cid.contains('Satellite') ||
        cid.contains('TVInternational') ||
        name.contains('卫视') ||
        altNames.any((a) => a.contains('卫视'))) {
      return ['卫视'];
    }
    // 省级卫视 fallback: XXTV.cn / XXSatelliteTV.cn / XXInternationalChannel (不含 Satellite 关键词的)
    if ((RegExp(r'^[A-Z][a-z]+TV').hasMatch(cid) ||
            cid.contains('InternationalChannel')) &&
        country == 'CN') {
      return ['卫视'];
    }
    // 中文省级台: XX电视台 / XX卫视 (alt_names 里带 "电视台" 或 "卫视")
    if (altNames.any((a) => a.contains('电视台') || a.contains('卫视')) &&
        country == 'CN') {
      return ['卫视'];
    }
    // QTV 系列频道按名称分类
    if (cid.startsWith('QTV') && altNames.isNotEmpty) {
      final alt = altNames.first;
      if (alt.contains('青少') || alt.contains('少儿')) return ['少儿'];
      if (alt.contains('影视') || alt.contains('电影')) return ['影视'];
    }

    // 国际 (非中文区)
    if (country.isNotEmpty && !{'CN', 'HK', 'TW', 'MO'}.contains(country)) {
      return ['国际'];
    }

    // 内容分类 (按名称关键词)
    final allNames = [name, ...altNames].join(' ');
    if (RegExp(r'新闻|News|CGTN|资讯|信息|报道|journal|report', caseSensitive: false).hasMatch(allNames) ||
        cid.contains('news')) {
      return ['新闻'];
    }
    if (RegExp(r'电影|Movie|影院|剧场|Drama|CHC|影视|视频|Video|Film', caseSensitive: false)
        .hasMatch(allNames)) {
      return ['影视'];
    }
    if (RegExp(r'少儿|Kids|卡通|Cartoon|Children|儿童|动画|亲子', caseSensitive: false)
        .hasMatch(allNames)) {
      return ['少儿'];
    }
    if (RegExp(r'体育|Sports|足球|Football|运动|比赛', caseSensitive: false)
        .hasMatch(allNames)) {
      return ['体育'];
    }
    if (RegExp(r'教育|Education|科学|Science|科教|知识|科普', caseSensitive: false)
        .hasMatch(allNames)) {
      return ['科教'];
    }
    if (RegExp(r'娱乐|Variety|综艺|音乐|Music|游戏|才艺', caseSensitive: false)
        .hasMatch(allNames)) {
      return ['娱乐'];
    }
    if (RegExp(r'财经|Finance|经济|Economic|股市|金融|商贸', caseSensitive: false)
        .hasMatch(allNames)) {
      return ['财经'];
    }

    return ['地方'];
  }

  /// v0.3.11.62: VOD 点播临时频道 — 用任意播放 URL 构造一个 Channel,
  /// 复用现有 play()/playSingleSource() 全链路 (错误/换源 UI 通用).
  /// id 用 url 的 hash 保证唯一且可寻址; sources 只含这一个 VOD URL.
  factory Channel.fromVod(String url, {required String title}) {
    return Channel(
      id: 'vod://${url.hashCode}',
      name: title,
      country: '',
      categories: const ['影视'],
      sources: [url],
    );
  }

  factory Channel.fromJson(Map<String, dynamic> j) {
    // v0.3.5.1 (6/18): 支持 string 和 {url, type} dict 两种 source 格式.
    // channels_cn.json 现有 145 string 源 (iptv-org 原始格式) + 83 dict 源
    // (merge_known_sources.py 把 known_sources.json 合并后改的格式).
    // 之前 .cast<String>() 在 dict 上 view 不报错, 但访问时 TypeError 炸,
    // CCTV-5 加载不出来可能就是这原因.
    final rawSources = (j['sources'] as List?) ?? const [];
    final sources = <String>[];
    for (final s in rawSources) {
      if (s is String) {
        sources.add(s);
      } else if (s is Map) {
        final url = s['url'];
        if (url is String) sources.add(url);
      }
    }
    // v0.3.5.3 (6/18): cctvSource 字段解析 (跟 sources 同格式, 优先用).
    // 老 channels_cn.json 没有这字段, 走默认 const <String>[] (空数组).
    // 跟 sources 字段一样容忍 string 和 {url, type} dict 两种格式.
    final rawCctvSource = (j['cctvSource'] as List?) ?? const [];
    final cctvSource = <String>[];
    for (final s in rawCctvSource) {
      if (s is String) {
        cctvSource.add(s);
      } else if (s is Map) {
        final url = s['url'];
        if (url is String) cctvSource.add(url);
      }
    }
    // v0.3.10.16: 从属性推导中文分类 (覆盖远端英文分类)
    final derivedCategories = _deriveCategories(
      Channel(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? (j['id'] as String),
        country: (j['country'] as String?) ?? '',
        categories: const [],
        sources: const [],
      ),
    );

    return Channel(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? (j['id'] as String),
      country: (j['country'] as String?) ?? '',
      categories: derivedCategories,
      altNames: ((j['alt_names'] as List?)?.cast<String>()) ?? const <String>[],
      website: j['website'] as String?,
      logoUrl: j['logo'] as String?,
      sources: sources,
      cctvSource: cctvSource,
      isNsfw: (j['is_nsfw'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'country': country,
        'categories': categories,
        'alt_names': altNames,
        'website': website,
        'logo': logoUrl,
        'sources': sources,
        'cctvSource': cctvSource,
        'is_nsfw': isNsfw,
      };
}
