// P2-3-A (6/18 老板拍): TvFocus 集成 5 page widget test
// 覆盖: favorites + search + category (Phase 1, 3 page).
//
// Phase 2/3 (player + home) 已有 home_page_focus_test.dart 等,  本次
// 只补 Phase 1 三个 page 的 TvFocus 焦点集成验证.
//
// 验收 (proof):
//   1. favorites_page: back 按钮 + list tile 套 TvFocus
//   2. search_page: back 按钮套 TvFocus + TvFocusGroup 在 page root
//   3. category_page: back 按钮 + list tile 套 TvFocus
//   4. TvFocus.borderWidth 默认 2,  可覆盖 3-4 (widget 参数验证)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/core/tv/tv_focus.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/category/category_page.dart';
import 'package:sanyelive/features/favorites/favorites_page.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/search/search_page.dart';
import 'package:sanyelive/services/startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Channel(
    id: 'HunanTV.cn',
    name: '湖南卫视',
    country: 'CN',
    categories: ['general'],
    sources: ['http://3'],
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
        GoRoute(path: '/', builder: (_, __) => const _HomeStub()),
        GoRoute(path: '/favorites', builder: (_, __) => const FavoritesPage()),
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(
          path: '/category/cctv',
          builder: (_, __) => const CategoryPage(
            categoryId: 'cctv',
            title: '央视',
          ),
        ),
        GoRoute(
          path: '/player/:id',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('player stub')),
          ),
        ),
      ],
    );

class _HomeStub extends StatelessWidget {
  const _HomeStub();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('home')));
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required GoRouter router,
  required List<Override> overrides,
}) async {
  // P2-3-A: 测试用 TV 尺寸 viewport (>= 1025dp 走 TV 分支,
  //  才能看到 TvFocus 拿焦点环).  默认 800x600 是 tablet,  TvFocus
  //  在 isTv=false 时不渲染.
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      startupServiceProvider.overrideWithValue(StartupService()),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P2-3-A: TvFocus widget 扩展参数', () {
    test('TvFocus.borderWidth 默认 2, focusedScale 默认 1.05', () {
      const widget = TvFocus(child: SizedBox.shrink());
      expect(widget.borderWidth, 2);
      expect(widget.focusedScale, 1.05);
      expect(widget.borderRadius, 12);
    });

    test('TvFocus.borderWidth 可覆盖到 3, focusedScale 1.08', () {
      const widget = TvFocus(
        borderWidth: 3,
        focusedScale: 1.08,
        child: SizedBox.shrink(),
      );
      expect(widget.borderWidth, 3);
      expect(widget.focusedScale, 1.08);
    });

    testWidgets('TvFocus 渲染不抛异常 (borderWidth=3 + focusedScale=1.08)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TvFocus(
              borderWidth: 3,
              focusedScale: 1.08,
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      expect(find.byType(TvFocus), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('P2-3-A Phase 1: 3 page TvFocus 集成', () {
    testWidgets('favorites_page: back 按钮 + 列表 tile 套 TvFocus', (tester) async {
      final router = _router();
      await _pumpApp(
        tester,
        router: router,
        overrides: _baseOverrides(),
      );
      router.push('/favorites');
      await tester.pumpAndSettle();

      // 1 back + 3 list = 4 个 TvFocus (CCTV1, CCTV2, HunanTV 都进 fav)
      // 但 InMemoryFavoritesStore 默认空, 所以 favorites page 是空态
      // 改: 收藏空时只显示 back 按钮 1 个 TvFocus,  list 没有
      // 这里只断言非空 + TvFocusGroup 存在
      expect(find.byType(TvFocus), findsAtLeast(1));
      expect(find.byType(TvFocusGroup), findsAtLeast(1));
      // 空态: 收藏为 0 时显示 "暂无收藏" 和 "还没有收藏"
      expect(find.text('暂无收藏'), findsOneWidget);
      expect(find.text('还没有收藏'), findsOneWidget);
    });

    testWidgets('favorites_page: 有收藏时 list 多个 TvFocus', (tester) async {
      final router = _router();
      // 预填 3 个收藏
      final store = InMemoryFavoritesStore();
      await store.add('CCTV1.cn', 'CCTV-1 综合');
      await store.add('CCTV2.cn', 'CCTV-2 财经');
      await store.add('HunanTV.cn', '湖南卫视');

      await _pumpApp(
        tester,
        router: router,
        overrides: [
          ..._baseOverrides(),
          favoritesServiceProvider.overrideWithValue(
            FavoritesService(store: store),
          ),
        ],
      );
      router.push('/favorites');
      await tester.pumpAndSettle();

      // 1 back + 3 list = 4 TvFocus
      expect(find.byType(TvFocus), findsNWidgets(4));
      expect(find.byType(TvFocusGroup), findsAtLeast(1));
      expect(find.text('共 3 个频道'), findsOneWidget);
    });

    testWidgets('search_page: TvFocusGroup + TvFocus 渲染 (初始无 query)',
        (tester) async {
      final router = _router();
      await _pumpApp(
        tester,
        router: router,
        overrides: _baseOverrides(),
      );
      router.push('/search');
      await tester.pumpAndSettle();

      // TvFocusGroup 1 个 (page root)
      expect(find.byType(TvFocusGroup), findsOneWidget);
      // back 按钮套 TvFocus 1 个
      expect(find.byType(TvFocus), findsAtLeast(1));
      // 初始空态: "输入关键词搜索频道"
      expect(find.text('输入关键词搜索频道'), findsOneWidget);
    });

    testWidgets('search_page: 输入 query 后 result tile 套 TvFocus',
        (tester) async {
      final router = _router();
      await _pumpApp(
        tester,
        router: router,
        overrides: _baseOverrides(),
      );
      router.push('/search');
      await tester.pumpAndSettle();

      // 输入 "CCTV" → 模糊匹配 CCTV1 + CCTV2
      await tester.enterText(find.byType(TextField), 'CCTV');
      await tester.pump(const Duration(milliseconds: 400)); // debounce 300ms
      await tester.pumpAndSettle();

      // 1 back + 1 clear (query 非空) + 2 result tile = 4 TvFocus
      expect(find.byType(TvFocus), findsNWidgets(4));
    });

    testWidgets('category_page (cctv): back + 列表 tile 套 TvFocus',
        (tester) async {
      final router = _router();
      await _pumpApp(
        tester,
        router: router,
        overrides: _baseOverrides(),
      );
      router.push('/category/cctv');
      await tester.pumpAndSettle();

      // CCTV filter: CCTV1 + CCTV2 = 2 list item
      // 1 back + 2 list = 3 TvFocus
      expect(find.byType(TvFocus), findsNWidgets(3));
      expect(find.byType(TvFocusGroup), findsAtLeast(1));
      expect(find.text('央视'), findsOneWidget);
      expect(find.text('共 2 个频道'), findsOneWidget);
    });
  });
}
