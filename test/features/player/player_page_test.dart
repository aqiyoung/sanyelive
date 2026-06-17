// 卡 5: PlayerPage widget test
// 验证: 页面渲染 + 切台时调用 SourceFailover

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/player/player_page.dart';
import 'package:sanyelive/services/player_service.dart';
import 'package:sanyelive/services/source_failover.dart';
import 'package:sanyelive/services/startup_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlayerPage widget', () {
    testWidgets('渲染播放页: 频道名 + 下一频道 + 状态栏', (tester) async {
      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      // 多次 pump 让 FutureBuilder + autoPlay 都完成
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // 频道名 (在 _TopBar)
      expect(find.text('CCTV-1 综合'), findsOneWidget);
      // 下一频道 section
      expect(find.text('下一频道'), findsOneWidget);
    });

    testWidgets('空 sources 频道 → 页面不调 opener', (tester) async {
      final opener = _ScriptedOpener([]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'NoSource.cn',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('NoSource Channel'), findsOneWidget);
      expect(opener.calls, isEmpty);
    });

    testWidgets('切台: 下一频道横滑条渲染 CCTV-2 chip', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final opener = _ScriptedOpener([
        _ScriptedResult.failure(),
        _ScriptedResult.failure(),
      ]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // 下一频道 chip 中能看到 CCTV-2
      expect(find.text('CCTV-2 财经'), findsOneWidget);
    });
  });
// P0-1 (6/17): 播放页 UI 3s 隐身
  group('PlayerPage P0-1 控件隐身', () {
    // 安全获取第一个 AnimatedOpacity 的 opacity
    double _firstOpacity(WidgetTester tester) {
      final widgets =
          tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      return widgets.first.opacity;
    }

    testWidgets('初始控件可见, 3s 后变隐藏 (timer 触发)', (tester) async {
      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.pump();

      // 初始: 频道名可见
      expect(find.text('CCTV-1 综合'), findsOneWidget);

      // 6/17 fix: pump(Duration) 推进 fake clock 过 3s hideAfter timer.
      // runAsync 走真实时, fake clock 没动, Timer 不会触发.
      await tester.pump(const Duration(milliseconds: 4000));
      // 多 pump 几轮确保 setState + 动画完成
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      // 控件应该已隐藏 (opacity=0)
      expect(_firstOpacity(tester), 0.0, reason: '3s 后控件应该隐藏');
    });

    testWidgets('点击视频区: 隐藏中点一下 -> 显示 + 重置 timer', (tester) async {
      final opener = _ScriptedOpener([_ScriptedResult.failure()]);
      await _pumpPlayerPage(
        tester,
        opener: opener,
        channels: _channels,
        channelId: 'CCTV1.cn',
      );
      await tester.pump();
      await tester.pump();

      // 初始: 控件可见
      expect(_firstOpacity(tester), 1.0);

      // 6/17 fix: pump(Duration) 推进 fake clock 过 3s hideAfter timer.
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_firstOpacity(tester), 0.0, reason: '等待后控件应该隐藏');

      // 点视频区
      final videoArea = find.byType(GestureDetector);
      await tester.tap(videoArea.first);
      await tester.pump();

      // 控件应该重新可见
      expect(_firstOpacity(tester), 1.0, reason: '点击后控件应该重新可见');
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
        streamOpenerProvider.overrideWithValue(opener),
        // 覆盖 ChannelRepository 避免 assets 加载 (test env 不可用)
        channelRepositoryProvider.overrideWith(
          (ref) => _FakeChannelRepository(channels),
        ),
        // 卡 5: 测试环境无 libmpv, 覆盖 video controller 为空 fake
        mediaKitVideoControllerProvider
            .overrideWithValue(_FakeVideoController()),
        // 6/17 修声音残留: PlayerService 现在拿 Player 实例, 测试环境不构造
        // 真 native player,  注入 noSuchMethod fake.  play() 调 stop() 会
        // 走到 noSuchMethod 返回 null,  不报错.
        mediaKitPlayerProvider.overrideWithValue(_FakePlayer()),
        // 卡 6: PlayerPage 调 StartupService + FavoritesService
        startupServiceProvider.overrideWithValue(StartupService()),
        favoritesServiceProvider.overrideWithValue(
          FavoritesService(store: InMemoryFavoritesStore()),
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
  Channel(
    id: 'NoSource.cn',
    name: 'NoSource Channel',
    country: 'CN',
    categories: ['general'],
    sources: <String>[],
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

/// VideoController fake — 测试环境不能 instantiate 真 Player
/// 实际渲染中只要 state != playing 就不会用到 controller
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

/// ChannelRepository fake — 返回预置的频道列表, 避免 assets 加载
class _FakeChannelRepository implements ChannelRepository {
  _FakeChannelRepository(this._channels);
  final List<Channel> _channels;

  @override
  Future<List<Channel>> loadBundled() async => _channels;
}
