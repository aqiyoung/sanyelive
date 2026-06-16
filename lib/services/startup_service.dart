import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动恢复服务 — 保存/恢复上次观看的频道
class StartupService {
  /// 抽象的存储层 — test 可注入 [InMemoryStartupStore] 避免 SharedPreferences
  /// 默认实现用 SharedPreferences (生产环境)
  StartupService({Future<SharedPreferences>? Function()? prefsLoader})
      : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsLoader;

  SharedPreferences? _prefs;
  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await _prefsLoader();
  }

  static const String _keyLastChannelId = 'last_channel_id';

  /// 保存上次观看的频道 ID
  Future<void> saveLastChannel(String channelId) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyLastChannelId, channelId);
    } catch (_) {
      // 写入失败不影响功能
    }
  }

  /// 读取上次观看的频道 ID
  Future<String?> loadLastChannel() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_keyLastChannelId);
    } catch (_) {
      return null;
    }
  }

  /// 清除记录
  Future<void> clearLastChannel() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_keyLastChannelId);
    } catch (_) {}
  }
}

/// Riverpod provider
final startupServiceProvider = Provider<StartupService>(
  (ref) => StartupService(),
);
