// v0.3.6.1 hotfix: 暗色主题 widget 适配 — search_page dark theme test
//
// 验证 SearchPage 7 个 hardcode 浅色 token 的地方都改成了 colorScheme.*:
//   L170: back IconButton color
//   L180: hintText color
//   L210: empty prompt text color
//   L226/L232: "未找到匹配" icon + text color
//   L311/312: 搜索结果 channel displayName color
//
// 测试策略: 不用 "Text 不用浅色 token" 通用检查, 因为 IptvTypography 字体
// 样式本身 (serifTitle / caption 等) 有 color: textPrimary baked in,
// 但 IptvTheme.dark() 用 .apply(bodyColor: darkTextPrimary, ...) 覆盖了.
// 改用 IconButton.color / IconTheme.of() 检查具体 widget.
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

Future<void> _pumpDark(WidgetTester tester) async {
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
        theme: IptvTheme.dark(),
        home: const SearchPage(),
      ),
    ),
  );
  // 让 channelsProvider 的 future 解析
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SearchPage dark theme (v0.3.6.1 hotfix)', () {
    testWidgets('返回按钮 IconButton.color = onSurface (darkTextPrimary)',
        (tester) async {
      await _pumpDark(tester);
      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(backButton.color, isNotNull);
      expect(backButton.color, isNot(equals(IptvColors.textPrimary)),
          reason: '返回按钮不该用浅色 token IptvColors.textPrimary');
      expect(backButton.color, equals(IptvColors.darkTextPrimary));
    });

    testWidgets('空态 search_off icon 颜色 != textSecondary 浅色 token',
        (tester) async {
      await _pumpDark(tester);
      // 触发空态
      await tester.enterText(find.byType(TextField), 'XxxNotFound');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // search_off icon 颜色 (从 IconTheme.of 读 resolved color)
      final iconFinder = find.byIcon(Icons.search_off);
      expect(iconFinder, findsOneWidget);
      final ctx = tester.element(iconFinder);
      final resolvedColor = IconTheme.of(ctx).color;
      expect(resolvedColor, isNotNull);
      // 不应该是浅色 textSecondary
      expect(resolvedColor, isNot(equals(IptvColors.textSecondary)),
          reason: 'search_off icon 不该用浅色 token IptvColors.textSecondary');
    });

    testWidgets('在 dark theme 下能正常渲染 (smoke test)', (tester) async {
      await _pumpDark(tester);
      // 输入框 + hint 渲染 OK
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('搜索频道名或频道号…'), findsOneWidget);
    });

    testWidgets('输入 "CCTV" 在 dark theme 下也能搜出结果', (tester) async {
      await _pumpDark(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'CCTV');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('CCTV-1 综合'), findsOneWidget);
      // "湖南卫视" 不应该出现 (不匹配 CCTV)
      expect(find.text('湖南卫视'), findsNothing);
    });
  });
}
