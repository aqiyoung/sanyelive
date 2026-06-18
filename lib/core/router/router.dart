import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/category/category_page.dart';
import '../../features/favorites/favorites_page.dart';
import '../../features/home/home_page.dart';
import '../../features/player/player_page.dart';
import '../../features/search/search_page.dart';
import '../../services/player_service.dart';

/// 路由路径常量 — 集中管理
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String category = '/category/:catId';
  static const String player = '/player/:channelId';
  static const String search = '/search';
  static const String favorites = '/favorites';

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
///
/// 6/18 P3-1: PlayerRouteObserver 监听路由 pop / replace,  离开 /player/* 时
/// 显式 stop + dispose PlayerService.  GoRouter 13+ 会在 navigatorObservers
/// 里 push 这个 observer,  否则 pop 路由时不会回调.  配合 main.dart 的
/// WidgetsBindingObserver (后台) + Android manifest stopWithTask=true
/// (任务杀), 三层保险释放 libmpv 资源.
GoRouter buildRouter({NavigatorObserver? playerObserver}) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    observers: playerObserver == null ? const [] : [playerObserver],
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
          // 6/17 v0.2.3 P1-2: 收藏页: /favorites
          GoRoute(
            path: 'favorites',
            name: 'favorites',
            builder: (context, state) => const FavoritesPage(),
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

/// 6/18 P3-1: NavigatorObserver for player route lifecycle.
///
/// 挂在 GoRouter observers 上后,  GoRouter 会回调这个类的
/// didPush/didPop/didReplace/didRemove.  离开 /player/* 路径时调
/// [PlayerService.stop] + [PlayerService.dispose],  释放 libmpv
/// 实例 + native audio track,  否则路由切走只是 UI 隐藏,  后台
/// 声音还在响.  配合 main.dart 的 WidgetsBindingObserver (后台) +
/// Android manifest android:stopWithTask=true (任务杀), 三层保险.
class PlayerRouteObserver extends NavigatorObserver {
  PlayerRouteObserver(this._playerService);

  final PlayerService _playerService;

  /// 路由名以 /player/ 开头则视为 player 路由,  要释放资源.
  /// AppRoutes.player = '/player/:channelId',  匹配 'player' 后面的部分
  /// 由 GoRoute 内部处理,  settings.name 是完整路径模板.
  bool _isPlayerRoute(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return false;
    // GoRoute name 是 'player' (见上面 routes 定义).
    return name == 'player';
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isPlayerRoute(route)) {
      _releasePlayer();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (_isPlayerRoute(oldRoute)) {
      _releasePlayer();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isPlayerRoute(route)) {
      _releasePlayer();
    }
  }

  void _releasePlayer() {
    // 异步 fire-and-forget,  不阻塞路由动画.  PlayerService 内部
    // 自己处理 _disposed 标志,  重复调不会出问题.
    _playerService.stop();
  }
}
