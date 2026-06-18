// v0.3.5.5 P0 bug fix: 全屏模式下"取消全屏"按钮永远 visible — 不参与
// _controlsVisible 3s 隐身.
//
// 验证 (3 case):
//   1. 全屏 + 控件隐身时, TopBar 仍然 visible (含 back/clock/favorite 跟
//      退出全屏按钮). 旧版 TopBar 整个在 AnimatedOpacity 内, 3s 后跟着隐.
//   2. 全屏 + 控件显示时, TopBar + 控件层 (节目卡 + 频道横滑) 都 visible.
//   3. 控件层 (节目卡 + 频道横滑) _controlsVisible=false 时 opacity=0,
//      TopBar 跟它分离, 不受 _controlsVisible 影响.

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

/// 强制走全屏 overlay 路径. 物理尺寸 1080x1920, devicePixelRatio=1.0
/// → logical size = 1080x1920 → shortestSide=1080 >= 600 → _isMobile=false
/// → 走 _buildFullscreenOverlay.  (v0.3.5.5 P0 bug fix 改的是这条路径.)
Future<void> _pumpPlayerFullscreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  // devicePixelRatio=1.0: logical size = physical size, shortestSide=1080
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
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
        theme: IptvTheme.light(),
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

  group('PlayerPage v0.3.5.5 TopBar 永远 visible (退出全屏按钮不能 3s 隐)', () {
    testWidgets('全屏 overlay + 控件 3s 隐身后, TopBar (含退出全屏按钮) 仍 visible',
        (tester) async {
      await _pumpPlayerFullscreen(tester);
      // devicePixelRatio=1.0, 物理 1080x1920 → 逻辑 1080x1920, shortestSide=1080
      // → _isMobile=false → 走 _buildFullscreenOverlay 路径.  这是 v0.3.5.5 P0
      // bug fix 改的路径.
      //
      // TopBar 现在在 AnimatedOpacity 外面, 永远 visible.  退出全屏按钮
      // (Icons.fullscreen_exit) 也在 TopBar 内 — 必须随时可点.

      // 1. 等待 3s+ 让 _controlsVisible 走完自动隐身计时
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      await tester.pump();

      // 2. 验证 TopBar 的 back 按钮仍在 — TopBar 不应随 _controlsVisible 隐
      expect(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
        findsOneWidget,
        reason: 'TopBar 应永远 visible — 3s 后 _controlsVisible=false, back 按钮仍在',
      );

      // 3. 验证退出全屏按钮仍在 TopBar 内 (v0.3.5.5 P0 fix 关键)
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — 退出全屏按钮现在在 TopBar 内, 永远 visible. '
            '原来在 _buildFullscreenOverlay 里单独 Positioned, 跟 TopBar 一起'
            '3s 隐, 体验严重 bug.',
      );

      // 4. 验证控件层已隐 (opacity=0)
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget,
          reason: '控件层应该只有 1 个 AnimatedOpacity');
      final opacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacity.opacity, equals(0.0),
          reason: '控件层 _controlsVisible=false 时 opacity=0 (节目卡 + 频道横滑隐)');
    });

    testWidgets('全屏 overlay + 控件显示时, TopBar + 退出全屏按钮 + 控件层都 visible',
        (tester) async {
      await _pumpPlayerFullscreen(tester);

      // 刚 pump 完, _controlsVisible=true (postFrameCallback 启动计时器, 还没
      // 到 3s).  验证 opacity=1.0:
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);
      final opacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacity.opacity, equals(1.0),
          reason: '控件层 _controlsVisible=true 时 opacity=1.0 (控件显示)');

      // TopBar 的 back 按钮在
      expect(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
        findsOneWidget,
        reason: 'TopBar 永远 visible — _controlsVisible=true 时 back 按钮在',
      );

      // 退出全屏按钮也在 TopBar 内 (v0.3.5.5 新加)
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsOneWidget,
        reason: 'v0.3.5.5 — 退出全屏按钮在 TopBar 内, _controlsVisible=true 时也在',
      );
    });

    testWidgets('TopBar 跟 AnimatedOpacity 分离 — 控件隐时 TopBar 仍 visible, 反之亦然',
        (tester) async {
      await _pumpPlayerFullscreen(tester);

      // 1. _controlsVisible=true: back + more_vert + fullscreen_exit 都在
      expect(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
        findsOneWidget,
        reason: '初始 _controlsVisible=true, TopBar back 按钮在',
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.more_vert),
        findsOneWidget,
        reason: 'TopBar 内的 more_vert 按钮在',
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsOneWidget,
        reason: 'v0.3.5.5 — 退出全屏按钮在 TopBar 内, _controlsVisible=true 时在',
      );

      // 2. 等 3s+ 让 _controlsVisible 变 false
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      await tester.pump();

      // 3. 控件层已隐 (opacity=0)
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, equals(0.0), reason: '控件层已隐');

      // 4. 关键: TopBar 3 个按钮 (back / more_vert / fullscreen_exit) 都仍在
      // v0.3.5.5 P0 fix: TopBar 移到 AnimatedOpacity 外面, 跟控件层分离.
      expect(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — TopBar 移到 AnimatedOpacity 外面, 永远 visible',
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.more_vert),
        findsOneWidget,
        reason: 'TopBar more_vert 也永远 visible',
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — 退出全屏按钮永远 visible, 用户随时能退出全屏',
      );
    });

    testWidgets('回归: 移动端嵌入布局不显示退出全屏按钮 (onExitFullscreen=null)', (tester) async {
      // 移动端嵌入布局: devicePixelRatio=2.0, 物理 1080x1920 → 逻辑 540x960
      // → shortestSide=540 < 600 → _isMobile=true → 走 _buildMobile.
      // _buildMobile 调 _TopBar 不传 onExitFullscreen, TopBar 内不渲染
      // Icons.fullscreen_exit 按钮.
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 1920);
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
            theme: IptvTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 移动端嵌入布局有 entry 全屏按钮 (Icons.fullscreen 在视频右下角)
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen),
        findsOneWidget,
        reason: '移动端嵌入布局 — 视频右下角有"进入全屏"按钮',
      );
      // 移动端嵌入布局没退出全屏按钮 (还没进全屏, 不需要退出)
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsNothing,
        reason: '移动端嵌入布局 — 不渲染"退出全屏"按钮 (onExitFullscreen=null)',
      );
    });
  });
}
