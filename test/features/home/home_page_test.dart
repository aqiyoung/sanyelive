// �?6 单元测试: HomePage 集成 �?上次观看 / 搜索入口 / 频道分类
// 验收 (proof): 收藏 5 个频�? 重启 APP 仍在; 搜索 "CCTV" 1s 内出结果
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:threelive/core/theme/theme.dart';
import 'package:threelive/data/models/channel.dart';
import 'package:threelive/data/repositories/channel_repository.dart';
import 'package:threelive/features/favorites/favorites_service.dart';
import 'package:threelive/features/home/home_page.dart';
import 'package:threelive/services/startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channels = <Channel>[
  Channel(
    id: 'CCTV1.cn',
    name: 'CCTV-1',
    country: 'CN',
    categories: ['general'],
    sources: ['http://1'],
  ),
  Channel(
    id: 'CCTV2.cn',
    name: 'CCTV-2',
    country: 'CN',
    categories: ['general'],
    sources: ['http://2'],
  ),
  Channel(
    id: 'HunanSatelliteTV.cn',
    name: 'Hunan TV',
    country: 'CN',
    categories: ['general'],
    sources: ['http://hn'],
  ),
];

class _FakeRepo implements ChannelRepository {
  const _FakeRepo(this._channels);
  final List<Channel> _channels;
  @override
  Future<List<Channel>> loadBundled() async => _channels;
}

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomePage(),
        ),
        GoRoute(
          path: '/search',
          builder: (_, __) => const Scaffold(body: Text('SEARCH_PAGE')),
        ),
        GoRoute(
          path: '/player/:channelId',
          builder: (_, state) => Scaffold(
            body: Text('PLAYER: ${state.pathParameters['channelId']}'),
          ),
        ),
        GoRoute(
          path: '/category/:catId',
          builder: (_, state) => Scaffold(
            body: Text('CATEGORY: ${state.pathParameters['catId']}'),
          ),
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required GoRouter router,
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: IptvTheme.light(),
        routerConfig: router,
      ),
    ),
  );
}

List<Override> _baseOverrides() => [
      channelsProvider.overrideWith((ref) async => _channels),
      channelRepositoryProvider.overrideWithValue(const _FakeRepo(_channels)),
      favoritesServiceProvider.overrideWithValue(
        FavoritesService(store: InMemoryFavoritesStore()),
      ),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomePage', () {
    testWidgets('渲染: 3 大分�?+ 标题 + 搜索入口', (tester) async {
      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('三页直播'), findsOneWidget);
      expect(find.text('央视'), findsOneWidget);
      expect(find.text('卫视'), findsOneWidget);
      expect(find.text('地方'), findsOneWidget);
      // 搜索入口: IconButton with Icons.search
      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('�?lastChannelId �?不显示「继续观看」卡�?, (tester) async {
      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.textContaining('继续观看'), findsNothing);
    });

    testWidgets('�?lastChannelId �?显示「继续观看」卡�?+ 清除按钮', (tester) async {
      // 预先�?SharedPreferences 写入 last channel
      SharedPreferences.setMockInitialValues({
        'last_channel_id': 'CCTV1.cn',
      });

      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // "继续观看" 标签 + 频道名都�?(文本格式: "继续观看  ·  CCTV-1")
      expect(find.textContaining('继续观看'), findsOneWidget);
      expect(find.textContaining('CCTV-1'), findsWidgets);
      // 关闭按钮 (清除上次观看)
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('点击清除按钮 �?移除「继续观看」卡�?, (tester) async {
      SharedPreferences.setMockInitialValues({
        'last_channel_id': 'CCTV1.cn',
      });

      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.textContaining('继续观看'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.textContaining('继续观看'), findsNothing);
      // SharedPreferences 已被清空
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_channel_id'), isNull);
    });

    testWidgets('点击搜索按钮 �?跳转�?/search', (tester) async {
      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // 找到 _AppHeader 里的 search IconButton
      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pumpAndSettle();

      expect(find.text('SEARCH_PAGE'), findsOneWidget);
    });

    testWidgets('点击「央视」卡�?�?跳到分类�?, (tester) async {
      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      await tester.tap(find.text('央视'));
      await tester.pumpAndSettle();

      expect(find.text('CATEGORY: cctv'), findsOneWidget);
    });
  });
}
