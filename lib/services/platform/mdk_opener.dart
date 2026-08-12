import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../source_failover.dart';

/// 对 [player] 应用全屏播放路径的渲染配置。
///
/// 当前方案: 硬解优先 (auto-safe) + VO/解码器自带去隔行 (deinterlace=yes)。
/// 在 TV/平板等大屏设备上, 强制软解 (hwdec=no) 曾出现绿/紫噪点, 因此全屏
/// 路径保持硬解优先; 1080i 隔行梳状纹由解码器/VO 处理。
///
/// 仅供 [MediaKitStreamOpener] 调用。
Future<void> configureDeinterlace(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.setProperty('deinterlace', 'yes');
    await platform.setProperty('hwdec', 'auto-safe');
    await platform.setProperty('vf', '');
  } catch (e, st) {
    debugPrint('configureDeinterlace failed: $e\n$st');
  }
}

/// 首页 Hero 小窗口预览的配置。
///
/// 在 Android 16 + 新版 libmpv (16KB 页 SDK36) 手机上, 硬解优先 (auto-safe)
/// 在小窗(surface 尺寸动态变化)下会渲染异常(灰屏/彩块马赛克)。因此预览前
/// 强制切换到软件解码 (hwdec=no), 同时关闭去隔行滤镜 (deinterlace=no / vf=''),
/// 避免从全屏播放页带回来的硬解+去隔行状态污染预览。
///
/// 仅供 [_TvHeroState._startPreview] 调用。
Future<void> configurePreview(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.setProperty('deinterlace', 'no');
    await platform.setProperty('hwdec', 'no');
    await platform.setProperty('vf', '');
  } catch (e, st) {
    debugPrint('configurePreview failed: $e\n$st');
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
      return ok;
    } catch (e) {
      debugPrint('MediaKitStreamOpener.open failed: $e');
      return false;
    }
  }
}
