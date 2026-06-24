import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// 抽象的存储接口 — 生产用 [SqfliteFavoritesStore], test 用 [InMemoryFavoritesStore]
abstract class FavoritesStore {
  Future<List<String>> getAll();
  Future<bool> isFavorite(String channelId);
  Future<void> add(String channelId, String channelName);
  Future<void> remove(String channelId);
}

/// sqflite 实现的 [FavoritesStore]
class SqfliteFavoritesStore implements FavoritesStore {
  SqfliteFavoritesStore({Database? db}) : _injectedDb = db;

  final Database? _injectedDb;
  Database? _db;
  // v0.3.7+86 (6/20 老板测试反馈): 多 widget 并发调 getAll()/add() 时,
  // _database getter 在 await 之前判断 _db 仍 null, 都进入 _initDb().
  // 加 _initLock 防止 race condition 打开多次 Database 实例 (资源泄漏 + 偶发
  // ConcurrentModificationError).
  Future<Database>? _initLock;

  static const String _table = 'favorites';

  Future<Database> get _database async {
    if (_injectedDb != null) {
      return _injectedDb!; // ignore: unnecessary_non_null_assertion
    }
    if (_db != null) return _db!;
    // v0.3.7+86: 用 _initLock 保证 _initDb() 只跑一次.  后续 caller await
    // 同一个 Future, 不会重新打开 Database.
    _initLock ??= _initDb();
    _db = await _initLock!;
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'iptv_favorites.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            channel_id TEXT PRIMARY KEY,
            channel_name TEXT NOT NULL,
            added_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  @override
  Future<List<String>> getAll() async {
    try {
      final db = await _database;
      final rows = await db.query(_table, orderBy: 'added_at DESC');
      return rows.map((r) => r['channel_id'] as String).toList();
    } catch (e) {
      debugPrint('SqfliteFavoritesStore.getAll failed: $e');
      return const [];
    }
  }

  @override
  Future<bool> isFavorite(String channelId) async {
    try {
      final db = await _database;
      final rows = await db.query(
        _table,
        where: 'channel_id = ?',
        whereArgs: [channelId],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('SqfliteFavoritesStore.isFavorite failed: $e');
      return false;
    }
  }

  @override
  Future<void> add(String channelId, String channelName) async {
    try {
      final db = await _database;
      await db.insert(
        _table,
        {
          'channel_id': channelId,
          'channel_name': channelName,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      debugPrint('SqfliteFavoritesStore.add failed: $e');
    }
  }

  @override
  Future<void> remove(String channelId) async {
    try {
      final db = await _database;
      await db.delete(
        _table,
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
    } catch (e) {
      debugPrint('SqfliteFavoritesStore.remove failed: $e');
    }
  }
}

/// 内存实现 — 用于 test (不依赖 sqflite)
class InMemoryFavoritesStore implements FavoritesStore {
  final Map<String, ({String id, String name, int addedAt})> _map = {};

  @override
  Future<List<String>> getAll() async {
    final list = _map.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list.map((e) => e.id).toList();
  }

  @override
  Future<bool> isFavorite(String channelId) async =>
      _map.containsKey(channelId);

  @override
  Future<void> add(String channelId, String channelName) async {
    _map[channelId] = (
      id: channelId,
      name: channelName,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> remove(String channelId) async {
    _map.remove(channelId);
  }
}

/// 收藏服务 — 依赖一个 [FavoritesStore]
class FavoritesService {
  FavoritesService({FavoritesStore? store})
      : _store = store ?? SqfliteFavoritesStore();

  final FavoritesStore _store;

  /// 查询所有收藏的频道 ID (按添加时间倒序)
  Future<List<String>> getAll() => _store.getAll();

  /// 判断是否已收藏
  Future<bool> isFavorite(String channelId) => _store.isFavorite(channelId);

  /// 添加收藏
  Future<void> add(String channelId, String channelName) =>
      _store.add(channelId, channelName);

  /// 移除收藏
  Future<void> remove(String channelId) => _store.remove(channelId);

  /// 切换收藏状态, 返回切换后的状态 (true=已收藏)
  Future<bool> toggle(String channelId, String channelName) async {
    final fav = await _store.isFavorite(channelId);
    if (fav) {
      await _store.remove(channelId);
      return false;
    } else {
      await _store.add(channelId, channelName);
      return true;
    }
  }
}

/// Riverpod provider
final favoritesServiceProvider = Provider<FavoritesService>(
  (ref) => FavoritesService(),
);

/// 收藏列表 provider (刷新用)
final favoritesProvider = FutureProvider<List<String>>((ref) async {
  final svc = ref.watch(favoritesServiceProvider);
  return svc.getAll();
});
