// 卡 6 验证: mergeKnownSources 把 known_sources 追加到 channel.sources 后面,
// 不覆盖.  iptv-org 高画质源 (channels_cn.json 已 bake) 必须保留在前面.
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/data/models/channel.dart';
import 'package:iptv_app/data/repositories/channel_repository.dart';

void main() {
  group('mergeKnownSources', () {
    const xWithSources = Channel(
      id: 'X.cn',
      name: 'X',
      country: 'CN',
      categories: <String>['news'],
      sources: <String>['http://a.com/1.m3u8', 'https://b.com/2.m3u8'],
    );
    const yNoSources = Channel(
      id: 'Y.cn',
      name: 'Y',
      country: 'CN',
      categories: <String>['news'],
    );

    test('channels_cn.json 已有 sources → known 追加在后面', () {
      final result = mergeKnownSources(
        <Channel>[xWithSources, yNoSources],
        <String, dynamic>{
          'X.cn': <String>['http://known.example/x.m3u8'],
          'Y.cn': <String>['http://known.example/y.m3u8'],
        },
      );

      final x = result.firstWhere((c) => c.id == 'X.cn');
      expect(x.sources, <String>[
        'http://a.com/1.m3u8', // iptv-org 高画质源保持在前
        'https://b.com/2.m3u8',
        'http://known.example/x.m3u8', // known 兑底追加
      ]);

      final y = result.firstWhere((c) => c.id == 'Y.cn');
      expect(y.sources, <String>['http://known.example/y.m3u8']);
    });

    test('known 里的 url 已存在于 channel.sources → 去重, 不重复', () {
      final result = mergeKnownSources(
        <Channel>[xWithSources],
        <String, dynamic>{
          'X.cn': <String>['http://a.com/1.m3u8', 'http://new.com/2.m3u8'],
        },
      );

      final x = result.firstWhere((c) => c.id == 'X.cn');
      expect(x.sources, <String>[
        'http://a.com/1.m3u8', // 首次出现位置保持
        'https://b.com/2.m3u8',
        'http://new.com/2.m3u8', // 新增在末尾
      ]);
    });

    test('known 里没有 channel.id → 保持原样, 不丢源', () {
      final result = mergeKnownSources(
        <Channel>[xWithSources],
        <String, dynamic>{
          'Other.cn': <String>['http://other.example/x.m3u8'],
        },
      );

      final x = result.firstWhere((c) => c.id == 'X.cn');
      // 保持原 channel 实例 (== 引用), sources 不变
      expect(x.sources, xWithSources.sources);
      expect(identical(x, xWithSources), true,
          reason: '没有 known match 时应该返回原 channel 引用');
    });

    test('空 known → 等同 identity (返回原 channel 引用)', () {
      final result = mergeKnownSources(
        <Channel>[xWithSources, yNoSources],
        <String, dynamic>{},
      );
      expect(identical(result[0], xWithSources), true);
      expect(identical(result[1], yNoSources), true);
    });

    test('known 里某 channel 字段是空 list → 不变, 跳过', () {
      final result = mergeKnownSources(
        <Channel>[xWithSources],
        <String, dynamic>{'X.cn': <String>[]},
      );
      final x = result.firstWhere((c) => c.id == 'X.cn');
      expect(x.sources, xWithSources.sources);
    });
  });
}
