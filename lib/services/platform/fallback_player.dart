import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils/crash_logger.dart';

/// libmpv.so 在某些 TV box 加载失败时的 fallback 播放器。
///
/// 通过 platform channel `com.threelive.iptv/fallback_player` 调 native 端
/// (MainActivity.kt) 用 Android MediaPlayer 打开 url。native 端未注册时
/// invokeMethod 会抛 MissingPluginException, 这里 catch 后静默失败 ——
/// 关键是 APP 不闪退, 而不是一定要能播出来。
class FallbackMediaPlayer {
  FallbackMediaPlayer();

  static const _channel = MethodChannel('com.threelive.iptv/fallback_player');

  Future<bool> play(String url) async {
    try {
      final result = await _channel.invokeMethod<bool>('play', {'url': url});
      return result ?? false;
    } catch (e) {
      debugPrint('FallbackMediaPlayer.play failed: $e');
      await CrashLogger.log('FallbackMediaPlayer.play failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('FallbackMediaPlayer.stop failed: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (e) {
      debugPrint('FallbackMediaPlayer.pause failed: $e');
    }
  }

  Future<void> resume() async {
    try {
      await _channel.invokeMethod('resume');
    } catch (e) {
      debugPrint('FallbackMediaPlayer.resume failed: $e');
    }
  }
}
