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
    const patterns = ['SatelliteTV', 'TVInternational'];
    return all.where((c) {
      for (final p in patterns) {
        if (c.id.contains(p)) return true;
      }
      return false;
    }).toList();
  }

  static List<Channel> local(List<Channel> all) {
    final sat = satellite(all).map((e) => e.id).toSet();
    final cctvIds = cctv(all).map((e) => e.id).toSet();
    return all
        .where((c) => !sat.contains(c.id) && !cctvIds.contains(c.id))
        .toList();
  }

  /// v0.3.8+110 (6/20 老板加国际频道模块):  国际频道 = 非中国 country.
  /// 'CN'/'HK'/'TW'/'MO' 是中文区,  其它都是国际 (i18n channels 7 国精选).
  static List<Channel> international(List<Channel> all) {
    const zhCountries = {'CN', 'HK', 'TW', 'MO'};
    return all
        .where((c) => !zhCountries.contains(c.country) && c.country.isNotEmpty)
        .toList();
  }
}
