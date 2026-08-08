//
// 网络模式 — 决定全局 HttpOverrides 的连接策略, 修复"某运营商宽带加载不出来".
//
// 背景:
//   - 早先硬强制 IPv4, 修好了"IPv4-only 老路由器"的卡死, 但移动宽带等
//     IPv6 环境下部分 CDN 没有 A 记录, 硬强制 IPv4 会抛 "No IPv4 address"
//     导致全站加载失败 (用户报: 移动宽带 WiFi 加载不出来, 电信手机流量正常).
//   - 改成"优先 IPv4 + IPv6 兜底"后两类网络都能工作, 作为默认 ('auto').
//   - 极少数纯 IPv4-only 老路由器若仍卡, 可切回 'ipv4' (强制 IPv4 老行为);
//     'system' 则完全交给 Dart 默认 happy-eyeballs.
//
// 注意: HttpOverrides 在 main() 启动时读取本设置安装一次, 切换后需重启生效.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart' show sharedPreferencesProvider;

/// 网络模式枚举.
enum NetworkMode {
  /// 优先 IPv4, IPv4 不可达回退 IPv6 (默认, 兼顾两类网络).
  auto,

  /// 强制仅 IPv4 (老行为), 适配纯 IPv4-only 老路由器.
  ipv4,

  /// 不覆盖, 交给 Dart 默认 happy-eyeballs.
  system;

  static NetworkMode parse(String? raw) {
    switch (raw) {
      case 'ipv4':
        return NetworkMode.ipv4;
      case 'system':
        return NetworkMode.system;
      case 'auto':
      default:
        return NetworkMode.auto;
    }
  }

  String get key {
    switch (this) {
      case NetworkMode.ipv4:
        return 'ipv4';
      case NetworkMode.system:
        return 'system';
      case NetworkMode.auto:
        return 'auto';
    }
  }

  String get label {
    switch (this) {
      case NetworkMode.ipv4:
        return '强制 IPv4';
      case NetworkMode.system:
        return '系统默认';
      case NetworkMode.auto:
        return '自动 (推荐)';
    }
  }

  String get hint {
    switch (this) {
      case NetworkMode.ipv4:
        return '仅走 IPv4, 适配老路由器';
      case NetworkMode.system:
        return '交给系统, 不干预';
      case NetworkMode.auto:
        return '优先 IPv4, 不行再 IPv6';
    }
  }
}

/// 网络模式持久化 (SharedPreferences 'network_mode').
final networkModeProvider =
    NotifierProvider<NetworkModeNotifier, NetworkMode>(NetworkModeNotifier.new);

class NetworkModeNotifier extends Notifier<NetworkMode> {
  static const kNetworkModeKey = 'network_mode';

  @override
  NetworkMode build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return NetworkMode.parse(prefs.getString(kNetworkModeKey));
  }

  /// 切换并持久化. 实际生效需重启应用 (HttpOverrides 启动时安装一次).
  Future<void> setMode(NetworkMode mode) async {
    if (state == mode) return;
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kNetworkModeKey, mode.key);
  }
}
