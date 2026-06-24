/// cctv_source_test.dart — CCTV 源选择器 + dispatcher 单元测试
///
/// 8 case (按 threely 卡 6.18 立的 "5 case 铁律" + 3 额外覆盖):
///   1. Channel.fromJson 解析 cctvSource 字段 (string + dict 混存)
///   1b. 老 channels_cn.json 没有 cctvSource 字段 → 默认空数组
///   2. CctvSourcePicker.isCctvMainChannel 判别 18 频道
///   3. pickSources 优先级 cctvSource > sources > known_sources
///   4. cctvSource 为空 → 降级到 sources + known_sources (老逻辑)
///   4b. cctvSource 跟 sources 重复 → 去重, cctvSource 在前
///   5. SourceDispatcher.dispatch CCTV 走 cctvSource, 非 CCTV 走 sources
///   5b. SourceDispatcher.traceDispatch CCTV 频道详细 trace
///   health. CctvSourcePicker.healthScore 已知 URL 拿分, 未知 0.5
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/source_dispatcher.dart';

void main() {
  group('cctvSource_test (v0.3.5.3 6/18)', () {
    test('case 1: Channel.fromJson 解析 cctvSource (string + dict 混存)', () {
      // 跟 v0.3.5.1 的 sources dict 解析对齐 — cctvSource 也容忍 dict 格式
      final c = Channel.fromJson({
        'id': 'CCTV1.cn',
        'name': 'CCTV-1',
        'country': 'CN',
        'categories': ['general'],
        'sources': [
          'http://legacy.example.com/cctv1.m3u8',
          {
            'url': 'http://iptv.org/cctv1.m3u8',
            'type': 'hls',
          },
        ],
        'cctvSource': [
          'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8',
          {
            'url': 'https://xykt-fix.github.io/play/a02a/index.m3u8',
            'type': 'hls',
          },
        ],
      });
      expect(c.id, 'CCTV1.cn');
      // sources 字段: 两条都解析
      expect(c.sources, <String>[
        'http://legacy.example.com/cctv1.m3u8',
        'http://iptv.org/cctv1.m3u8',
      ]);
      // cctvSource 字段: 两条都解析 (string + dict)
      expect(c.cctvSource, <String>[
        'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8',
        'https://xykt-fix.github.io/play/a02a/index.m3u8',
      ]);
    });

    test('case 1b: 老 channels_cn.json 没有 cctvSource 字段 → 默认空数组', () {
      // 向后兼容: v0.3.5.3 之前的 channels_cn.json 没 cctvSource 字段,
      // Channel.fromJson 必须默认 const <String>[] (空数组), 不抛错.
      final c = Channel.fromJson({
        'id': 'CCTV5.cn',
        'name': 'CCTV-5',
        'country': 'CN',
        'categories': ['sports'],
        'sources': ['http://legacy/cctv5.m3u8'],
      });
      expect(c.cctvSource, isEmpty);
    });

    test('case 2: CctvSourcePicker.isCctvMainChannel 判别 18 CCTV 主频道', () {
      // 18 个主频道 (CCTV1-17 + 5Plus + 4K) 都应该是 true
      for (final id in [
        'CCTV1.cn',
        'CCTV2.cn',
        'CCTV3.cn',
        'CCTV4.cn',
        'CCTV5.cn',
        'CCTV5Plus.cn',
        'CCTV6.cn',
        'CCTV7.cn',
        'CCTV8.cn',
        'CCTV9.cn',
        'CCTV10.cn',
        'CCTV11.cn',
        'CCTV12.cn',
        'CCTV13.cn',
        'CCTV14.cn',
        'CCTV15.cn',
        'CCTV16.cn',
        'CCTV17.cn',
        'CCTV4K.cn',
      ]) {
        final c = Channel(
          id: id,
          name: id,
          country: 'CN',
          categories: const ['general'],
        );
        expect(
          CctvSourcePicker.isCctvMainChannel(c),
          isTrue,
          reason: '$id 应该是 CCTV 主频道',
        );
      }

      // 数字频道 (Billiards / Storm / Plus / Opera) 不算主频道
      for (final id in [
        'CCTVPlus1.cn',
        'CCTVPlus2.cn',
        'CCTV4America.cn',
        'CCTV4Asia.cn',
        'CCTV4Europe.cn',
        'CCTVBilliards.cn',
        'CCTVStormFootball.cn',
        'CCTVGolfTennis.cn',
        'CCTVWeaponTechnology.cn',
      ]) {
        final c = Channel(
          id: id,
          name: id,
          country: 'CN',
          categories: const ['general'],
        );
        expect(
          CctvSourcePicker.isCctvMainChannel(c),
          isFalse,
          reason: '$id 不应该是 CCTV 主频道 (是子频道)',
        );
      }
    });

    test('case 3: pickSources 优先级 cctvSource[0] > sources[0] > known_sources',
        () {
      // CCTV-1 模拟 3 层源
      const c = Channel(
        id: 'CCTV1.cn',
        name: 'CCTV-1',
        country: 'CN',
        categories: ['general'],
        sources: <String>[
          'http://iptv-org/cctv1.m3u8',
          'http://legacy/cctv1.m3u8',
        ],
        cctvSource: <String>[
          'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8',
          'http://198.204.240.250:82/live/cctv1.m3u8',
        ],
      );

      final known = <String, List<String>>{
        'CCTV1.cn': <String>['http://known-fallback/cctv1.m3u8'],
      };

      final picked = CctvSourcePicker.pickSources(
        c,
        knownSources: known,
      );

      // 顺序: cctvSource[0], cctvSource[1], sources[0], sources[1], known[0]
      expect(picked, <String>[
        'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8',
        'http://198.204.240.250:82/live/cctv1.m3u8',
        'http://iptv-org/cctv1.m3u8',
        'http://legacy/cctv1.m3u8',
        'http://known-fallback/cctv1.m3u8',
      ]);
    });

    test('case 4: cctvSource 为空 → 降级到 sources + known_sources (老逻辑)', () {
      // 老 release 升级, cctvSource 字段缺失 (空数组), 必须降级到老逻辑,
      // 不丢源 (channel.sources + known_sources).
      const c = Channel(
        id: 'CCTV1.cn',
        name: 'CCTV-1',
        country: 'CN',
        categories: ['general'],
        sources: <String>[
          'http://iptv-org/cctv1.m3u8',
        ],
        cctvSource: <String>[], // v0.3.5.3 之前默认
      );

      final known = <String, List<String>>{
        'CCTV1.cn': <String>['http://known/cctv1.m3u8'],
      };

      final picked = CctvSourcePicker.pickSources(
        c,
        knownSources: known,
      );

      // 没 cctvSource, 走老逻辑: sources + known
      expect(picked, <String>[
        'http://iptv-org/cctv1.m3u8',
        'http://known/cctv1.m3u8',
      ]);
    });

    test('case 4b: cctvSource 跟 sources 重复 → 去重, cctvSource 在前', () {
      // 同 URL 在 cctvSource 和 sources 都有, cctvSource 优先, sources 那份不重复加
      const c = Channel(
        id: 'CCTV6.cn',
        name: 'CCTV-6',
        country: 'CN',
        categories: ['movies'],
        sources: <String>[
          'http://198.204.240.250:82/live/cctv6.m3u8', // 跟 cctvSource[0] 重复
          'http://iptv-org/cctv6.m3u8',
        ],
        cctvSource: <String>[
          'http://198.204.240.250:82/live/cctv6.m3u8', // 重复
        ],
      );

      final picked = CctvSourcePicker.pickSources(c);

      // 198.204.240.250 只出现一次 (在 cctvSource 位置), iptv-org 跟在后面
      expect(picked, <String>[
        'http://198.204.240.250:82/live/cctv6.m3u8',
        'http://iptv-org/cctv6.m3u8',
      ]);
    });

    test(
        'case 5: SourceDispatcher.dispatch CCTV 走 cctvSource, 非 CCTV 走 sources',
        () {
      // CCTV 频道: dispatch 走 cctvSource 优先
      const cctvChannel = Channel(
        id: 'CCTV1.cn',
        name: 'CCTV-1',
        country: 'CN',
        categories: <String>['general'],
        sources: <String>['http://iptv-org/cctv1.m3u8'],
        cctvSource: <String>[
          'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8',
        ],
      );
      final cctvResult = SourceDispatcher.dispatch(cctvChannel);
      expect(cctvResult.first,
          'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8',
          reason: 'CCTV-1 应该用 cctvSource[0]');

      // CCTV 数字频道 (Billiards) 走 sources (cctvSource 字段空, 老逻辑)
      const cctvSubChannel = Channel(
        id: 'CCTVBilliards.cn',
        name: 'CCTV-台球',
        country: 'CN',
        categories: <String>['sports'],
        sources: <String>[
          'http://38.75.136.137:98/gslb/dsdqpub/ystq.m3u8?auth=testpub'
        ],
      );
      final cctvSubResult = SourceDispatcher.dispatch(cctvSubChannel);
      expect(
          cctvSubResult,
          <String>[
            'http://38.75.136.137:98/gslb/dsdqpub/ystq.m3u8?auth=testpub',
          ],
          reason: 'CCTV 子频道走老逻辑 (channel.sources)');

      // 非 CCTV (卫视) 走 channel.sources (老逻辑)
      const nonCctv = Channel(
        id: 'BeijingSatelliteTV.cn',
        name: '北京卫视',
        country: 'CN',
        categories: <String>['general'],
        sources: <String>['http://go.bkpcp.top/mg/bjws'],
      );
      final nonCctvResult = SourceDispatcher.dispatch(nonCctv);
      expect(nonCctvResult, <String>['http://go.bkpcp.top/mg/bjws']);
    });

    test('case 5b: SourceDispatcher.traceDispatch CCTV 频道详细 trace', () {
      // 调试用, 验证 trace 正确标识 cctvSource 优先策略
      const c = Channel(
        id: 'CCTV4.cn',
        name: 'CCTV-4',
        country: 'CN',
        categories: <String>['general'],
        sources: <String>['http://iptv-org/cctv4.m3u8'],
        cctvSource: <String>['https://xykt-fix.github.io/play/a02a/index.m3u8'],
      );

      final trace = SourceDispatcher.traceDispatch(c);
      expect(trace.channelId, 'CCTV4.cn');
      expect(trace.strategy, 'cctv_priority');
      expect(trace.cctvSourcesUsed, 1);
      expect(trace.legacySourcesUsed, 1);
      expect(trace.pickedSource,
          'https://xykt-fix.github.io/play/a02a/index.m3u8');
      expect(trace.strategyDetail, contains('cctvSource[0]'));
    });

    test('case health: CctvSourcePicker.healthScore 已知 URL 拿分, 未知 0.5', () {
      // 已知 URL 拿 0.95 (Tencent Cloud 官方 CDN)
      expect(
        CctvSourcePicker.healthScore(
          'http://ldncctvwbcdtxy.liveplay.myqcloud.com/ldncctvwbcd/cdrmldcctv1_1/index.m3u8',
        ),
        0.95,
      );
      // 未知 URL 默认 0.5
      expect(
        CctvSourcePicker.healthScore('http://unknown.example.com/cctv1.m3u8'),
        0.5,
      );
    });
  });
}
