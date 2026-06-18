// v0.3.5.4 主题适配真修: 浅色+暗色都验证 player_page chrome 颜色
//
// 验证:
//   1. 浅色主题下, 全屏按钮 (fullscreen + fullscreen_exit) 背景用
//      colorScheme.surfaceContainerHigh (跟浅米色页面风格一致),
//      图标用 colorScheme.onSurface (深棕) 跟浅底对比.
//   2. 暗色主题下, 同样的 widget 用暗色板 (深底 + 浅色图标).
//   3. Scaffold 仍是 Colors.black (视频区, 不跟主题联动).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/player/player_page.dart';
import 'package:sanyelive/services/player_service.dart';
import 'package:sanyelive/services/source_failover.dart';
import 'package:sanyelive/services/startup_service.dart';

const _channels = <Channel>[
  Channel(
    id: 'CCTV1.cn',
    name: 'CCTV-1 综合',
    country: 'CN',
    categories: ['general'],
    sources: ['http://1'],
  ),
  Channel(
    id: 'CCTV2.cn',
    name: 'CCTV-2 财经',
    country: 'CN',
    categories: ['general'],
    sources: ['http://2'],
  ),
];

class _ScriptedOpener implements StreamOpener {
  _ScriptedOpener(this._scripted);
  final List<bool> _scripted;
  int _idx = 0;
  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    final i = _idx++;
    if (i >= _scripted.length) return false;
    return _scripted[i];
  }
}

class _FakeChannelRepository implements ChannelRepository {
  _FakeChannelRepository(this._channels);
  final List<Channel> _channels;
  @override
  Future<List<Channel>> loadBundled() async => _channels;
}

class _FakeVideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePlayer implements Player {
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpPlayer(
  WidgetTester tester, {
  required ThemeData theme,
  required Size physicalSize,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);

  final opener = _ScriptedOpener([false, false]);
  final router = GoRouter(
    initialLocation: '/player/CCTV1.cn',
    routes: [
      GoRoute(
        path: '/player/:channelId',
        builder: (_, state) => PlayerPage(
          channelId: state.pathParameters['channelId']!,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        streamOpenerProvider.overrideWithValue(opener),
        channelRepositoryProvider
            .overrideWith((ref) => _FakeChannelRepository(_channels)),
        mediaKitVideoControllerProvider
            .overrideWithValue(_FakeVideoController()),
        mediaKitPlayerProvider.overrideWithValue(_FakePlayer()),
        startupServiceProvider.overrideWithValue(StartupService()),
        favoritesServiceProvider.overrideWithValue(
          FavoritesService(store: InMemoryFavoritesStore()),
        ),
      ],
      child: MaterialApp.router(
        theme: theme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlayerPage v0.3.5.4 主题适配 (浅色+暗色)', () {
    testWidgets('浅色主题: 全屏按钮 Material bg = transparent (v0.3.5.19)',
        (tester) async {
      await _pumpPlayer(
        tester,
        theme: IptvTheme.light(),
        physicalSize: const Size(1080, 1920),
      );
      final btnFinder = find.widgetWithIcon(IconButton, Icons.fullscreen);
      expect(btnFinder, findsOneWidget);

      // v0.3.5.19: 全屏按钮背景改透明, 不再用 surfaceContainerHigh
      final materialFinder =
          find.ancestor(of: btnFinder, matching: find.byType(Material)).first;
      final material = tester.widget<Material>(materialFinder);
      expect(material.color, equals(Colors.transparent),
          reason: 'v0.3.5.19: 全屏按钮 bg 应该 = transparent');
    });

    testWidgets('暗色主题: 全屏按钮 Material bg = transparent (v0.3.5.19)',
        (tester) async {
      await _pumpPlayer(
        tester,
        theme: IptvTheme.dark(),
        physicalSize: const Size(1080, 1920),
      );
      final btnFinder = find.widgetWithIcon(IconButton, Icons.fullscreen);
      expect(btnFinder, findsOneWidget);
      final materialFinder =
          find.ancestor(of: btnFinder, matching: find.byType(Material)).first;
      final material = tester.widget<Material>(materialFinder);
      expect(material.color, equals(Colors.transparent),
          reason: 'v0.3.5.19: 暗色下全屏按钮 bg 应该 = transparent');
    });

    testWidgets('视频区 Scaffold bg = Colors.black (v0.3.5.19)', (tester) async {
      // v0.3.5.19: 视频区纯黑底, 不跟主题联动
      await _pumpPlayer(
        tester,
        theme: IptvTheme.light(),
        physicalSize: const Size(1080, 1920),
      );
      final scaffoldLight = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffoldLight.backgroundColor, equals(Colors.black),
          reason: 'v0.3.5.19: 视频区 Scaffold bg 应 = Colors.black');
    });
  });
}
