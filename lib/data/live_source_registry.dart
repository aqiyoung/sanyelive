//
// 导入直播源注册器 — 持久化从 TVBox 接口导入的直播频道.
//
// 设计:
//   - 用户从 TVBox 接口 (手动粘贴或预设) 导入 lives → 解析为 TvBoxLiveGroup.
//   - 这里把每个频道存成 ImportedLiveChannel (稳定 id = 组+名 hash),
//     持久化到 SharedPreferences (key: tvbox_live_channels_json).
//   - 上层 (channelsProvider / channelsStreamProvider) 把 imported channels
//     并进现有直播 UI, 复用 SourceDispatcher → SourceFailover 全链路播放.
//
// 为什么不直接存 Channel:  Channel 字段多且跟 assets 绑定, 单独存一份
// 导入态更易增量合并 / 清空; 运行时再映射成 Channel (categories=['导入']).

import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/channel.dart';
import '../services/tvbox_config_parser.dart' show TvBoxLiveGroup;

/// SharedPreferences key — 持久化导入直播频道.
const String kLiveChannelsJsonKey = 'tvbox_live_channels_json';

/// 单条导入的直播频道 (由 TVBox lives 解析而来).
class ImportedLiveChannel {
  const ImportedLiveChannel({
    required this.id,
    required this.groupName,
    required this.name,
    required this.urls,
    this.logoUrl,
  });

  final String id;
  final String groupName;
  final String name;
  final List<String> urls;
  final String? logoUrl;

  /// 稳定 id — 组名 + 频道名 hash, 保证同频道跨会话 id 不变 (路由 / 去重一致).
  static String makeId(String groupName, String name) {
    final raw = '${groupName.trim()}::${name.trim()}';
    return 'tvbox_${raw.hashCode.abs().toRadixString(36)}';
  }

  ImportedLiveChannel copyWith({
    String? id,
    String? groupName,
    String? name,
    List<String>? urls,
    String? logoUrl,
  }) {
    return ImportedLiveChannel(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      name: name ?? this.name,
      urls: urls ?? this.urls,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupName': groupName,
        'name': name,
        'urls': urls,
        'logoUrl': logoUrl,
      };

  factory ImportedLiveChannel.fromJson(Map<String, dynamic> json) =>
      ImportedLiveChannel(
        id: json['id'] as String? ?? '',
        groupName: json['groupName'] as String? ?? '直播',
        name: json['name'] as String? ?? '',
        urls: ((json['urls'] as List?)?.cast<String>()) ?? const <String>[],
        logoUrl: json['logoUrl'] as String?,
      );
}

/// 导入直播源注册器 — 持有全部导入频道, 持久化到 SharedPreferences.
/// 继承 ChangeNotifier: addGroups / clearAll 后 notifyListeners, 让
/// 设置页计数与 channelsProvider (依赖 importedLiveChannelsProvider) 自动刷新.
class LiveSourceRegistry extends ChangeNotifier {
  LiveSourceRegistry(this._prefs) : _channels = const [];

  final SharedPreferences _prefs;
  List<ImportedLiveChannel> _channels;

  /// 全部导入频道 (不可变视图).
  List<ImportedLiveChannel> get channels => List.unmodifiable(_channels);

  /// 导入频道总数.
  int get count => _channels.length;

  /// 加载 (启动时调用一次): 从 SharedPreferences 恢复.
  Future<void> load() {
    final raw = _prefs.getString(kLiveChannelsJsonKey);
    if (raw == null || raw.isEmpty) {
      _channels = const [];
      return Future.value();
    }
    try {
      final list = (json.decode(raw) as List<dynamic>)
          .map((e) => ImportedLiveChannel.fromJson(e as Map<String, dynamic>))
          .where((c) => c.id.isNotEmpty && c.name.isNotEmpty && c.urls.isNotEmpty)
          .toList();
      _channels = list;
    } catch (e) {
      debugPrintLive('LiveSourceRegistry: 解析失败, 重置为空: $e');
      _channels = const [];
    }
    return Future.value();
  }

  /// 从 TVBox lives 分组导入. 同 id 已存在则覆盖 (更新 urls).
  Future<void> addGroups(List<TvBoxLiveGroup> groups) async {
    if (groups.isEmpty) return;
    final byId = <String, ImportedLiveChannel>{
      for (final c in _channels) c.id: c,
    };
    for (final g in groups) {
      for (final ch in g.channels) {
        if (ch.name.isEmpty || ch.urls.isEmpty) continue;
        final id = ImportedLiveChannel.makeId(g.name, ch.name);
        byId[id] = ImportedLiveChannel(
          id: id,
          groupName: g.name,
          name: ch.name,
          urls: ch.urls,
          logoUrl: ch.logoUrl,
        );
      }
    }
    _channels = byId.values.toList();
    await _persist();
    notifyListeners();
  }

  /// 清空全部导入直播频道.
  Future<void> clearAll() async {
    _channels = const [];
    await _persist();
    notifyListeners();
  }

  /// 转为现有直播管线使用的 Channel 列表 (categories=['导入']).
  List<Channel> toChannelList() {
    return _channels
        .map(
          (c) => Channel(
            id: c.id,
            name: c.name,
            country: '',
            categories: const ['导入'],
            altNames: const [],
            logoUrl: c.logoUrl,
            sources: c.urls,
            cctvSource: const [],
            isNsfw: false,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _persist() async {
    final raw = json.encode(_channels.map((c) => c.toJson()).toList());
    await _prefs.setString(kLiveChannelsJsonKey, raw);
  }
}

void debugPrintLive(String msg) {
  // ignore: avoid_print
  print(msg);
}

/// SharedPreferences Riverpod provider — 同 vodSharedPreferencesProvider,
/// 必须在 ProviderContainer 里 override (main.dart).
final liveSharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'liveSharedPreferencesProvider 必须在 ProviderContainer 里 override',
  );
});

/// LiveSourceRegistry Riverpod provider — 单例 (app 生命周期内共享).
final liveSourceRegistryProvider = ChangeNotifierProvider<LiveSourceRegistry>(
  (ref) {
    final prefs = ref.read(liveSharedPreferencesProvider);
    final registry = LiveSourceRegistry(prefs);
    registry.load();
    return registry;
  },
);

/// 导入直播频道 (Channel 形式), 供 channelsProvider / channelsStreamProvider
/// 并进现有直播 UI.
final importedLiveChannelsProvider = Provider<List<Channel>>(
  (ref) => ref.watch(liveSourceRegistryProvider).toChannelList(),
);
