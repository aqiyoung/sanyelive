// v0.3.5.2 (6/18 P1 hotfix) + v0.3.5.5 (P0 bug fix): PlayerPage 全屏覆盖布局测试
// 验证:
//   1. 全屏覆盖布局不再 SafeArea (find.byType(SafeArea) 在全屏覆盖时为 0,
//      在移动嵌入布局时为 1).
//   2. (v0.3.5.5 P0 fix) _TopBar **不参与** _controlsVisible 隐身 — 3s
//      后 _TopBar 仍然 visible, 节目卡 / 频道横滑才跟着隐.  TopBar 含
//      退出全屏按钮, 必须永远 visible (否则用户无法退出全屏).
//   3. 退出全屏按钮 (v0.3.5.5 P0 fix 后) 移进 _TopBar 内, 不再单独
//      Positioned.  全屏时存在, 退出后消失 (回到 _buildMobile 不渲染).
//   4. TV 端 (shortestSide >= 600) 默认就走全屏覆盖 — _TopBar 渲染且
//      永远 visible (v0.3.5.5 P0 fix).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/player/player_page.dart';
import 'package:sanyelive/services/player_service.dart' as ps;
import 'package:sanyelive/services/source_failover.dart';
import 'package:sanyelive/services/startup_service.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlayerPage P1 hotfix 全屏覆盖布局 (v0.3.5.2)', () {
    testWidgets('移动端嵌入布局: 有 SafeArea 包 Stack (v0.3.5 P2-2 行为保留)',
        (tester) async {
      // 6/18 fix: 移动端屏幕 (短边 < 600).  1080x1920 / 2.0 = 540x960 logical, shortestSide=540 < 600=mobile.
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // 移动端嵌入布局: _buildMobile 套了 SafeArea, 应该找到 SafeArea.
      // 关键: 6/18 fix 没有动 _buildMobile, SafeArea 保留.
      expect(
        find.byType(SafeArea),
        findsOneWidget,
        reason: '移动端嵌入布局 (非全屏) 应该 SafeArea 保留 (v0.3.5 行为)',
      );
      // 频道名应该在 _TopBar
      expect(find.text('CCTV-1 综合'), findsOneWidget);
    });

    testWidgets('移动端 → 主动全屏: SafeArea 消失, 视频区填满全屏', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // 全屏前: SafeArea 1 个
      expect(find.byType(SafeArea), findsOneWidget);

      // 点全屏按钮 (在视频区右下角)
      final fullscreenBtn = find.byIcon(Icons.fullscreen);
      expect(fullscreenBtn, findsOneWidget);
      await tester.tap(fullscreenBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 全屏后: SafeArea 应该 0 个 (6/18 fix: 移除 SafeArea)
      expect(
        find.byType(SafeArea),
        findsNothing,
        reason: '全屏覆盖布局不应该有 SafeArea (status bar 已隐, 让视频填满)',
      );
      // 全屏后: 退出全屏按钮 (fullscreen_exit) 出现
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    });

    testWidgets('全屏 (v0.3.5.5 P0 fix): 控件层 3s 后 opacity=0, TopBar 仍 visible',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // 点全屏
      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 全屏时: _TopBar 渲染且可见 (频道名 CCTV-1 综合)
      expect(
        find.text('CCTV-1 综合'),
        findsOneWidget,
        reason: '全屏 + 控件可见时 _TopBar 显示频道名',
      );

      // v0.3.5.5 P0 fix: _TopBar 已移到 AnimatedOpacity 外面.  pump
      // fake clock 过 3s, 控件层 (节目卡 + 频道横滑) 应该 opacity=0,
      // 但 _TopBar 永远 visible — 频道名 (CCTV-1 综合) + 退出全屏按钮
      // (Icons.fullscreen_exit) 仍 findable.
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      // 验证 AnimatedOpacity 的 opacity = 0.0 (只剩控件层)
      final opacities =
          tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacities, isNotEmpty);
      expect(
        opacities.first.opacity,
        0.0,
        reason: '3s 后控件层 (节目卡 + 频道横滑) opacity=0',
      );

      // 关键 (v0.3.5.5 P0 fix): _TopBar 不在 AnimatedOpacity 内, 永远 visible.
      // 频道名仍在:
      expect(
        find.text('CCTV-1 综合'),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — _TopBar 永远 visible, 3s 后频道名仍在',
      );
      // 退出全屏按钮仍在 (v0.3.5.5 P0 fix: 合并进 _TopBar):
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — 退出全屏按钮在 _TopBar 内, 永远 findable, '
            '用户随时可点退出全屏',
      );
    });

    testWidgets('全屏: 退出全屏按钮 (fullscreen_exit) 在 _TopBar 内 (v0.3.5.5 移入)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // 默认: 无退出全屏按钮 (因为还没全屏)
      expect(
        find.byIcon(Icons.fullscreen_exit),
        findsNothing,
        reason: '未全屏时不应该有退出全屏按钮',
      );

      // 点全屏
      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 全屏时: 退出全屏按钮存在
      expect(
        find.byIcon(Icons.fullscreen_exit),
        findsOneWidget,
        reason: '全屏时应该有退出全屏按钮 (top right)',
      );

      // 点退出全屏
      await tester.tap(find.byIcon(Icons.fullscreen_exit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 退出后: 按钮消失
      expect(
        find.byIcon(Icons.fullscreen_exit),
        findsNothing,
        reason: '退出全屏后按钮消失',
      );
    });

    testWidgets(
        'TV 端 (短边 >= 600): 默认走全屏覆盖, _TopBar 永远 visible (v0.3.5.5 P0 fix)',
        (tester) async {
      // TV 端: logical 1920x1080 (短边 1080 >= 600)
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // TV 端: _buildFullscreenOverlay 直接走 (因为 !_isMobile).  _TopBar
      // 应该立即渲染.
      expect(
        find.text('CCTV-1 综合'),
        findsOneWidget,
        reason: 'TV 端默认全屏覆盖, _TopBar 显示频道名',
      );
      // 6/18 fix: TV 端也走全屏覆盖, 同样无 SafeArea.
      expect(
        find.byType(SafeArea),
        findsNothing,
        reason: 'TV 端默认全屏覆盖, 无 SafeArea (跟移动端全屏一致)',
      );

      // TV 端: 没有"进入全屏"按钮 (因为已经全屏了).
      expect(
        find.byIcon(Icons.fullscreen),
        findsNothing,
        reason: 'TV 端没有"进入全屏"按钮 (默认就是全屏覆盖)',
      );
      // v0.3.5.5 P0 fix: 退出全屏按钮现在在 _TopBar 内 — TV 端 _isFullscreen=false
      // 也在 (onExitFullscreen 永远传给 _TopBar).  因为 TV 端也走
      // _buildFullscreenOverlay, onExitFullscreen 不为 null, 按钮渲染.
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — 退出全屏按钮在 _TopBar 内, TV 端也显示',
      );

      // v0.3.5.5 P0 fix: 3s 后 _TopBar **不**隐身 (永远 visible).  只有
      // 控件层 (节目卡 + 频道横滑) opacity=0.
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      final opacities =
          tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(
        opacities.first.opacity,
        0.0,
        reason: 'TV 端 控件层 (节目卡 + 频道横滑) 3s 后 opacity=0',
      );

      // 关键 (v0.3.5.5 P0 fix): _TopBar 永远 visible, 3s 后频道名 + 退出
      // 全屏按钮仍在.
      expect(
        find.text('CCTV-1 综合'),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — _TopBar 永远 visible, 3s 后频道名仍在',
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.fullscreen_exit),
        findsOneWidget,
        reason: 'v0.3.5.5 P0 fix — _TopBar 永远 visible, 退出全屏按钮仍在',
      );
    });
  });
}

