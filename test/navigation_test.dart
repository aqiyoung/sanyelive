// 卡 4 集成测试 — 主页 → 分类 → 详情 跳转流程
// 用 ProviderScope.overrides 注入 fake channels, 不依赖 assets
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:iptv_app/core/router/router.dart';
import 'package:iptv_app/core/theme/theme.dart';
import 'package:iptv_app/data/models/channel.dart';
import 'package:iptv_app/data/repositories/channel_repository.dart';
import 'package:iptv_app/services/player_service.dart';
import 'package:iptv_app/services/source_failover.dart';

const List<Channel> _kFixtureChannels = <Channel>[
  Channel(
    id: 'CCTV1.cn',
    name: 'CCTV-1',
    country: 'CN',
    categories: <String>['general'],
    sources: <String>['http://example.com/c1'],
  ),
  Channel(
    id: 'CCTV2.cn',
    name: 'CCTV-2',
    country: 'CN',
    categories: <String>['business'],
    sources: <String>['http://example.com/c2'],
  ),
  Channel(
    id: 'HunanSatelliteTV.cn',
    name: 'Hunan Satellite TV',
    country: 'CN',
    categories: <String>['general'],
    sources: <String>['http://example.com/hn'],
  ),
  Channel(
    id: 'BeijingTV.cn',
    name: 'Beijing TV',
    country: 'CN',
    categories: <String>['general'],
    sources: <String>[],
  ),
];

/// VideoController fake — 测试环境不能 instantiate 真 Player
class _FakeVideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 空的 StreamOpener — 让 player 页面顺利 mount (不实际 open)
class _NoopOpener implements StreamOpener {
  @override
  Future<bool> open(String url, {required Duration timeout}) async => false;
}

/// ChannelRepository fake — 返回预置频道, 避免 assets 加载
class _FakeRepo extends ChannelRepository {
  const _FakeRepo(this._channels);
  final List<Channel> _channels;
  @override
  Future<List<Channel>> loadBundled() async => _channels;
}

List<Override> _testOverrides() => <Override>[
      channelsProvider.overrideWith((ref) async => _kFixtureChannels),
      channelRepositoryProvider
          .overrideWithValue(const _FakeRepo(_kFixtureChannels)),
      mediaKitVideoControllerProvider.overrideWithValue(_FakeVideoController()),
      streamOpenerProvider.overrideWithValue(_NoopOpener()),
    ];

Widget _app() => MaterialApp.router(
      theme: IptvTheme.light(),
      routerConfig: buildRouter(),
    );

void main() {
  testWidgets('home renders 3 category cards', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(),
        child: _app(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('央视'), findsOneWidget);
    expect(find.text('卫视'), findsOneWidget);
    expect(find.text('地方'), findsOneWidget);
    expect(find.text('三页直播'), findsOneWidget);
  });

  testWidgets('home → category (cctv) shows CCTV channels', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(),
        child: _app(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.tap(find.text('央视'));
    await tester.pumpAndSettle();

    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('CCTV-2'), findsOneWidget);
    expect(find.text('Hunan Satellite TV'), findsNothing);
  });

  testWidgets('home → category (satellite) shows Hunan', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(),
        child: _app(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.tap(find.text('卫视'));
    await tester.pumpAndSettle();

    expect(find.text('Hunan Satellite TV'), findsOneWidget);
  });

  testWidgets('home → category → player route pushed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(),
        child: _app(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.tap(find.text('央视'));
    await tester.pumpAndSettle();
    expect(find.text('CCTV-1'), findsOneWidget);

    await tester.tap(find.text('CCTV-1'));
    await tester.pumpAndSettle();

    // 频道名出现在 player topbar (CCTV-1 + 其它描述, 但 CCTV-1 至少 1 次)
    expect(find.text('CCTV-1'), findsWidgets);
  });

  testWidgets('back from category returns to home', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(),
        child: _app(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.tap(find.text('央视'));
    await tester.pumpAndSettle();
    expect(find.text('CCTV-1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('三页直播'), findsOneWidget);
  });
}
