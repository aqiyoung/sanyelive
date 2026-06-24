// v0.3.7+50 (6/19): SourceFailover 按 health_score 优先选源 (top-1 优先),
// A fail 才换 B, B fail 才换 C.  这是老板 11:12 反馈"加载慢"的关键
// 优化:  直接选最快源, 不用试错.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanyelive/data/cctv_source.dart';

void main() {
  // v0.3.7+57: 跟 source_failover_test 同样原因 — 调用 sortByHealthScore
  // 跟 SharedPreferences 无直接关系,  但保持一致性防 future regression.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('sortByHealthScore', () {
    test('A score=0.9, B=0.6, C=0.3 → 优先选 A', () {
      final sources = <CctvSource>[
        const CctvSource(
            url: 'http://a.com/playlist.m3u8',
            score: 0.9,
            method: 'tencent_cloud'),
        const CctvSource(
            url: 'http://b.com/playlist.m3u8', score: 0.6, method: 'legacy'),
        const CctvSource(
            url: 'http://c.com/playlist.m3u8', score: 0.3, method: 'legacy'),
      ];
      final sorted = sortByHealthScore(sources);
      expect(sorted.first.url, 'http://a.com/playlist.m3u8');
      expect(sorted.first.score, 0.9);
    });

    test('死源 (score=0) 排最后', () {
      final sources = <CctvSource>[
        const CctvSource(
            url: 'http://dead.com/playlist.m3u8', score: 0.0, method: 'legacy'),
        const CctvSource(
            url: 'http://alive.com/playlist.m3u8',
            score: 0.7,
            method: 'tencent_cloud'),
      ];
      final sorted = sortByHealthScore(sources);
      expect(sorted.first.url, 'http://alive.com/playlist.m3u8');
      expect(sorted.last.url, 'http://dead.com/playlist.m3u8');
    });

    test('空列表 → 返回空', () {
      final sorted = sortByHealthScore(<CctvSource>[]);
      expect(sorted, isEmpty);
    });

    test('同分 → 保持输入顺序 (stable sort)', () {
      final sources = <CctvSource>[
        const CctvSource(
            url: 'http://first.com/playlist.m3u8', score: 0.8, method: 'a'),
        const CctvSource(
            url: 'http://second.com/playlist.m3u8', score: 0.8, method: 'b'),
      ];
      final sorted = sortByHealthScore(sources);
      expect(sorted[0].url, 'http://first.com/playlist.m3u8');
      expect(sorted[1].url, 'http://second.com/playlist.m3u8');
    });
  });
}
