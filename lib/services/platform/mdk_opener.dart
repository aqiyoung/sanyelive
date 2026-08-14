import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../source_failover.dart';
import '../../utils/crash_logger.dart';

/// 对 [player] 应用全屏播放路径的渲染配置。
///
/// hwdec 已由 [mediaKitVideoControllerProvider] 在 VideoController 构造时锁定为
/// auto-safe (MediaCodec 硬件解码), 此处不再改动 (运行时改 hwdec 无法重建解码
/// 后端, 不可靠)。
///
/// ⚠️ Android 16 vo=gpu 渲染修复 (三种 hwdec 全花屏的根因):
///   不再是 vf='' 的问题 (已移除), 而是 OpenGL ES→SurfaceTexture 管线在 Android 16
///   上需要显式指定 gpu-api 和颜色空间参数。这些属性必须在 open 前设置,
///   因为它们影响 vo 初始化。
///
/// 仅供 [MediaKitStreamOpener] 调用。
Future<void> configureDeinterlace(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    // Android 16 渲染兼容: 强制 OpenGL ES (不用 Vulkan, 避免 Adreno 兼容问题)
    await platform.setProperty('gpu-api', 'opengl');
    // 颜色空间 hint: 确保 YUV→RGB 映射正确 (绿/紫噪点的典型修复)
    await platform.setProperty('target-colorspace-hint', 'srgb');
    // 去隔行: 央视/卫视 1080i 必需
    await platform.setProperty('deinterlace', 'yes');
  } catch (e, st) {
    debugPrint('configureDeinterlace failed: $e\n$st');
  }
}

/// 首页 Hero 小窗口预览的配置。
///
/// hwdec 已由 [mediaKitVideoControllerProvider] 锁定为 auto-safe, 此处不再改动。
/// 预览对隔行梳状纹不敏感, 故关掉 deinterlace 以省算力。
///
/// ⚠️ 同样需要 gpu-api/target-colorspace-hint (Android 16 渲染兼容, 见 configureDeinterlace)。
///
/// 仅供 [_TvHeroState._startPreview] 调用。
Future<void> configurePreview(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    // Android 16 渲染兼容 (同全屏)
    await platform.setProperty('gpu-api', 'opengl');
    await platform.setProperty('target-colorspace-hint', 'srgb');
    // 预览不需要去隔行
    await platform.setProperty('deinterlace', 'no');
  } catch (e, st) {
    debugPrint('configurePreview failed: $e\n$st');
  }
}

/// 起播成功后 dump mpv 实际渲染参数, 便于真机排查花屏/灰屏。
///
/// Android 16 上 vo=gpu 管线花屏的修复方向: gpu-api / target-colorspace-hint /
/// vo / hwdec-current / imgfmt。这些属性能直接看出实际渲染路径是否正确。
///
/// [tag] 用于区分来源 (如 'hero-preview' / 全屏留空), 写入日志便于对照。
Future<void> dumpMpvRenderInfo(Player player, {String? tag}) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  final prefix = tag != null ? '[$tag] ' : '';
  const keys = <String>[
    'vo',
    'hwdec-current',
    'gpu-api',
    'target-colorspace-hint',
    'video-format',
    'video-params/imgfmt',
    'deinterlace-current',
    'width',
    'height',
    'current-vo',
  ];
  for (final k in keys) {
    try {
      final v = await platform.getProperty(k);
      debugPrint('[mpv] $prefix$k = $v');
      await CrashLogger.log('[mpv] $prefix$k = $v');
    } catch (e) {
      debugPrint('[mpv] $prefix$k = <unavailable: $e>');
      await CrashLogger.log('[mpv] $prefix$k = <unavailable: $e>');
    }
  }
}

/// media_kit 实现的 [StreamOpener]: 把 URL 真正打开到 [Player]。
///
/// open 不阻塞等到首帧, 而是监听 [Player.stream.playing] 判断是否起播成功,
/// 超时未起播则返回 false, 由 [SourceFailover] 切下一个源。
///
/// 单 Player 切换安全: 同一时刻只有一个 open 应视作"有效"。用 [_generation]
/// 标记每次 open, 已被更新 open 取代的旧调用在结果返回时直接作废 (返回 false),
/// 避免旧切换的成功事件污染新切换。cancel 改为 no-op —— 新 open 会自动
/// 替换当前流, 显式 stop 反而可能误杀正在起播的新流。
class MediaKitStreamOpener implements StreamOpener {
  MediaKitStreamOpener(this._player);

  final Player _player;

  /// 每次 [open] 自增, 用于识别"当前有效"的那次 open。
  int _generation = 0;

  @override
  Future<void> cancel(String url) async {
    // 不再 stop: 新 open 会替换当前流; 旧切换的 cancel 若 stop 会误杀新流.
  }

  /// 每次 [open] 前确保全屏去隔行配置生效。
  ///
  /// 不能用一次性守卫: 首页 Hero 预览会经 [configurePreview] 把共享 Player 的
  /// deinterlace 改回 no, 若此处只在首次 open 设置, 后续全屏 open 会沿用预览
  /// 留下的 no → 央视/卫视 1080i 隔行梳状花屏。故每次 open 都重新置 yes。
  Future<void> _configurePlayer() async {
    await configureDeinterlace(_player);
  }

  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    final myGen = ++_generation;
    try {
      await _configurePlayer();
      final completer = Completer<bool>();
      late final StreamSubscription<dynamic> sub;
      late final Timer timer;
      sub = _player.stream.playing.listen((playing) {
        if (!completer.isCompleted) {
          sub.cancel();
          timer.cancel();
          completer.complete(true);
        }
      });
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          sub.cancel();
          completer.complete(false);
        }
      });

      await _player.open(Media(url));
      final ok = await completer.future;
      // 等待期间已发生更新的切换 -> 本次结果作废.
      if (myGen != _generation) return false;
      if (ok) await dumpMpvRenderInfo(_player);
      return ok;
    } catch (e) {
      debugPrint('MediaKitStreamOpener.open failed: $e');
      return false;
    }
  }
}
