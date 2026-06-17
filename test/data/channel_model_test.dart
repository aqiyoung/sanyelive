import 'package:flutter_test/flutter_test.dart';

import 'package:threelive/data/models/channel.dart';

void main() {
  group('Channel.fromJson', () {
    test('parses iptv-org standard fields', () {
      final j = <String, dynamic>{
        'id': 'CCTV1.cn',
        'name': 'CCTV-1',
        'country': 'CN',
        'categories': <String>['general', 'news'],
        'alt_names': <String>['央视一�?],
        'website': 'http://www.cctv.com/',
        'logo': 'http://example.com/logo.png',
        'is_nsfw': false,
      };
      final c = Channel.fromJson(j);
      expect(c.id, 'CCTV1.cn');
      expect(c.name, 'CCTV-1');
      expect(c.country, 'CN');
      expect(c.categories, <String>['general', 'news']);
      expect(c.altNames, <String>['央视一�?]);
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

  group('sources 字段 (�?6)', () {
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

    test('toJson �?sources', () {
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

  // �?7 (6/17 老板需�?: 频道名自动优先中�? 手工映射兑底.
  group('displayName / displaySubtitle (中文�?', () {
    test('中文 alt_names 优先 (CCTV-13 �?央视新闻)', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CCTV13.cn',
        'name': 'CCTV-13',
        'country': 'CN',
        'alt_names': <String>['CCTV-13 新闻', '中国中央电视台新闻频�?],
      });
      expect(c.displayName, 'CCTV-13 新闻');
    });

    test('CGTN 手工映射: 原始 name 英文没中�?alt, 从映射表�?, () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CGTNArabic.cn',
        'name': 'CGTN Arabic',
        'country': 'CN',
        'alt_names': <String>['CGTN العربية'],
      });
      // 第一�?alt 包含 Arabic 字符, 但这个含中文 (�?, 所以走手工�?
      // 手工�?'CGTNArabic.cn' �?'CGTN 阿语'
      expect(c.displayName, 'CGTN 阿语');
    });

    test('中国频道, 手工表里�?id �?用映射名', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CCTVPlus1.cn',
        'name': 'CCTV+ 1',
        'country': 'CN',
        'alt_names': <String>[],
      });
      expect(c.displayName, 'CCTV+ 1 (海外�?');
    });

    test('displaySubtitle: 中文化后, 原名作为副标�?, () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CCTV13.cn',
        'name': 'CCTV-13',
        'country': 'CN',
        'alt_names': <String>['CCTV-13 新闻'],
      });
      expect(c.displayName, 'CCTV-13 新闻');
      expect(c.displaySubtitle, 'CCTV-13');
    });

    test('displaySubtitle: 已经是原�?(没中文化) �?null', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CNN.us',
        'name': 'CNN',
        'country': 'US',
        'alt_names': <String>[],
      });
      expect(c.displayName, 'CNN');
      expect(c.displaySubtitle, isNull);
    });

    test('非中国频�? 纯英�?�?displayName 就是 name', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CNN.us',
        'name': 'CNN',
        'country': 'US',
        'alt_names': <String>[],
      });
      expect(c.displayName, 'CNN');
    });

    test('手工映射�?name 兑底', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'unknown_id.cn',
        'name': 'GTV Electronic Sports',
        'country': 'CN',
        'alt_names': <String>[],
      });
      // id 不在映射�? name 也不�?
      expect(c.displayName, 'GTV Electronic Sports');
    });
  });
}
