// v0.3.6.1 hotfix: 暗色主题 widget 适配 — favorites_page dark theme test
//
// 验证:
//   1. dark theme 下, FavoritesPage Scaffold 不再 hardcode bgParchment
//      (让 theme.surface 生效)
//   2. 返回按钮 IconButton.color 用 colorScheme.onSurface (= darkTextPrimary)
//   3. 空态 favorite_border IconButton.color 用 colorScheme.onSurfaceVariant
//      (不是 textSecondary 浅色 token)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/core/theme/colors.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_page.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
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
];

Future<void> _pumpDark(WidgetTester tester) async {
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
      child: MaterialApp(
        theme: IptvTheme.dark(),
        home: const FavoritesPage(),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoritesPage dark theme (v0.3.6.1 hotfix)', () {
    testWidgets('Scaffold 不再 hardcode bgParchment (依赖 theme surface)',
        (tester) async {
      await _pumpDark(tester);
      // Scaffold 显式 backgroundColor == null (让 theme.surface 生效)
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNull,
          reason: 'Scaffold 硬编码 backgroundColor 会盖掉 theme');
    });

    testWidgets('返回按钮 IconButton.color = onSurface (darkTextPrimary)',
        (tester) async {
      await _pumpDark(tester);
      // _FavoritesAppBar 里的返回 IconButton
      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(backButton.color, isNotNull,
          reason: '返回按钮的 IconButton.color 应该是显式设置的');
      expect(backButton.color, isNot(equals(IptvColors.textPrimary)),
          reason: '返回按钮不该用浅色 token IptvColors.textPrimary');
      // dark theme 下应该用 darkTextPrimary (colorScheme.onSurface)
      expect(backButton.color, equals(IptvColors.darkTextPrimary));
    });

    testWidgets('空态 favorite_border icon 颜色 != textSecondary 浅色 token',
        (tester) async {
      // 空收藏列表 → _EmptyState → favorite_border icon
      await _pumpDark(tester);
      // ChannelTile 不渲染 (空 favIds), _EmptyState 显示 1 个 favorite_border icon
      final iconFinder = find.byIcon(Icons.favorite_border);
      expect(iconFinder, findsOneWidget);
      // 从 IconTheme.of 读 resolved color (M3 IconButton/Icon 用 IconTheme 传色)
      final ctx = tester.element(iconFinder);
      final resolvedColor = IconTheme.of(ctx).color;
      expect(resolvedColor, isNotNull);
      // 不应该是浅色 textSecondary
      expect(resolvedColor, isNot(equals(IptvColors.textSecondary)),
          reason: '空态图标不该用浅色 token IptvColors.textSecondary');
    });
  });
}
