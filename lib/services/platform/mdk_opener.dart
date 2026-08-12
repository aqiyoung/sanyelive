import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../source_failover.dart';

/// 对 [player] 应用央视 1080i 隔行源的去隔行配置。
///
/// 央视/卫视是 1080i 隔行广播, 必须软件去隔行 (bwdif) 才能消除预览/播放的
/// 梳状隔行纹。同时强制 hwdec=no: Android media_kit_video 默认走
/// mediacodec_embed VO, 该 VO 不支持 mpv 滤镜链, 因此关掉硬解让 deinterlace 生效。
///
/// 幂等: 不会因重复调用而出错。供 [MediaKitStreamOpener] 与首页 Hero 静音预览
/// 复用, 保证两条播放路径的去隔行处理一致 —— 否则首页预览会出花屏/隔行纹。
Future<void> configureDeinterlace(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.setProperty('deinterlace', 'yes');
    await platform.setProperty('hwdec', 'no');
    await platform.setProperty('vf', 'bwdif');
  } catch (e, st) {
    debugPrint('configureDeinterlace failed: $e\n$st');
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
