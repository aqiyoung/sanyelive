//  写到 externalFilesDir (/sdcard/Android/data/<pkg>/files/) 不需要权限,
//  三类错误: flutter_error (UI 构建期) + platform_error (native 异步, JNI 崩)
//  + zoned_error (runZonedGuarded 包裹的异步).

import 'dart:async';
import 'dart:io';
import 'dart:ui'
    show ErrorCallback;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrashLogger {
  CrashLogger._();

  static bool _initialized = false;
  static File? _logFile;
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

    // 3. 让业务 debugPrint 也落盘 —— 覆盖顶层 debugPrint, 同时保留原生
    //    console 输出. 各处 debugPrint (含 [mpv] / [province] 诊断) 自动写入
    //    日志文件, 无需逐个改调用点. _writeLog 内部不调 debugPrint, 无递归.
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      originalDebugPrint(message, wrapWidth: wrapWidth);
      if (message != null && message.isNotEmpty) {
        _writeLog(message);
      }
    };
  }

  /// 业务代码主动记一条 (e.g. libmpv init 失败时).
  /// 不再走 debugPrint, 避免与重定向后的落盘重复前缀.
  static Future<void> log(String msg) async {
    await _writeLog(msg);
  }

  /// 导出日志到 /sdcard/Download/sanyelive_log_<时间戳>.txt, 返回目标路径.
  /// 文件管理器可对该文件直接分享 (微信/QQ 等) 用于排查.
  /// 抛异常: 日志未初始化 / 文件不存在 / 写入失败.
  static Future<String> export() async {
    final src = _logFile;
    if (src == null) throw Exception('日志未初始化');
    if (!await src.exists()) throw Exception('日志文件不存在');
    final name = 'sanyelive_log_${_timestamp()}.txt';
    final dest = File('/sdcard/Download/$name');
    await src.copy(dest.path);
    return dest.path;
  }

  static String _timestamp() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  static String? get logFilePath => _logFile?.path;

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
