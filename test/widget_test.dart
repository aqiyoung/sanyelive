// Card 4 回归测试 — App boot + 主页基本元素
// (旧测试引用了卡 2 的 IptvDemoPage, 已被路由 + HomePage 取代)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanyelive/core/responsive/breakpoints.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/data/repositories/channel_repository.dart';
import 'package:sanyelive/features/favorites/favorites_service.dart';
import 'package:sanyelive/features/settings/theme_provider.dart';
import 'package:sanyelive/main.dart';
import 'package:sanyelive/services/startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('IptvApp boots and home page renders (offline)', (tester) async {
    // 卡 5: 用 [bootstrap] 跳过 media_kit native init, 并 override 频道源
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 空频道列表, 避免 assets 加载
          channelsProvider.overrideWith(
            (ref) async => <Channel>[],
          ),
          // 卡 6: HomePage 需要 StartupService + FavoritesService
          startupServiceProvider.overrideWithValue(StartupService()),
          favoritesServiceProvider.overrideWithValue(
            FavoritesService(store: InMemoryFavoritesStore()),
          ),
          // 0.3.6+19: IptvApp 是 ConsumerWidget 监听 themeModeProvider,
          //  themeModeProvider 内部读 sharedPreferencesProvider.
          //  setUp 已 setMockInitialValues({}),  getInstance 返回 mock.
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const IptvApp(),
      ),
    );
    // First frame: app shell renders, channels loading
    await tester.pump();
    expect(find.text('三页直播'), findsWidgets);
  });

  testWidgets('DeviceTier.thresholds', (tester) async {
    expect(Breakpoints.phone, 600);
    expect(Breakpoints.tablet, 1024);
    expect(Breakpoints.tv, 1024);

    Future<DeviceTier> tierForWidth(double w) async {
      late DeviceTier tier;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(w, 800)),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                tier = context.deviceTier;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return tier;
    }

    expect(await tierForWidth(360), DeviceTier.phone);
    expect(await tierForWidth(600), DeviceTier.phone);
    expect(await tierForWidth(720), DeviceTier.tablet);
    expect(await tierForWidth(1024), DeviceTier.tablet);
    expect(await tierForWidth(1280), DeviceTier.tv);
    expect(await tierForWidth(1920), DeviceTier.tv);
  });
}
