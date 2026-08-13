import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../source_failover.dart';

/// 对 [player] 应用全屏播放路径的渲染配置。
///
/// hwdec 已由 [mediaKitVideoControllerProvider] 在 VideoController 构造时锁定为
/// auto-safe (MediaCodec 硬件解码), 此处不再改动 (运行时改 hwdec 无法重建解码
/// 后端, 不可靠)。这里只控制去隔行: 全屏对 1080i 开 deinterlace, 并清空软件
/// 去隔行滤镜 (vf='') 以免与硬件解码冲突。
///
/// 仅供 [MediaKitStreamOpener] 调用。
Future<void> configureDeinterlace(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.setProperty('deinterlace', 'yes');
    await platform.setProperty('vf', '');
  } catch (e, st) {
    debugPrint('configureDeinterlace failed: $e\n$st');
  }
}

/// 首页 Hero 小窗口预览的配置。
///
/// hwdec 已由 [mediaKitVideoControllerProvider] 锁定为 auto-copy, 此处不再改动。
/// 预览对隔行梳状纹不敏感, 故关掉 deinterlace 以省算力; 同时清空 vf=''。
///
/// 仅供 [_TvHeroState._startPreview] 调用。
Future<void> configurePreview(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.setProperty('deinterlace', 'no');
    await platform.setProperty('vf', '');
  } catch (e, st) {
    debugPrint('configurePreview failed: $e\n$st');
  }
}

/// 起播成功后 dump mpv 实际渲染参数, 便于真机排查花屏/灰屏。
/// 绿紫噪点通常是 vo=gpu 的硬解 surface 颜色格式错乱; 这些属性能直接看出
/// 实际走了哪个 vo / hwdec / 颜色格式 (imgfmt), 定位是解码层还是渲染层问题。
Future<void> _dumpMpvRenderInfo(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  const keys = <String>[
    'vo',
    'hwdec-current',
    'video-format',
    'video-params/imgfmt',
    'width',
    'height',
    'current-vo',
  ];
  for (final k in keys) {
    try {
      final v = await platform.getProperty(k);
      debugPrint('[mpv] $k = $v');
    } catch (e) {
      debugPrint('[mpv] $k = <unavailable: $e>');
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

  /// 是否已针对当前 [_player] 配置过去隔行参数。
  ///
  /// mpv 属性设置是异步 FFI; provider 创建时不能 await, 所以放到第一次
  /// [open] 前同步等待, 确保首播前已生效。
  bool _configured = false;

  @override
  Future<void> cancel(String url) async {
    // 不再 stop: 新 open 会替换当前流; 旧切换的 cancel 若 stop 会误杀新流.
  }

  Future<void> _configurePlayer() async {
    if (_configured) return;
    _configured = true;
    // 去隔行配置抽成可复用函数, 首页 Hero 预览也用它 (见 [configureDeinterlace]).
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
      if (ok) await _dumpMpvRenderInfo(_player);
      return ok;
    } catch (e) {
      debugPrint('MediaKitStreamOpener.open failed: $e');
      return false;
    }
  }
}
