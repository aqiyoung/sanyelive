import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/category/category_page.dart';
import '../../features/home/home_page.dart';
import '../../features/player/player_page.dart';
import '../../features/search/search_page.dart';

/// 路由路径常量 — 集中管理
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String category = '/category/:catId';
  static const String player = '/player/:channelId';
  static const String search = '/search';

  static String categoryPath(String catId, {String? title, int? count}) {
    final query = <String, String>{};
    if (title != null) query['title'] = title;
    // count 通过 extra 传, 不放 query
    final uri = Uri(
      path: '/category/$catId',
      queryParameters: query.isEmpty ? null : query,
    );
    return uri.toString();
  }

  static String playerPath(String channelId) => '/player/$channelId';
}

/// 应用路由 — go_router 14 配置
/// 主页 → 分类 (path param catId + query title) → 播放 (path param channelId)
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomePage(),
        routes: [
          // 分类页: /category/cctv?title=央视
          GoRoute(
            path: 'category/:catId',
            name: 'category',
            builder: (context, state) {
              final catId = state.pathParameters['catId']!;
              final title = state.uri.queryParameters['title'];
              return CategoryPage(categoryId: catId, title: title);
            },
          ),
          // 播放页: /player/CCTV1.cn
          GoRoute(
            path: 'player/:channelId',
            name: 'player',
            builder: (context, state) {
              final channelId = state.pathParameters['channelId']!;
              return PlayerPage(channelId: channelId);
            },
          ),
          // 搜索页: /search
          GoRoute(
            path: 'search',
            name: 'search',
            builder: (context, state) => const SearchPage(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouterErrorPage(error: state.error),
  );
}

class _RouterErrorPage extends StatelessWidget {
  const _RouterErrorPage({this.error});
  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面未找到')),
      body: Center(
        child: Text(error?.toString() ?? '未知路由'),
      ),
    );
  }
}
