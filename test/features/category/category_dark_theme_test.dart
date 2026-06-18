// v0.3.6.1 hotfix: 暗色主题 widget 适配 — category_page dark theme test
//
// 验证:
//   - L145 (IconButton color textPrimary) → onSurface
//   - L222 (空态 Icon color textSecondary) → onSurfaceVariant
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/core/theme/colors.dart';
import 'package:sanyelive/core/theme/theme.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/category/category_page.dart';

class _FakeRepo implements ChannelRepository {
  const _FakeRepo(this._channels);
  final List<Channel> _channels;
  @override
  Future<List<Channel>> loadBundled() async => _channels;
}

// 故意返回空, 触发 _EmptyState
const _channels = <Channel>[];

Future<void> _pumpDark(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        channelsProvider.overrideWith((ref) async => _channels),
        channelRepositoryProvider.overrideWithValue(const _FakeRepo(_channels)),
      ],
      child: MaterialApp(
        theme: IptvTheme.dark(),
        home: const CategoryPage(categoryId: 'cctv', title: '央视'),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CategoryPage dark theme (v0.3.6.1 hotfix)', () {
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

    testWidgets('空态 inbox_outlined icon 颜色 != textSecondary', (tester) async {
      await _pumpDark(tester);
      // 空 channels → _EmptyState → inbox_outlined icon
      final iconFinder = find.byIcon(Icons.inbox_outlined);
      expect(iconFinder, findsOneWidget);
      // 从 IconTheme.of 读 resolved color (M3 IconButton 用 IconTheme 传色)
      final ctx = tester.element(iconFinder);
      final resolvedColor = IconTheme.of(ctx).color;
      expect(resolvedColor, isNotNull);
      // 不应该是浅色 textSecondary
      expect(resolvedColor, isNot(equals(IptvColors.textSecondary)),
          reason: '空态 icon 不该用浅色 token IptvColors.textSecondary');
    });

    testWidgets('在 dark theme 下能正常渲染 (smoke test)', (tester) async {
      await _pumpDark(tester);
      // _BackBar 显示 title='央视', count='共 0 个频道'
      expect(find.text('央视'), findsOneWidget);
      expect(find.text('共 0 个频道'), findsOneWidget);
      // _EmptyState 显示
      expect(find.text('该分类暂无频道'), findsOneWidget);
    });
  });
}
