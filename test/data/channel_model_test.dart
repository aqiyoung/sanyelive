import 'package:flutter_test/flutter_test.dart';

import 'package:iptv_app/data/models/channel.dart';

void main() {
  group('Channel.fromJson', () {
    test('parses iptv-org standard fields', () {
      final j = {
        'id': 'CCTV1.cn',
        'name': 'CCTV-1',
        'country': 'CN',
        'categories': ['general', 'news'],
        'alt_names': ['央视一套'],
        'website': 'http://www.cctv.com/',
        'logo': 'http://example.com/logo.png',
        'is_nsfw': false,
      };
      final c = Channel.fromJson(j);
      expect(c.id, 'CCTV1.cn');
      expect(c.name, 'CCTV-1');
      expect(c.country, 'CN');
      expect(c.categories, ['general', 'news']);
      expect(c.altNames, ['央视一套']);
      expect(c.website, 'http://www.cctv.com/');
      expect(c.logoUrl, 'http://example.com/logo.png');
      expect(c.isNsfw, false);
    });

    test('isChinese: country=CN', () {
      final c = Channel.fromJson({
        'id': 'X.cn',
        'name': 'X',
        'country': 'CN',
      });
      expect(c.isChinese, true);
    });

    test('isChinese: name contains Chinese chars', () {
      final c = Channel.fromJson({
        'id': 'X.tw',
        'name': '民视',
        'country': 'TW',
      });
      expect(c.isChinese, true);
    });

    test('isChinese: English name + non-CN country', () {
      final c = Channel.fromJson({
        'id': 'X.us',
        'name': 'CNN',
        'country': 'US',
      });
      expect(c.isChinese, false);
    });

    test('primaryCategory falls back to general', () {
      final c = Channel.fromJson({
        'id': 'X.us',
        'name': 'X',
        'country': 'US',
        'categories': [],
      });
      expect(c.primaryCategory, 'general');
    });

    test('primaryCategory returns first', () {
      final c = Channel.fromJson({
        'id': 'X.cn',
        'name': 'X',
        'country': 'CN',
        'categories': ['news', 'general'],
      });
      expect(c.primaryCategory, 'news');
    });
  });

  test('Channel.toJson roundtrips', () {
    final c = Channel(
      id: 'A.cn',
      name: 'A',
      country: 'CN',
      categories: const ['news'],
    );
    final j = c.toJson();
    final c2 = Channel.fromJson(j);
    expect(c2.id, c.id);
    expect(c2.name, c.name);
    expect(c2.country, c.country);
    expect(c2.categories, c.categories);
  });
}
