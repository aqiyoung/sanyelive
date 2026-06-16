import '../models/channel.dart';

class IptvOrgFilter {
  const IptvOrgFilter();

  List<Channel> chineseChannels(List<Channel> all) {
    final out = <Channel>[];
    for (final c in all) {
      if (c.isNsfw) continue;
      if (!c.isChinese) continue;
      out.add(c);
    }
    return out;
  }

  List<Channel> curated(List<Channel> all) {
    const wanted = {
      'general',
      'news',
      'sports',
      'music',
      'movies',
      'kids',
      'entertainment',
      'documentary',
      'education',
      'animation',
    };
    final seen = <String>{};
    final out = <Channel>[];
    for (final c in chineseChannels(all)) {
      if (seen.contains(c.id)) continue;
      seen.add(c.id);
      if (c.categories.isEmpty) continue;
      if (!c.categories.any((k) => wanted.contains(k))) continue;
      out.add(c);
    }
    return out;
  }
}
