// 卡 4 集成测试 — 主页 → 分类 → 详情 跳转流程
// 用 ProviderScope.overrides 注入 fake channels, 不依赖 assets
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:sanyelive/core/router/router.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/services/player_service.dart';
import 'package:sanyelive/services/source_failover.dart';
import 'package:sanyelive/services/startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sanyelive/data/sources/remote_sources_source.dart';

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

/// 6/17 修声音残留: PlayerService 拿 Player 实例后, 测试环境需提供一个 fake.
///  Player() 调 libmpv native, 测试 env 没有.  noSuchMethod 让大多数调用走
///  default 路径, 但 stop() / dispose() 必须返回 Future<void>, 不然
///  PlayerService.dispose() 里 unawaited() 会报 type error.
class _FakePlayer implements Player {
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 空的 StreamOpener — 让 player 页面顺利 mount (不实际 open)
class _NoopOpener implements StreamOpener {
  @override
  Future<bool> open(String url, {required Duration timeout}) async => false;

  @override
  Future<void> cancel(String url) async {}
}

/// ChannelRepository fake — 返回预置频道, 避免 assets 加载
/// v0.3.10.8: channelsProvider body 走远端 enrich, 测试不连 HTTP + sqflite.
/// 返空 bundle → _enrichWithRemoteSources 走 fallback (保持本地).
class _FakeEmptyRemoteSourcesNotifier extends RemoteSourcesNotifier {
  @override
  Future<RemoteSourcesBundle> build() async {
    return const RemoteSourcesBundle(
      meta: {},
      known: {},
      dead: {},
    );
  }
}

class _FakeRepo extends ChannelRepository {
  const _FakeRepo(this._channels);
  final List<Channel> _channels;
  @override
  Future<List<Channel>> loadBundled() async => _channels;
}

List<Override> _testOverrides() => <Override>[
      channelsProvider.overrideWith((ref) async => _kFixtureChannels),
      channelsStreamProvider.overrideWith((ref) async* {
        yield _kFixtureChannels;
      }),
      channelRepositoryProvider
          .overrideWithValue(const _FakeRepo(_kFixtureChannels)),
      mediaKitVideoControllerProvider.overrideWithValue(_FakeVideoController()),
      // 6/17 修声音残留: PlayerService 现在会读 mediaKitPlayerProvider,
      // 测试环境注入 fake,  避免 instantiate 真 native player.
      mediaKitPlayerProvider.overrideWithValue(_FakePlayer()),
      streamOpenerProvider.overrideWithValue(_NoopOpener()),
      remoteSourcesProvider.overrideWith(_FakeEmptyRemoteSourcesNotifier.new),
      // 卡 6: HomePage 现在需要 StartupService + FavoritesService
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
  setUpAll(() async {
    sqflite_ffi.sqfliteFfiInit();
    databaseFactory = sqflite_ffi.databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home renders category cards', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(),
        child: _app(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // 验证主页渲染了分类卡片
    expect(find.text('央视'), findsOneWidget);
    expect(find.text('卫视'), findsOneWidget);
  });

  testWidgets('home → category (cctv) shows CCTV channels', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(),
        child: _app(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // 点击央视分类
    await tester.tap(find.text('央视'));
    await tester.pumpAndSettle();

    // 进入分类页后应该能看到 CCTV 频道
    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('CCTV-2'), findsOneWidget);
    expect(find.text('Hunan Satellite TV'), findsNothing);
  });
}
