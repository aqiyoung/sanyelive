import 'package:flutter_test/flutter_test.dart';

import 'package:threelive/data/models/channel.dart';
import 'package:threelive/data/sources/iptv_org_filter.dart';

Channel _c(
  String id,
  String name,
  String country,
  List<String> cats, {
  bool nsfw = false,
}) {
  return Channel(
    id: id,
    name: name,
    country: country,
    categories: cats,
    isNsfw: nsfw,
  );
}

void main() {
  const filter = IptvOrgFilter();

  test('chineseChannels filters by country=CN', () {
    final list = [
      _c('A.cn', 'CCTV', 'CN', ['news']),
      _c('B.us', 'CNN', 'US', ['news']),
      _c('C.cn', 'Phoenix', 'CN', ['news']),
    ];
    final out = filter.chineseChannels(list);
    expect(out.length, 2);
    expect(out.map((c) => c.id), ['A.cn', 'C.cn']);
  });

  test('chineseChannels filters NSFW', () {
    final list = [
      _c('A.cn', 'X', 'CN', ['xxx'], nsfw: true),
      _c('B.cn', 'Y', 'CN', ['news']),
    ];
    final out = filter.chineseChannels(list);
    expect(out.length, 1);
    expect(out.first.id, 'B.cn');
  });

  test('curated limits to mainstream categories', () {
    final list = [
      _c('A.cn', 'A', 'CN', ['news']),
      _c('B.cn', 'B', 'CN', ['cooking']),
      _c('C.cn', 'C', 'CN', ['sports']),
    ];
    final out = filter.curated(list);
    expect(out.length, 2);
    expect(out.map((c) => c.id), ['A.cn', 'C.cn']);
  });

  test('curated deduplicates by id', () {
    final list = [
      _c('A.cn', 'A1', 'CN', ['news']),
      _c('A.cn', 'A2', 'CN', ['news']),
    ];
    final out = filter.curated(list);
    expect(out.length, 1);
  });
}
