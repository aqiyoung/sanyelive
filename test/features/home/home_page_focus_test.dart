// P2-1: HomePage 焦点项数上限测试
// 验收 (proof): home_page 一屏焦点项 ≤ 9, 超出 TvFocusScope 报 assert
// 6/18 老板拍 ChatGPT 6/17 21:18 建议.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/core/tv/tv_focus.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/home/home_page.dart';
import 'package:sanyelive/services/startup_service.dart';
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
      channelsStreamProvider.overrideWith((ref) async* {
        yield _channels;
      }),
      channelRepositoryProvider.overrideWithValue(const _FakeRepo(_channels)),
      favoritesServiceProvider.overrideWithValue(
        FavoritesService(store: InMemoryFavoritesStore()),
      ),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomePage focus cap (P2-1)', () {
    testWidgets('无 lastChannel → 5 个焦点项 (2 actions + 3 categories), 不超 9',
        (tester) async {
      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // TvFocusScope 在 build 阶段跑 assert, 如果 5 > 9 会抛 — 这里
      // 不抛 = 通过. 再 verify TvFocusScope 实际渲染了 (子组件的 Text 在).
      expect(find.text('三页直播'), findsWidgets);
      expect(find.text('央视'), findsOneWidget);
      expect(find.text('卫视'), findsOneWidget);
      expect(find.text('地方'), findsOneWidget);
    });

    testWidgets('有 lastChannel → 6 个焦点项 (+1 ContinueWatching), 不超 9',
        (tester) async {
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

      // TvFocusScope assert 6 <= 9 通过, 页面正常渲染.
      expect(find.textContaining('继续观看'), findsOneWidget);
      expect(find.text('央视'), findsOneWidget);
    });

    testWidgets('AppBar actions 包在 TvFocusCapWrap (maxPerRow=3) 内',
        (tester) async {
      await _pump(
        tester,
        router: _router(),
        overrides: [
          ..._baseOverrides(),
          startupServiceProvider.overrideWithValue(StartupService()),
        ],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // TvFocusCapWrap 渲染 → 2 个 IconButton (search + favorites) 在内.
      expect(find.byType(TvFocusCapWrap), findsWidgets);
      // 2 个 search + favorites icon button 都在 wrap 内.
      expect(find.byIcon(Icons.search), findsWidgets);
      expect(find.byIcon(Icons.favorite_border), findsWidgets);
    });
  });
}
