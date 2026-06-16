import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 验证打包后 assets/data/channels_cn.json 的内容契约
/// 卡 6 验收: 真流注入, 至少要有一部分频道带 sources
void main() {
  group('assets/data/channels_cn.json', () {
    final raw = File('assets/data/channels_cn.json').readAsStringSync();
    final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();

    test('channels 数组非空', () {
      expect(list, isNotEmpty);
    });

    test('channels 数量在合理范围 (50..500)', () {
      expect(list.length, greaterThanOrEqualTo(50));
      expect(list.length, lessThanOrEqualTo(500));
    });

    test('每个 channel 都有 id/name', () {
      for (final c in list) {
        expect(c['id'], isA<String>(), reason: 'channel without id: $c');
        expect(c['id'], isNotEmpty);
        expect(c['name'], isA<String>());
      }
    });

    test('id 唯一', () {
      final ids = list.map((c) => c['id'] as String).toSet();
      expect(ids.length, list.length, reason: '有重复 id');
    });

    test('卡 6 注入: 至少 30 个频道有 sources (iptv-org 覆盖率 ~20%)', () {
      final withSources = list
          .where((c) => (c['sources'] as List?)?.isNotEmpty ?? false)
          .length;
      expect(
        withSources,
        greaterThanOrEqualTo(30),
        reason: '只有 $withSources 个频道带 source, 少于 30',
      );
    });

    test('每个 channel 的 sources 数量 ≤ 5 (SourceFailover 不会跳 5 个源)', () {
      for (final c in list) {
        final sources = (c['sources'] as List?)?.cast<String>() ?? const [];
        expect(
          sources.length,
          lessThanOrEqualTo(5),
          reason: '${c['id']} 有 ${sources.length} 个 sources',
        );
      }
    });

    test('sources 都是 http(s) URL', () {
      for (final c in list) {
        final sources = (c['sources'] as List?)?.cast<String>() ?? const [];
        for (final s in sources) {
          expect(
            s.startsWith('http://') || s.startsWith('https://'),
            true,
            reason: '非法 source URL: $s',
          );
          expect(
            s.endsWith('.m3u8') || s.contains('.m3u8'),
            true,
            reason: 'source 不是 m3u8: $s',
          );
        }
      }
    });

    test('categories 至少一个, 主分类在允许集合内', () {
      const allowed = <String>{
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
        'culture',
      };
      for (final c in list) {
        final cats = (c['categories'] as List?)?.cast<String>() ?? const [];
        expect(cats, isNotEmpty, reason: '${c['id']} 没 categories');
        expect(allowed.contains(cats.first), true,
            reason: '${c['id']} 主分类 ${cats.first} 不在允许集合');
      }
    });
  });
}
