// v0.3.5.4 主题适配真修: 浅色+暗色都验证 home_page chrome 颜色
//
// 验证:
//   1. 浅色主题下, AppBar 3 个 IconButton (search/favorite/settings) 颜色
//      都用 onSurface (= textPrimary / 2A2520).
//   2. 暗色主题下, 同样的 widget 用暗色板 (darkTextPrimary / 米色).
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

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        channelsProvider.overrideWith((ref) async => _channels),
        channelsStreamProvider.overrideWith((ref) async* {
          yield _channels;
        }),
        channelRepositoryProvider.overrideWithValue(const _FakeRepo(_channels)),
        favoritesServiceProvider.overrideWithValue(
          FavoritesService(store: InMemoryFavoritesStore()),
        ),
        startupServiceProvider.overrideWithValue(StartupService()),
      ],
      child: MaterialApp.router(
        theme: theme,
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

  group('HomePage v0.3.5.4 主题适配 (浅色+暗色)', () {
    testWidgets('浅色主题: AppBar 3 个 IconButton.color = onSurface (= textPrimary)',
        (tester) async {
      await _pump(tester, theme: IptvTheme.light());
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
        // 浅色下 onSurface = textPrimary (0xFF2A2520)
        expect(btn.color, equals(IptvColors.textPrimary),
            reason: '$icon 浅色下应该 = onSurface = textPrimary');
      }
    });

    testWidgets(
        '暗色主题: AppBar 3 个 IconButton.color = onSurface (= darkTextPrimary)',
        (tester) async {
      await _pump(tester, theme: IptvTheme.dark());
      for (final icon in [
        Icons.search,
        Icons.favorite_border,
        Icons.settings_outlined,
      ]) {
        final btn = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, icon),
        );
        expect(btn.color, isNotNull);
        // 暗色下 onSurface = darkTextPrimary (0xFFEDE4D3 米色)
        expect(btn.color, equals(IptvColors.darkTextPrimary),
            reason: '$icon 暗色下应该 = onSurface = darkTextPrimary');
        // 不能是浅色 token
        expect(btn.color, isNot(equals(IptvColors.textPrimary)),
            reason: '$icon 暗色下不能用浅色 token IptvColors.textPrimary');
      }
    });
  });
}
