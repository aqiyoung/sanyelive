// v0.3.13.0 (7/9 老板要求): VOD 源注册器 — 多源持久化 + 单活跃源切换.
//
// 设计:
//   - 内置默认源 = bfzyapi.com (老板 7/9 之前唯一在用的 VOD 源).
//   - 用户可添加自定义源 (name + baseUrl + typeId 方案) 或从 TVBox 4 URL 导入.
//   - 单活跃源:  用户一次选一个源浏览,  VOD providers 全部基于活跃源构造.
//   - SharedPreferences 持久化 (跟 theme_provider.dart 同一模式).
//
// 存储 key:
//   - vod_sources_json:  List<VodSource>.map(toJson)  (含默认 + 用户添加).
//   - vod_active_source_id:  当前活跃源 id (默认 "bfzyapi").

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/vod_source.dart';

/// 默认内置源 id (bfzyapi.com).
const String kBfzyapiSourceId = 'bfzyapi';

/// SharedPreferences key — 持久化 VOD 源列表.
const String kSourcesJsonKey = 'vod_sources_json';

/// SharedPreferences key — 当前活跃源 id.
const String kActiveSourceIdKey = 'vod_active_source_id';

/// 默认内置源 — bfzyapi.com (老板 7/9 前唯一在用的 VOD 源,  永不可删).
/// 用 bfzyapiDefaultTypeIds (海外剧=32, 跟其他 bfzyapi 采集器的 26 不同).
VodSource bfzyapiDefaultSource() => const VodSource(
      id: kBfzyapiSourceId,
      name: '暴风资源',
      baseUrl: 'https://bfzyapi.com/api.php/provide/vod',
      typeIds: bfzyapiDefaultTypeIds,
      builtIn: true,
    );

/// VOD 源注册器 — 持有全部源 + 当前活跃源,  持久化到 SharedPreferences.
class VodSourceRegistry {
  VodSourceRegistry(this._prefs) : _sources = [], _activeSourceId = kBfzyapiSourceId;

  final SharedPreferences _prefs;
  List<VodSource> _sources;
  String _activeSourceId;

  /// 全部已启用源 (默认 bfzyapi + 用户添加).
  List<VodSource> get sources => List.unmodifiable(_sources);

  /// 当前活跃源 id.
  String get activeSourceId => _activeSourceId;

  /// 当前活跃源 (fallback 到 bfzyapi).
  VodSource get activeSource {
    return _sources.firstWhere(
      (s) => s.id == _activeSourceId,
      orElse: () => bfzyapiDefaultSource(),
    );
  }

  /// 加载 (启动时调用一次):  默认 bfzyapi + persisted 源,  合并去重.
  Future<void> load() {
    final raw = _prefs.getString(kSourcesJsonKey);
    if (raw == null || raw.isEmpty) {
      // 首次启动 — 只放默认.
      _sources = [bfzyapiDefaultSource()];
      _activeSourceId = kBfzyapiSourceId;
      return _persist();
    }
    try {
      final list = (json.decode(raw) as List<dynamic>)
          .map((e) => VodSource.fromJson(e as Map<String, dynamic>))
          .toList();
      // 必须有默认 bfzyapi (缺了就补).
      if (!list.any((s) => s.id == kBfzyapiSourceId)) {
        list.insert(0, bfzyapiDefaultSource());
      }
      _sources = list;
      // 恢复上次的活跃源 (校验存在).
      final savedId = _prefs.getString(kActiveSourceIdKey);
      if (savedId != null && _sources.any((s) => s.id == savedId)) {
        _activeSourceId = savedId;
      } else {
        _activeSourceId = kBfzyapiSourceId;
      }
    } catch (e) {
      // 解析失败 — 退回默认.
      _sources = [bfzyapiDefaultSource()];
      _activeSourceId = kBfzyapiSourceId;
    }
    return Future.value();
  }

  /// 切换活跃源 (不存在则 noop).
  Future<void> setActiveSource(String id) async {
    if (!_sources.any((s) => s.id == id)) return;
    _activeSourceId = id;
    await _prefs.setString(kActiveSourceIdKey, id);
  }

  /// 添加源 (同 id 已存在则覆盖).
  Future<void> addSource(VodSource source) async {
    final idx = _sources.indexWhere((s) => s.id == source.id);
    if (idx >= 0) {
      _sources[idx] = source;
    } else {
      _sources.add(source);
    }
    await _persist();
  }

  /// 批量添加 (如 TVBox 导入).
  Future<void> addSources(Iterable<VodSource> sources) async {
    for (final s in sources) {
      final idx = _sources.indexWhere((x) => x.id == s.id);
      if (idx >= 0) {
        _sources[idx] = s;
      } else {
        _sources.add(s);
      }
    }
    await _persist();
  }

  /// 移除源 (builtIn 不可删,  删活跃源则 fallback 到 bfzyapi).
  Future<void> removeSource(String id) async {
    final target = _sources.firstWhere(
      (s) => s.id == id,
      orElse: () => bfzyapiDefaultSource(),
    );
    if (target.builtIn) return; // 内置不可删
    _sources.removeWhere((s) => s.id == id);
    if (_activeSourceId == id) _activeSourceId = kBfzyapiSourceId;
    await _persist();
  }

  Future<void> _persist() async {
    final raw = json.encode(_sources.map((s) => s.toJson()).toList());
    await _prefs.setString(kSourcesJsonKey, raw);
  }
}

/// SharedPreferences Riverpod provider — 跟 theme_provider.dart 同模式,
/// 必须在 ProviderContainer override 或 main() await 后 override.
final vodSharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'vodSharedPreferencesProvider 必须在 ProviderContainer 里 override',
  );
});

/// VodSourceRegistry Riverpod provider — 单例 (app 生命周期内共享).
final vodSourceRegistryProvider =
    Provider<VodSourceRegistry>((ref) {
  final prefs = ref.read(vodSharedPreferencesProvider);
  final registry = VodSourceRegistry(prefs);
  // 启动时异步 load (不阻塞 build,  watch 的话会 rebuild).
  registry.load();
  return registry;
});
