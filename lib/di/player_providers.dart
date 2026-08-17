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
  Future<bool> open(
    String url, {
    required Duration timeout,
    bool preferSoftwareDecode = false,
  }) async {
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
/// ⚠️ 央视花屏根因 (ffprobe 实锤): 不是 chroma(央视流实测就是 yuv420p, 与卫视同构),
/// 而是**默认拉了 1080i/1080p 最重主码流**在 Android 16 media_kit 管线上没正确
/// 去隔行/渲染。根治在源级: [CctvSourcePicker] 把腾讯云央视源改为 720p 渐进子码流,
/// [MediaKitStreamOpener] 再设 `hls-bitrate` 封顶双保险。本处 hwdec=auto-copy +
/// [mdk_opener] 的 deinterlace/vf 仅作无害兜底(渐进 720p 下 vf 是 no-op)。
/// 详见 [MediaKitStreamOpener._configurePlayer]。
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
/// 渲染路径: vo=gpu (SurfaceTexture 纹理) + hwdec=auto-copy (MediaCodec 硬解
/// 后把帧拷贝到内存, 再交给 vo=gpu 上传)。
///
/// 为什么是 auto-copy 而不是 auto-safe:
/// - 根治靠源级: [CctvSourcePicker] 把腾讯云央视源改为 720p 渐进子码流(与卫视同构),
///   [MediaKitStreamOpener] 再设 `hls-bitrate` 封顶, 从源头避开 1080i/1080p 花屏。
/// - auto-copy 仍保留作兜底路径: 它把 MediaCodec 解码后的帧**拷贝回内存**, 使
///   [configureDeinterlace] 的 vf 滤镜链(若有 4:2:2 源需转 yuv420p)能真正生效;
///   auto-safe 直出 Surface 会绕过 vf, 故不能用 auto-safe。
/// - 用户设备硬件无问题 (其他播放器 app 正常播放 CCTV)。
final mediaKitVideoControllerProvider = Provider<VideoController?>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  if (player == null) return null;
  try {
    return VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-copy',
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
