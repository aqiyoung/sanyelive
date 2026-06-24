import 'package:flutter_test/flutter_test.dart';

import 'package:sanyelive/data/models/channel.dart';

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
      // v0.3.10.16: categories 从属性推导, 不再直接用 JSON 值
      expect(c.categories, <String>['央视']);
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

    test('primaryCategory: US channel → 国际', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.us',
        'name': 'X',
        'country': 'US',
        'categories': <String>[],
      });
      expect(c.primaryCategory, '国际');
    });

    test('primaryCategory: CN news channel → 新闻', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'X.cn',
        'name': '新闻频道',
        'country': 'CN',
        'categories': <String>['news', 'general'],
      });
      expect(c.primaryCategory, '新闻');
    });
  });

  test('Channel.toJson roundtrips', () {
    const c = Channel(
      id: 'A.cn',
      name: 'A',
      country: 'CN',
      categories: <String>['新闻'],
    );
    final j = c.toJson();
    final c2 = Channel.fromJson(j);
    expect(c2.id, c.id);
    expect(c2.name, c.name);
    expect(c2.country, c.country);
    // categories 会从属性推导, 只要 JSON 非空就不会被覆盖为空
    expect(c2.categories, isNotEmpty);
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

  // 卡 7 (6/17 老板需求): 频道名自动优先中文, 手工映射兑底.
  group('displayName / displaySubtitle (中文化)', () {
    test('中文 alt_names 优先 (CCTV-13 → 央视新闻)', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CCTV13.cn',
        'name': 'CCTV-13',
        'country': 'CN',
        'alt_names': <String>['CCTV-13 新闻', '中国中央电视台新闻频道'],
      });
      expect(c.displayName, 'CCTV-13 新闻');
    });

    test('CGTN 手工映射: 原始 name 英文没中文 alt, 从映射表取', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CGTNArabic.cn',
        'name': 'CGTN Arabic',
        'country': 'CN',
        'alt_names': <String>['CGTN العربية'],
      });
      // 第一个 alt 包含 Arabic 字符, 但这个含中文 (没), 所以走手工表
      // 手工表 'CGTNArabic.cn' → 'CGTN 阿语'
      expect(c.displayName, 'CGTN 阿语');
    });

    test('中国频道, 手工表里有 id → 用映射名', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CCTVPlus1.cn',
        'name': 'CCTV+ 1',
        'country': 'CN',
        'alt_names': <String>[],
      });
      expect(c.displayName, 'CCTV+ 1 (海外版)');
    });

    test('displaySubtitle: 中文化后, 副标题显示分类名', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CCTV13.cn',
        'name': 'CCTV-13',
        'country': 'CN',
        'alt_names': <String>['CCTV-13 新闻'],
      });
      expect(c.displayName, 'CCTV-13 新闻');
      // v0.3.10.16: 副标题显示分类名 (不再显示英文原名)
      expect(c.displaySubtitle, '央视');
    });

    test('displaySubtitle: 国际频道 → 国际', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CNN.us',
        'name': 'CNN',
        'country': 'US',
        'alt_names': <String>[],
      });
      expect(c.displayName, 'CNN');
      expect(c.displaySubtitle, '国际');
    });

    test('非中国频道, 纯英文 → displayName 就是 name', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'CNN.us',
        'name': 'CNN',
        'country': 'US',
        'alt_names': <String>[],
      });
      expect(c.displayName, 'CNN');
    });

    test('手工映射用 name 兑底', () {
      final c = Channel.fromJson(<String, dynamic>{
        'id': 'unknown_id.cn',
        'name': 'GTV Electronic Sports',
        'country': 'CN',
        'alt_names': <String>[],
      });
      // id 不在映射表, name 也不在
      expect(c.displayName, 'GTV Electronic Sports');
    });
  });
}
