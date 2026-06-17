// �?4 集成测试 �?主页 �?分类 �?详情 跳转流程
// �?ProviderScope.overrides 注入 fake channels, 不依�?assets
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:threelive/core/router/router.dart';
import 'package:threelive/core/theme/theme.dart';
import 'package:threelive/data/models/channel.dart';
import 'package:threelive/data/repositories/channel_repository.dart';
import 'package:threelive/features/favorites/favorites_service.dart';
import 'package:threelive/services/player_service.dart';
import 'package:threelive/services/source_failover.dart';
import 'package:threelive/services/startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// VideoController fake �?测试环境不能 instantiate �?Player
class _FakeVideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 6/17 修声音残�? PlayerService �?Player 实例�? 测试环境需提供一�?fake.
///  Player() �?libmpv native, 测试 env 没有.  noSuchMethod 让大多数调用�?
///  default 路径, �?stop() / dispose() 必须返回 Future<void>, 不然
///  PlayerService.dispose() �?unawaited() 会报 type error.
class _FakePlayer implements Player {
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 空的 StreamOpener �?�?player 页面顺利 mount (不实�?open)
class _NoopOpener implements StreamOpener {
  @override
  Future<bool> open(String url, {required Duration timeout}) async => false;
}

/// ChannelRepository fake �?返回预置频道, 避免 assets 加载
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
      // 6/17 修声音残�? PlayerService 现在会读 mediaKitPlayerProvider,
      // 测试环境注入 fake,  避免 instantiate �?native player.
      mediaKitPlayerProvider.overrideWithValue(_FakePlayer()),
      streamOpenerProvider.overrideWithValue(_NoopOpener()),
      // �?6: HomePage 现在需�?StartupService + FavoritesService
      startupServiceProvider.overrideWithValue(StartupService()),
      favoritesServiceProvider.overrideWithValue(
        FavoritesService(store: InMemoryFavoritesStore()),
      ),
    ];

Widget _app() => MaterialApp.router(
      theme: IptvTheme.light(),
      routerConfig: buildRouter(),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('home �?category (cctv) shows CCTV channels', (tester) async {
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

  testWidgets('home �?category (satellite) shows Hunan', (tester) async {
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

  testWidgets('home �?category �?player route pushed', (tester) async {
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

    // 频道名出现在 player topbar (CCTV-1 + 其它描述, �?CCTV-1 至少 1 �?
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
