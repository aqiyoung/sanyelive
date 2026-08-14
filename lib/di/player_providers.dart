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
/// (由 [MediaKitStreamOpener] 在首播前设置)。解码走 MediaCodec 硬件解码
/// (auto-copy), 见 [mediaKitVideoControllerProvider]。
///
/// 首页 Hero 小窗口预览**复用此共享实例**（与全屏播放页同一 Player）。历史
/// 上 `d4c3acc` 用这套默认配置能正常出画面；独立 Preview Player 反而在本
/// 设备上渲染异常。
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
    // 去隔行/软解配置在 [MediaKitStreamOpener.open] 首播前 await 设置,
    // provider 创建不能阻塞, 这里不再异步 setProperty。
    return player;
  } catch (e, st) {
    debugPrint('mediaKitPlayerProvider: failed: $e\n$st');
    unawaited(CrashLogger.log('Player init failed: $e'));
    return null;
  }
});

/// media_kit 视频渲染控制器。
///
/// 渲染路径: vo=gpu (SurfaceTexture 纹理) + **hwdec=no (纯软件解码)**。
///
/// 为什么是 no（完整实测链）:
/// - `auto-copy` (+224/+225): 全屏 CCTV-13 彩色噪点/半屏黑 ❌
/// - `auto-safe` (+226): Hero 小窗 CCTV-1 同样彩色噪点 ❌
/// - `no` (+211 当年钉死时): **全屏正常出画面** ✅ (唯一确认能用的)
///
/// no 的代价: CPU 软解略耗电, 1080p60 可能掉帧; 但在当前设备上这是唯一
/// 能正常渲染的路径。Hero 小窗花屏的根因(共享 Player deinterlace 污染)已由
/// +225 每次 open 重置修复。
///
/// 去隔行由 [MediaKitStreamOpener] 在每次 open 前通过 mpv 属控
/// (deinterlace=yes)。
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
