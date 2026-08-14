import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

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
/// 央视/卫视是 1080i 隔行广播, 全屏播放时用 mpv 的 deinterlace 去隔行
/// (由 [MediaKitStreamOpener] 在每次 open 前设置)。解码走 MediaCodec 硬件解码
/// (auto-safe), 见 [mediaKitVideoControllerProvider]。
///
/// 首页 Hero 小窗口预览**复用此共享实例**（与全屏播放页同一 Player）。
///
/// ⚠️ Android 16 渲染兼容性: 三种 hwdec (auto-copy/auto-safe/no) 实测全花屏,
/// 根因在 vo=gpu 的 OpenGL ES→SurfaceTexture 管线, 不在解码器。通过
/// PlayerConfiguration 显式指定 vo + mdk_opener 在 open 前设置 gpu-api 等
/// 参数来修复。详见 [MediaKitStreamOpener._configurePlayer]。
final mediaKitPlayerProvider = Provider<Player?>((ref) {
  final available = ref.read(libmpvAvailableProvider);
  if (!available) {
    debugPrint('mediaKitPlayerProvider: libmpv 不可用, 走 Fallback');
    unawaited(CrashLogger.log('libmpv not available, using fallback player'));
    return null;
  }
  try {
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(
        vo: 'gpu',
        logLevel: MPVLogLevel.warn,
      ),
    );
    return player;
  } catch (e, st) {
    debugPrint('mediaKitPlayerProvider: failed: $e\n$st');
    unawaited(CrashLogger.log('Player init failed: $e'));
    return null;
  }
});

/// media_kit 视频渲染控制器。
///
/// 渲染路径: vo=gpu (SurfaceTexture 纹理) + hwdec=auto-safe (MediaCodec 硬解)。
///
/// 为什么是 auto-safe (硬解优先):
/// - 用户设备硬件无问题 (其他播放器 app 正常播放 CCTV)。
/// - 三种 hwdec 全花屏的根因是 vo=gpu 渲染管线在 Android 16 上的兼容性问题
///   (已通过 PlayerConfiguration.vo + gpu-api 等参数修复, 见 mdk_opener)。
/// - auto-safe 是 MediaCodec 直出 surface 的标准 Android 路径。
final mediaKitVideoControllerProvider = Provider<VideoController?>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  if (player == null) return null;
  try {
    return VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-safe',
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
