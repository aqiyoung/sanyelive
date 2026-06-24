// v0.3.8+133 (6/21 09:49 老板反馈 "地方分类里还有几个卫视"):
// 之前 ChannelFilter.local() 只排除 cctv + satellite,  没排除 international —
// 133 个国际频道错误归到"地方"分类.  修法:  加 international 排除.
// 加这个 test 验证:  local() 不返回任何 international channel.
//
// 历史:  之前没专门给 channel_filter.dart 写 test,  +131 satellite 修法也是
// 默默改的没补 test.  这次 P0 bug 警示 —  分类逻辑没 test 守门,  后续任何
// 重构都可能再次错分类.  补这一组 test 把 4 个分类方法 (cctv / satellite /
// local / international) 全部覆盖.
import 'package:flutter_test/flutter_test.dart';

import 'package:sanyelive/data/channel_filter.dart';
import 'package:sanyelive/data/models/channel.dart';

Channel _ch({
  required String id,
  required String name,
  required String country,
  List<String> altNames = const <String>[],
  List<String> categories = const <String>[],
}) {
  return Channel(
    id: id,
    name: name,
    country: country,
    altNames: altNames,
    categories: categories,
  );
}

void main() {
  // 1 个 CCTV (CN),  1 个卫视 (CN,  id 含 Satellite),  1 个地方 (CN,
  // 不含 Satellite / 不以 CCTV 开头),  1 个香港 (HK),  1 个台湾 (TW),  1 个
  // 澳门 (MO),  1 个美帝 (US),  1 个日本 (JP) — 后 4 个是 international.
  final cctv = _ch(id: 'CCTV1.cn', name: 'CCTV-1', country: 'CN');
  final sat = _ch(id: 'HunanTVSatellite.cn', name: '湖南卫视', country: 'CN');
  final localCn = _ch(id: 'SomeLocalTV.cn', name: '某地市台', country: 'CN');
  final hk = _ch(id: 'TVB.hk', name: 'TVB', country: 'HK');
  final tw = _ch(id: 'TTV.tw', name: '台视', country: 'TW');
  final mo = _ch(id: 'TDM.mo', name: '澳广视', country: 'MO');
  final us = _ch(id: 'CNN.us', name: 'CNN', country: 'US');
  final jp = _ch(id: 'NHK.jp', name: 'NHK', country: 'JP');
  final all = <Channel>[cctv, sat, localCn, hk, tw, mo, us, jp];

  group('ChannelFilter.cctv', () {
    test('matches id starting with CCTV (case-insensitive)', () {
      final r = ChannelFilter.cctv(all);
      expect(r.map((c) => c.id), contains('CCTV1.cn'));
      expect(r.length, 1);
    });
  });

  group('ChannelFilter.satellite', () {
    test('matches id containing Satellite (e.g. HunanTVSatellite)', () {
      final r = ChannelFilter.satellite(all);
      expect(r.map((c) => c.id), contains('HunanTVSatellite.cn'));
    });

    test('matches Chinese alt_name containing 卫视', () {
      final extra = _ch(
        id: 'NoSatInId.cn',
        name: 'NoSat',
        country: 'CN',
        altNames: const <String>['某卫视'],
      );
      final r = ChannelFilter.satellite([...all, extra]);
      expect(r.map((c) => c.id), contains('NoSatInId.cn'));
    });
  });

  group('ChannelFilter.international', () {
    test('matches non-zh countries (US, JP)', () {
      final r = ChannelFilter.international(all);
      final ids = r.map((c) => c.id).toSet();
      expect(ids, contains('CNN.us'));
      expect(ids, contains('NHK.jp'));
    });

    test('excludes zh countries (CN, HK, TW, MO)', () {
      final r = ChannelFilter.international(all);
      final ids = r.map((c) => c.id).toSet();
      expect(ids.contains('CCTV1.cn'), false);
      expect(ids.contains('HunanTVSatellite.cn'), false);
      expect(ids.contains('SomeLocalTV.cn'), false);
      expect(ids.contains('TVB.hk'), false);
      expect(ids.contains('TTV.tw'), false);
      expect(ids.contains('TDM.mo'), false);
    });
  });

  group('ChannelFilter.local (v0.3.8+133 修法)', () {
    test('排除 cctv', () {
      final r = ChannelFilter.local(all);
      expect(r.map((c) => c.id), isNot(contains('CCTV1.cn')));
    });

    test('排除 satellite', () {
      final r = ChannelFilter.local(all);
      expect(r.map((c) => c.id), isNot(contains('HunanTVSatellite.cn')));
    });

    // v0.3.8+133 P0-1 关键回归测试:  之前 local() 没排除 international,
    //  133 个国际频道错进"地方".  现在必须排除 US/JP 等非中文区频道.
    test('排除 international (P0-1 回归)', () {
      final r = ChannelFilter.local(all);
      final ids = r.map((c) => c.id).toSet();
      expect(ids.contains('CNN.us'), false,
          reason: 'v0.3.8+133: local() 必须排除 international');
      expect(ids.contains('NHK.jp'), false,
          reason: 'v0.3.8+133: local() 必须排除 international');
    });

    test('保留 zh non-cctv non-satellite 频道 (HK / TW / MO / CN 本地)', () {
      final r = ChannelFilter.local(all);
      final ids = r.map((c) => c.id).toSet();
      // HK / TW / MO 算中文区 (country 在 zhCountries set),  不属于
      // international,  应该保留在 local.
      expect(ids, contains('TVB.hk'));
      expect(ids, contains('TTV.tw'));
      expect(ids, contains('TDM.mo'));
      expect(ids, contains('SomeLocalTV.cn'));
    });

    test('空列表返回空', () {
      expect(ChannelFilter.local(const <Channel>[]), isEmpty);
    });
  });
}