// ───────────── Test helpers ─────────────

Future<void> _pumpPlayerPage(
  WidgetTester tester, {
  required _ScriptedOpener opener,
  required List<Channel> channels,
  required String channelId,
}) async {
  final router = GoRouter(
    initialLocation: '/player/$channelId',
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
        ps.streamOpenerProvider.overrideWithValue(opener),
        channelRepositoryProvider.overrideWith(
          (ref) => _FakeChannelRepository(channels),
        ),
        ps.mediaKitVideoControllerProvider
            .overrideWithValue(_FakeVideoController()),
        ps.mediaKitPlayerProvider.overrideWithValue(_FakePlayer()),
        startupServiceProvider.overrideWithValue(StartupService()),
        favoritesServiceProvider.overrideWithValue(
          FavoritesService(store: InMemoryFavoritesStore()),
        ),
        // 6/18 fix: 覆盖 player state 为 loading, 避免 _ErrorOverlay 在
        // 小手机 16:9 区域溢出 (error overlay 套 Column, 需要 ~250px 高,
        // 手机 16:9 区域只有 ~200px 会触发 RenderFlex overflow 报黄黑条).
        ps.currentPlayerStateProvider.overrideWithValue(
          const ps.PlayerState(
            status: ps.PlayerStatus.loading,
            attempt: SourceAttemptEvent(index: 1, total: 2, url: 'http://1'),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

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
    sources: ['http://1'],
  ),
];

class _ScriptedResult {
  const _ScriptedResult.failure() : _success = false;

  final bool _success;
}

class _ScriptedOpener implements StreamOpener {
  _ScriptedOpener(this._scripted);
  final List<_ScriptedResult> _scripted;
  int _idx = 0;
  final List<String> calls = [];

  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    calls.add(url);
    final i = _idx++;
    if (i >= _scripted.length) return false;
    return _scripted[i]._success;
  }
}

class _FakeVideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePlayer implements mk.Player {
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeChannelRepository implements ChannelRepository {
  _FakeChannelRepository(this._channels);
  final List<Channel> _channels;

  @override
  Future<List<Channel>> loadBundled() async => _channels;
}
