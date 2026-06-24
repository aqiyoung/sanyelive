// v0.3.10.11 (6/23 老板反馈 腾讯极光盒子 6 v0.3.10.8 闪退):
//  本地 crash 日志 — 老板装 APK 后看不到 logcat 时,  我们能从 crash.log 拿到线索.
//  写到 externalFilesDir (/sdcard/Android/data/<pkg>/files/) 不需要权限,
//  老板 adb pull 出来就行.
//  三类错误: flutter_error (UI 构建期) + platform_error (native 异步, JNI 崩)
//  + zoned_error (runZonedGuarded 包裹的异步).

import 'dart:async';
import 'dart:io';
import 'dart:ui'
    show ErrorCallback; // v0.3.10.11: 兼容写法 (ErrorCallback 在 dart:ui)

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrashLogger {
  CrashLogger._();

  static bool _initialized = false;
  static File? _logFile;
  // v0.3.10.11: 保留 FlutterError.onError 旧 handler (e.g. _ErrorBoundary
  // 在 main.dart 设的),  我们加自己的 chain,  不覆盖.  同样
  // PlatformDispatcher.onError 也保留.
  static FlutterExceptionHandler? _prevFlutterOnError;
  static ErrorCallback? _prevPlatformOnError;

  /// 启动时调用 — 必须在 runApp() 之前.
  /// - 打开 /sdcard/Android/data/com.threelive.tv/files/crash.log
  /// - 接管 FlutterError.onError + PlatformDispatcher.onError (保留旧链)
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // v0.3.10.15: 同时写两个位置:
    //   1. /sdcard/Download/iptv_crash.log — TV 盒子文件管理器可直接看到
    //   2. app 内部存储 — adb pull 备用
    try {
      // 位置1: /sdcard/Download/ (Android 9 及以下无需权限)
      try {
        _logFile = File('/sdcard/Download/iptv_crash.log');
        if (!await _logFile!.exists()) {
          await _logFile!.create(recursive: true);
        }
        await _writeLog('CrashLogger init OK (Download dir)');
      } catch (e) {
        debugPrint('CrashLogger: /sdcard/Download failed: $e');
        // fallback: app 内部存储
        try {
          final dir = await getApplicationSupportDirectory();
          _logFile = File('${dir.path}/crash.log');
          if (!await _logFile!.exists()) {
            await _logFile!.create(recursive: true);
          }
          await _writeLog('CrashLogger init OK (internal dir)');
        } catch (e2) {
          debugPrint('CrashLogger: internal dir also failed: $e2');
        }
      }
    } catch (e, st) {
      debugPrint('CrashLogger init failed: $e\n$st');
    }

    // 1. Flutter 框架错误 — UI 构建期异常. 保留原 handler, 我们 chain 在前.
    _prevFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _writeLog('flutter_error: ${details.exceptionAsString()}');
      if (details.stack != null) {
        _writeLog('flutter_stack: ${details.stack}');
      }
      // 让原 handler 继续 (e.g. main.dart _ErrorBoundary 会 setState 弹 UI)
      final prev = _prevFlutterOnError;
      if (prev != null) {
        prev(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    // 2. Platform 异步错误 — native crash (JNI throw / libmpv SIGSEGV).
    //    PlatformDispatcher.onError 返回 true 表示 "已处理, framework 不要
    //    走默认 crash 流程".  我们返回 false, 让 framework 也参与 (e.g. 印
    //    red screen).
    _prevPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _writeLog('platform_error: $error');
      _writeLog('platform_stack: $stack');
      final prev = _prevPlatformOnError;
      if (prev != null) {
        return prev(error, stack);
      }
      return false;
    };
  }

  /// 业务代码主动记一条 (e.g. libmpv init 失败时).
  static Future<void> log(String msg) async {
    debugPrint('CrashLogger: $msg');
    await _writeLog(msg);
  }

  /// 当前 log 文件路径 (给 UI 显示, 老板可以 adb pull 这个路径).
  static String? get logFilePath => _logFile?.path;

  /// v0.3.10.13: 读取 native crash log (MainActivity.kt 写的).
  /// 返回文件内容,  不存在则返回 null.
  static Future<String?> readNativeCrashLog() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/native_crash.log');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _writeLog(String msg) async {
    final file = _logFile;
    if (file == null) return;
    try {
      final ts = DateTime.now().toIso8601String();
      await file.writeAsString('$ts: $msg\n', mode: FileMode.append);
    } catch (e) {
      // swallow — log 写不进 debugPrint 也无意义, 至少 logcat 有
    }
  }
}
