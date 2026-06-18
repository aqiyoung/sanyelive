// v0.3.6.1 hotfix: 暗色主题 widget 适配 — home_page dark theme test
//
// 验证 HomePage 顶 bar 3 个 IconButton (search/favorite/settings) 都用 onSurface.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/core/theme/colors.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/home/home_page.dart';
import 'package:sanyelive/services/startup_service.dart';

class _FakeRepo implements ChannelRepository {
  const _FakeRepo(this._channels);
  final List<Channel> _channels;
  @override
  Future<List<Channel>> loadBundled() async => _channels;
}

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

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomePage()),
        GoRoute(
          path: '/search',
          builder: (_, __) => const Scaffold(body: Text('SEARCH')),
        ),
        GoRoute(
          path: '/favorites',
          builder: (_, __) => const Scaffold(body: Text('FAVORITES')),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('SETTINGS')),
        ),
      ],
    );

Future<void> _pumpDark(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        channelsProvider.overrideWith((ref) async => _channels),
        channelRepositoryProvider.overrideWithValue(const _FakeRepo(_channels)),
        favoritesServiceProvider.overrideWithValue(
          FavoritesService(store: InMemoryFavoritesStore()),
        ),
        startupServiceProvider.overrideWithValue(StartupService()),
      ],
      child: MaterialApp.router(
        theme: IptvTheme.dark(),
        routerConfig: _router(),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomePage dark theme (v0.3.6.1 hotfix)', () {
    testWidgets('3 个 AppBar IconButton.color = onSurface (darkTextPrimary)',
        (tester) async {
      await _pumpDark(tester);

      for (final icon in [
        Icons.search,
        Icons.favorite_border,
        Icons.settings_outlined,
      ]) {
        final btn = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, icon),
        );
        expect(btn.color, isNotNull,
            reason: '$icon button color should be set');
        expect(btn.color, isNot(equals(IptvColors.textPrimary)),
            reason: '$icon still uses light token IptvColors.textPrimary');
        // dark theme 下应该用 darkTextPrimary (colorScheme.onSurface)
        expect(btn.color, equals(IptvColors.darkTextPrimary),
            reason: '$icon should use darkTextPrimary in dark theme');
      }
    });

    testWidgets('在 dark theme 下能正常渲染 (smoke test)', (tester) async {
      await _pumpDark(tester);
      expect(find.text('三页直播'), findsWidgets);
      expect(find.text('央视'), findsOneWidget);
      expect(find.text('卫视'), findsOneWidget);
      expect(find.text('地方'), findsOneWidget);
    });
  });
}
