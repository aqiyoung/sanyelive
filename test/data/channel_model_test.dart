import 'package:flutter_test/flutter_test.dart';

import 'package:iptv_app/data/models/channel.dart';

void main() {
  group('Channel.fromJson', () {
    test('parses iptv-org standard fields', () {
      final j = <String, dynamic>{
        'id': 'CCTV1.cn',
        'name': 'CCTV-1',
        'country': 'CN',
        'categories': <String>['general', 'news'],
        'alt_names': <String>['央视一套'],
        'website': 'http://www.cctv.com/',
        'logo': 'http://example.com/logo.png',
        'is_nsfw': false,
      };
      final c = Channel.fromJson(j);
      expect(c.id, 'CCTV1.cn');
      expect(c.name, 'CCTV-1');
      expect(c.country, 'CN');
      expect(c.categories, <String>['general', 'news']);
      expect(c.altNames, <String>['央视一套']);
      expect(c.website, 'http://www.cctv.com/');
      expect(c.logoUrl, 'http://example.com/logo.png');
      expect(c.isNsfw, false);
    });

    test('isChinese: country=CN', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.cn',
        'name': 'X',
        'country': 'CN',
      });
      expect(c.isChinese, true);
    });

    test('isChinese: name contains Chinese chars', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.tw',
        'name': '民视',
        'country': 'TW',
      });
      expect(c.isChinese, true);
    });

    test('isChinese: English name + non-CN country', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.us',
        'name': 'CNN',
        'country': 'US',
      });
      expect(c.isChinese, false);
    });

    test('primaryCategory falls back to general', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.us',
        'name': 'X',
        'country': 'US',
        'categories': <String>[],
      });
      expect(c.primaryCategory, 'general');
    });

    test('primaryCategory returns first', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.cn',
        'name': 'X',
        'country': 'CN',
        'categories': <String>['news', 'general'],
      });
      expect(c.primaryCategory, 'news');
    });
  });

  test('Channel.toJson roundtrips', () {
    const c = Channel(
      id: 'A.cn',
      name: 'A',
      country: 'CN',
      categories: <String>['news'],
    );
    final j = c.toJson();
    final c2 = Channel.fromJson(j);
    expect(c2.id, c.id);
    expect(c2.name, c.name);
    expect(c2.country, c.country);
    expect(c2.categories, c.categories);
  });

  group('sources 字段 (卡 6)', () {
    test('parses sources list', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CCTV1.cn',
        'name': 'CCTV-1',
        'country': 'CN',
        'categories': <String>['news'],
        'sources': <String>[
          'http://example.com/cctv1.m3u8',
          'https://backup.example.com/cctv1.m3u8',
        ],
      });
      expect(c.sources, hasLength(2));
      expect(c.sources[0], 'http://example.com/cctv1.m3u8');
    });

    test('sources 缺省是空 list', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.cn',
        'name': 'X',
        'country': 'CN',
      });
      expect(c.sources, isEmpty);
    });

    test('sources 容忍 null', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.cn',
        'name': 'X',
        'country': 'CN',
        'sources': null,
      });
      expect(c.sources, isEmpty);
    });

    test('toJson 含 sources', () {
      const c = Channel(
        id: 'A.cn',
        name: 'A',
        country: 'CN',
        categories: <String>['news'],
        sources: <String>['http://a.com/1.m3u8'],
      );
      final j = c.toJson();
      expect(j['sources'], <String>['http://a.com/1.m3u8']);
    });
  });
}
