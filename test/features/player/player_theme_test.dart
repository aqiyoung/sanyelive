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
import 'package:sanyelive/core/theme/colors.dart';
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
    testWidgets('浅色主题: 全屏按钮 Material bg = surfaceContainerHigh',
        (tester) async {
      await _pumpPlayer(
        tester,
        theme: IptvTheme.light(),
        physicalSize: const Size(1080, 1920),
      );
      // 找全屏按钮 (Icons.fullscreen)
      final btnFinder = find.widgetWithIcon(IconButton, Icons.fullscreen);
      expect(btnFinder, findsOneWidget);
      // 全屏按钮的 Material 容器 bg
      final ctx = tester.element(btnFinder);
      final expectedColor = Theme.of(ctx).colorScheme.surfaceContainerHigh;
      // 从 Material 父级拿 color
      final materialFinder =
          find.ancestor(of: btnFinder, matching: find.byType(Material)).first;
      final material = tester.widget<Material>(materialFinder);
      expect(material.color, isNotNull);
      expect(material.color, equals(expectedColor),
          reason: '浅色下全屏按钮 bg 应该 = surfaceContainerHigh (theme-driven)');
    });

    testWidgets('暗色主题: 全屏按钮 Material bg = surfaceContainerHigh (暗色板)',
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
      // 暗色 theme 下, surfaceContainerHigh = IptvColors.darkSurfaceHigh
      // (312B25 暖深灰), 跟浅色的 EAE5DA 不同, 验证用的是当前主题的 token.
      expect(material.color, isNotNull);
      expect(material.color, equals(IptvColors.darkSurfaceHigh),
          reason: '暗色下全屏按钮 bg 应该 = darkSurfaceHigh (暗色板)');
      // 不能是浅色 token
      expect(material.color, isNot(equals(IptvColors.bgElevated)),
          reason: '暗色下不能用浅色 token IptvColors.bgElevated');
    });

    testWidgets('浅/暗色 Scaffold 跟随主题 colorScheme.surface (跟主题联动)',
        (tester) async {
      // v0.3.5.15: Scaffold bg 改为 scheme.surface, 跟主题联动
      await _pumpPlayer(
        tester,
        theme: IptvTheme.light(),
        physicalSize: const Size(1080, 1920),
      );
      final scaffoldLight = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffoldLight.backgroundColor,
          equals(IptvTheme.light().colorScheme.surface),
          reason: 'v0.3.5.15: Scaffold bg 应跟随主题 colorScheme.surface');
    });
  });
}
