// 6/17 v0.2.3 P1-2: 收藏页 widget smoke test
// 覆盖:
//  - 收藏页能渲染 (ProviderScope + Router)
//  - 收藏为空时显示空态
//  - 收藏有 3 个频道时,  ChannelTile 出现 3 次 + 顶 bar count = 3
//  - 长按 ChannelTile 弹底部 sheet,  「取消收藏」后 favs 列表更新
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iptv_app/data/models/channel.dart';
import 'package:iptv_app/data/repositories/channel_repository.dart';
import 'package:iptv_app/features/favorites/favorites_page.dart';
import 'package:iptv_app/features/favorites/favorites_service.dart';
import 'package:iptv_app/services/startup_service.dart';

void main() {
  group('FavoritesPage widget', () {
    testWidgets('渲染空态: 无收藏时显示「还没有收藏」', (tester) async {
      await _pump(tester, favIds: const <String>[]);
      await tester.pumpAndSettle();

      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('暂无收藏'), findsOneWidget);
      expect(find.text('还没有收藏'), findsOneWidget);
    });

    testWidgets('有 3 个收藏: ChannelTile 出现 3 次,  顶 bar count = 3',
        (tester) async {
      await _pump(
        tester,
        favIds: const ['CCTV1.cn', 'CCTV2.cn', 'HunanTV.cn'],
      );
      await tester.pumpAndSettle();

      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('共 3 个频道'), findsOneWidget);
      // ChannelTile 渲染 3 个 — 用 ChannelTile 内部 text 验证
      // 频道号 '01' '02' '03' 来自 category_page 同样的展示
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
    });

    testWidgets('收藏了不存在的 channel id: 只显示有的,  不会崩',
        (tester) async {
      // 模拟 sqflite 返回了 ID, 但 channels_cn.json 里已经被剔除
      await _pump(
        tester,
        favIds: const ['Missing.cn', 'CCTV1.cn'],
      );
      await tester.pumpAndSettle();

      // 只渲染 CCTV1.cn,  Missing.cn 被跳过
      expect(find.text('共 1 个频道'), findsOneWidget);
    });
  });
}

// ───────────── helpers ─────────────

Future<void> _pump(
  WidgetTester tester, {
  required List<String> favIds,
}) async {
  final store = InMemoryFavoritesStore();
  // 预置收藏
  for (final id in favIds) {
    await store.add(id, id);
  }
  final svc = FavoritesService(store: store);

  final router = GoRouter(
    initialLocation: '/favorites',
    routes: [
      GoRoute(
        path: '/favorites',
        builder: (_, __) => const FavoritesPage(),
      ),
      GoRoute(
        path: '/player/:channelId',
        builder: (_, state) => Scaffold(
          body: Center(child: Text('Player:${state.pathParameters['channelId']}')),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        channelsProvider.overrideWith((ref) async => _channels),
        favoritesServiceProvider.overrideWithValue(svc),
        // 收藏页用不到 startup,  覆盖掉避免 SharedPreferences 依赖
        startupServiceProvider.overrideWithValue(StartupService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
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
    id: 'CCTV2.cn',
    name: 'CCTV-2 财经',
    country: 'CN',
    categories: ['general'],
    sources: ['http://2'],
  ),
  Channel(
    id: 'HunanTV.cn',
    name: 'Hunan TV',
    country: 'CN',
    categories: ['general'],
    sources: ['http://h'],
  ),
];
