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
/// 央视/卫视是 1080i 隔行广播, 全屏播放时必须开 mpv 软件去隔行 (bwdif) 才能
/// 消除梳状纹。注意: 软件去隔行只对**软件解码**帧生效, 所以全屏播放前会由
/// [MediaKitStreamOpener] 把 player 的 hwdec 切到 'no'。
///
/// 首页 Hero 小窗口预览则走硬解优先 (auto-safe): 小窗口对隔行不敏感, 而
/// 强制软解在本设备上反而导致花屏/灰屏。预览前会由 [configurePreview]
/// 恢复 hwdec=auto-safe, 避免从播放页返回后继承软解状态。
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
/// 全屏播放 1080i 隔行源前, [MediaKitStreamOpener] 会运行时把 player 切到
/// hwdec=no + deinterlace=bwdif, 不受此处配置影响。
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

/// 首页 Hero 预览专用 [Player]。
///
/// 必须与 [mediaKitPlayerProvider] 隔离：
/// 1. media_kit 单个 [Player] 同时只能输出到一个 [Video] widget，而首页预览与
///    全屏播放页可能因导航状态快速切换导致纹理争用。
/// 2. 全屏播放需要强制软解 + 软件去隔行 (bwdif)，该配置在本设备的小窗口预览
///    上反而花屏/灰屏；预览单独一个 Player 后，两端配置互不干扰。
/// 3. 运行时通过 setProperty 在硬解/软解之间切换，容易让 libmpv 的 decoder /
///    texture 状态混乱，从而出现绿屏。独立 Player + 固定 auto-safe 彻底避开此
///    问题。
///
/// 预览默认静音 (在 [_TvHeroState._startPreview] 里 setVolume(0))；离开首页
/// 时由 Riverpod onDispose 释放，不泄漏 native 资源/声音。
final heroPreviewPlayerProvider = Provider<Player?>((ref) {
  final available = ref.read(libmpvAvailableProvider);
  if (!available) {
    debugPrint('heroPreviewPlayerProvider: libmpv 不可用, 不走预览');
    return null;
  }
  try {
    MediaKit.ensureInitialized();
    final player = Player();
    ref.onDispose(() async {
      try {
        await player.dispose();
      } catch (e) {
        debugPrint('heroPreviewPlayerProvider dispose failed: $e');
      }
    });
    return player;
  } catch (e, st) {
    debugPrint('heroPreviewPlayerProvider: failed: $e\n$st');
    unawaited(CrashLogger.log('Hero preview player init failed: $e'));
    return null;
  }
});

/// 首页 Hero 预览专用视频渲染控制器。
///
/// 固定硬解优先 (auto-safe)，不强制软解，也不设置 deinterlace。这是本设备
/// 小窗口预览能正常出画面的关键配置。
final heroPreviewVideoControllerProvider = Provider<VideoController?>((ref) {
  final player = ref.watch(heroPreviewPlayerProvider);
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
        'heroPreviewVideoControllerProvider: VideoController() threw: $e\n$st');
    unawaited(CrashLogger.log('Hero preview VideoController failed: $e'));
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
