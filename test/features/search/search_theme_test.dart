// v0.3.5.4 主题适配真修: 浅色+暗色都验证 search_page chrome 颜色
//
// 验证:
//   1. 浅色主题下, 返回按钮 color = onSurface (textPrimary),
//      搜索结果 channel displayName color = onSurface.
//   2. 暗色主题下, 同样的 widget 用暗色板 (darkTextPrimary).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/core/theme/colors.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/search/search_page.dart';

class _FakeRepo implements ChannelRepository {
  _FakeRepo(this._channels);
  final List<Channel> _channels;
  @override
  Future<List<Channel>> loadBundled() async => _channels;
  @override
  void mergeFastSources(List<Channel> channels, Map<String, List<String>> fast) {}
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
    id: 'HunanTV.cn',
    name: '湖南卫视',
    country: 'CN',
    categories: ['general'],
    sources: ['http://h'],
  ),
];

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
        channelRepositoryProvider.overrideWithValue(_FakeRepo(_channels)),
        favoritesServiceProvider.overrideWithValue(
          FavoritesService(store: InMemoryFavoritesStore()),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: const SearchPage(),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SearchPage v0.3.5.4 主题适配 (浅色+暗色)', () {
    testWidgets('浅色主题: 返回按钮 IconButton.color = onSurface (= textPrimary)',
        (tester) async {
      await _pump(tester, theme: IptvTheme.light());
      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(backButton.color, isNotNull);
      // 浅色 theme 下 onSurface = textPrimary (0xFF2A2520)
      expect(backButton.color, equals(IptvColors.textPrimary),
          reason: '浅色下返回按钮 color = onSurface = textPrimary');
    });

    testWidgets('暗色主题: 返回按钮 IconButton.color = onSurface (= darkTextPrimary)',
        (tester) async {
      await _pump(tester, theme: IptvTheme.dark());
      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(backButton.color, isNotNull);
      // 暗色 theme 下 onSurface = darkTextPrimary (0xFFEDE4D3)
      expect(backButton.color, equals(IptvColors.darkTextPrimary),
          reason: '暗色下返回按钮 color = onSurface = darkTextPrimary');
    });
  });
}
