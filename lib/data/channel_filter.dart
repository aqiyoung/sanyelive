import 'models/channel.dart';

/// Shared channel filter logic for category classification
class ChannelFilter {
  ChannelFilter._();

  /// 首页「正在直播」优选顺序 (按国民度手排).
  /// 每项先按 channel id 精确匹配, 不中再按 displayName/altNames 关键词匹配 ——
  /// 数据里同一频道有中英文两套 id (如 `浙江卫视.cn` 与 `ZhejiangSatelliteTV.cn`),
  /// 关键词兜底可保证换 id 体系也能命中.
  static const List<String> kHotChannelKeys = <String>[
    'CCTV1.cn', // 综合
    'CCTV13.cn', // 新闻
    'CCTV5.cn', // 体育
    '湖南卫视',
    'CCTV6.cn', // 电影
    '浙江卫视',
    'CCTV3.cn', // 综艺
    '江苏卫视',
    '东方卫视',
    'CCTV8.cn', // 电视剧
    '北京卫视',
    'CCTV4.cn', // 中文国际
  ];

  /// 优选热门频道 — 首页「正在直播」用.
  ///
  /// 之前首页第一行直接铺全量 channels (198 个), 冷门地方台混在最前面,
  /// 用户要横滑很久才看到央视/湖南卫视. 这里按 [kHotChannelKeys] 的国民度
  /// 顺序优选, 并按 displayName 去重 (避免中英文双 id 同频道各占一格).
  /// 不足 [limit] 时用剩余频道原顺序补齐, 保证这一行永远不空.
  static List<Channel> hot(List<Channel> all, {int limit = 12}) {
    if (all.isEmpty) return const <Channel>[];
    final picked = <Channel>[];
    final seenId = <String>{};
    final seenName = <String>{};

    bool take(Channel c) {
      if (!seenId.add(c.id)) return false;
      if (!seenName.add(c.displayName)) return false;
      picked.add(c);
      return true;
    }

    for (final key in kHotChannelKeys) {
      if (picked.length >= limit) break;
      // 1. id 精确
      Channel? hit;
      for (final c in all) {
        if (c.id == key) {
          hit = c;
          break;
        }
      }
      // 2. 名称关键词 (中文名 / alt_names)
      if (hit == null) {
        for (final c in all) {
          if (c.displayName.contains(key) ||
              c.name.contains(key) ||
              c.altNames.any((a) => a.contains(key))) {
            hit = c;
            break;
          }
        }
      }
      if (hit != null) take(hit);
    }

    // 补齐: 优选表命中不足时按原顺序填充, 这一行不能是空的
    for (final c in all) {
      if (picked.length >= limit) break;
      take(c);
    }
    return picked;
  }

  static List<Channel> cctv(List<Channel> all) {
    return all
        .where((c) => c.id.startsWith(RegExp(r'CCTV', caseSensitive: false)))
        .toList();
  }

  static List<Channel> satellite(List<Channel> all) {
    // 之前只查 id contains 'SatelliteTV' 或 'TVInternational' — 15 个命中.
    // 但远端 iptv-channels-organized data 里还有 HenanTVSatellite.cn
    // (没 TV 后缀) + NingxiaSatelliteChannel.cn + 中文命名 XX卫视.cn
    // (没 'Satellite' 也没 'TVInternational') — 这部分被错误分到 local 分类.
    // 修法:  3 路匹配 — id 含 'Satellite' OR 'TVInternational' OR 中文 alt/name 含 '卫视'.
    return all.where((c) {
      // 1. id 包含 'Satellite' 或 'TVInternational' (含 HenanTVSatellite / SatelliteChannel)
      if (c.id.contains('Satellite')) return true;
      if (c.id.contains('TVInternational')) return true;
      // 2. 中文 alt_names 或 name 包含 '卫视'
      if (c.altNames.any((a) => a.contains('卫视'))) return true;
      if (c.name.contains('卫视')) return true;
      return false;
    }).toList();
  }

  static List<Channel> byCategory(List<Channel> all, String category) {
    return all.where((c) => c.categories.contains(category)).toList();
  }

  static List<Channel> local(List<Channel> all) {
    final sat = satellite(all).map((e) => e.id).toSet();
    final cctvIds = cctv(all).map((e) => e.id).toSet();
    final intlIds = international(all).map((e) => e.id).toSet();
    const contentCats = {'新闻', '影视', '少儿', '体育', '科教', '娱乐', '财经'};
    return all
        .where((c) =>
            !sat.contains(c.id) &&
            !cctvIds.contains(c.id) &&
            !intlIds.contains(c.id) &&
            !c.categories.any((cat) => contentCats.contains(cat)))
        .toList();
  }

  /// 之前只排除 cctv + satellite,  没排除 international — 133 个国际频道
  /// 错误归到"地方".  修法:  加 international 排除.

  /// 'CN'/'HK'/'TW'/'MO' 是中文区,  其它都是国际 (i18n channels 7 国精选).
  static List<Channel> international(List<Channel> all) {
    const zhCountries = {'CN', 'HK', 'TW', 'MO'};
    return all
        .where((c) => !zhCountries.contains(c.country) && c.country.isNotEmpty)
        .toList();
  }
}
