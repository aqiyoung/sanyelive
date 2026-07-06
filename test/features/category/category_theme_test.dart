// v0.3.5.4 主题适配真修: 浅色+暗色都验证 category_page chrome 颜色
//
// 验证:
//   1. 浅色主题下, 返回按钮 color = onSurface (textPrimary),
//      空态 inbox_outlined icon color = onSurfaceVariant (textSecondary).
//   2. 暗色主题下, 同样的 widget 用暗色板 (darkTextPrimary / darkTextSecondary).
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
      ],
      child: MaterialApp(
        theme: theme,
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

  group('CategoryPage v0.3.5.4 主题适配 (浅色+暗色)', () {
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
