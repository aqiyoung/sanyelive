import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart' hide PlayerState;

import '../features/settings/theme_provider.dart';
import '../services/platform/mdk_opener.dart';
import '../services/player_service.dart';

export '../services/player_service.dart';
import '../services/smart_source_router.dart';
import '../services/source_failover.dart';
import '../utils/crash_logger.dart';

/// libmpv 不可用时占位: open 直接记日志并返回 false, 让上层走错误分支。
class _NoopStreamOpener implements StreamOpener {
  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    await CrashLogger.log('_NoopStreamOpener.open($url) — libmpv unavailable');
    return false;
  }

  @override
  Future<void> cancel(String url) async {}
}

/// libmpv.so 可用性开关 (默认 true)。TV box 等环境若加载失败, 置 false 走 fallback。
final libmpvAvailableProvider = Provider<bool>((ref) => true);

/// 全局唯一 [Player] 实例。
///
/// 央视/卫视是 1080i 隔行广播, 必须开 mpv 软件去隔行 (yadif) 才能消除花屏。
/// 注意: 软件去隔行 (yadif) 只对**软件解码**帧生效, 所以 VideoController 的
/// hwdec 必须配成 'no' (见 [mediaKitVideoControllerProvider]) —— 走硬解时
/// deinterlace 是空操作, 这正是之前开了 deinterlace 仍花屏的根因。
final mediaKitPlayerProvider = Provider<Player?>((ref) {
  final available = ref.read(libmpvAvailableProvider);
  if (!available) {
    debugPrint('mediaKitPlayerProvider: libmpv 不可用, 走 Fallback');
    unawaited(CrashLogger.log('libmpv not available, using fallback player'));
    return null;
  }
  try {
    MediaKit.ensureInitialized();
    final player = Player();
    final platform = player.platform;
    if (platform is NativePlayer) {
      unawaited(platform.setProperty('deinterlace', 'yes'));
    }
    return player;
  } catch (e, st) {
    debugPrint('mediaKitPlayerProvider: failed: $e\n$st');
    unawaited(CrashLogger.log('Player init failed: $e'));
    return null;
  }
});

/// media_kit 视频渲染控制器。
///
/// hwdec: 'no' = 强制软件解码, 让 [mediaKitPlayerProvider] 的 deinterlace 生效,
/// 同时完全避开 TV box MediaCodec 的 SIGSEGV。代价: 1080i50 软解更吃 CPU,
/// 老旧电视盒可能掉帧。
final mediaKitVideoControllerProvider = Provider<VideoController?>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  if (player == null) return null;
  try {
    return VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'no',
      ),
    );
  } catch (e, st) {
    debugPrint(
        'mediaKitVideoControllerProvider: VideoController() threw: $e\n$st');
    unawaited(CrashLogger.log('VideoController() construction failed: $e'));
    return null;
  }
});

/// 把 URL 打开到 player 的抽象实现。
final streamOpenerProvider = Provider<StreamOpener>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  if (player == null) return _NoopStreamOpener();
  return MediaKitStreamOpener(player);
});

/// 全局播放服务单例。
final playerServiceProvider = ChangeNotifierProvider<PlayerService>((ref) {
  final opener = ref.watch(streamOpenerProvider);
  final player = ref.watch(mediaKitPlayerProvider);
  final router = SmartSourceRouter(prefs: ref.watch(sharedPreferencesProvider));
  return PlayerService(opener: opener, player: player, router: router);
});

/// 当前播放状态快照, UI 监听它刷新。
final currentPlayerStateProvider = Provider<PlayerState>((ref) {
  final service = ref.watch(playerServiceProvider);
  return service.state;
});
