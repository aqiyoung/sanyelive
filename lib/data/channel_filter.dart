import 'models/channel.dart';

/// Shared channel filter logic for category classification
class ChannelFilter {
  ChannelFilter._();

  static List<Channel> cctv(List<Channel> all) {
    return all
        .where((c) => c.id.startsWith(RegExp(r'CCTV', caseSensitive: false)))
        .toList();
  }

  static List<Channel> satellite(List<Channel> all) {
    // v0.3.8+131 (6/21 09:01 老板反馈 "地方分类里混的卫视频道 没有合并整理"):
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

  /// v0.3.10.13 (6/24): 按中文分类名筛选频道
  static List<Channel> byCategory(List<Channel> all, String category) {
    return all.where((c) => c.categories.contains(category)).toList();
  }

  /// v0.3.10.13 (6/24): 地方 = 排除 央视/卫视/国际/内容分类 后的频道
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

  /// v0.3.8+133 (6/21 09:49 老板反馈 "地方分类里还有几个卫视"):
  /// 之前只排除 cctv + satellite,  没排除 international — 133 个国际频道
  /// 错误归到"地方".  修法:  加 international 排除.
  /// v0.3.10.13 (6/24):  加内容分类排除 (新闻/影视/少儿/体育/科教/娱乐/财经).

  /// v0.3.8+110 (6/20 老板加国际频道模块):  国际频道 = 非中国 country.
  /// 'CN'/'HK'/'TW'/'MO' 是中文区,  其它都是国际 (i18n channels 7 国精选).
  static List<Channel> international(List<Channel> all) {
    const zhCountries = {'CN', 'HK', 'TW', 'MO'};
    return all
        .where((c) => !zhCountries.contains(c.country) && c.country.isNotEmpty)
        .toList();
  }
}
