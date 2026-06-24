import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/category/category_page.dart';
import '../../features/favorites/favorites_page.dart';
import '../../features/home/home_page.dart';
import '../../features/player/player_page.dart';
import '../../features/search/search_page.dart';
import '../../features/settings/settings_page.dart';
import '../../services/player_service.dart';

class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String category = '/category/:catId';
  static const String player = '/player/:channelId';
  static const String search = '/search';
  static const String favorites = '/favorites';
  static const String settings = '/settings';

  static String categoryPath(String catId, {String? title, int? count}) {
    final query = <String, String>{};
    if (title != null) query['title'] = title;
    final uri = Uri(
      path: '/category/$catId',
      queryParameters: query.isEmpty ? null : query,
    );
    return uri.toString();
  }

  static String playerPath(String channelId) => '/player/$channelId';
}

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
          GoRoute(
            path: 'category/:catId',
            name: 'category',
            builder: (context, state) {
              final catId = state.pathParameters['catId']!;
              final title = state.uri.queryParameters['title'];
              return CategoryPage(categoryId: catId, title: title);
            },
          ),
          GoRoute(
            path: 'player/:channelId',
            name: 'player',
            builder: (context, state) {
              final channelId = state.pathParameters['channelId']!;
              return PlayerPage(channelId: channelId);
            },
          ),
          GoRoute(
            path: 'search',
            name: 'search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: 'favorites',
            name: 'favorites',
            builder: (context, state) => const FavoritesPage(),
          ),
          GoRoute(
            path: 'settings',
            name: 'settings',
            builder: (context, state) => const SettingsPage(),
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

class PlayerRouteObserver extends NavigatorObserver {
  PlayerRouteObserver(this._container);

  final ProviderContainer _container;

  bool _isPlayerRoute(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return false;
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
    try {
      final svc = _container.read(playerServiceProvider);
      svc.stop();
    } catch (_) {}
  }
}
