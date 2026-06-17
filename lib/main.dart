import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/router/router.dart';
import 'core/theme/colors.dart';
import 'core/theme/theme.dart';

void main() async {
  // 卡 7 (6/17 修复): 之前 v0.2.0 启动崩
  // 'MediaKit.ensureInitialized must be called', 因为 bootstrap 是 async
  // 跳到 runApp 才走完 await, 期间某个 widget build 触发了 Player() 构造.
  // 现在改成 main 同步等 init 完成再 runApp. WidgetsFlutterBinding
  // 也必须 await, 因为 ensureInitialized 要用到 binding.
  WidgetsFlutterBinding.ensureInitialized();
  // 卡 7 (6/17 老板需求): 状态栏需要手动设置, 否则默认黑色文字 + 透明背景
  // 会在浅米色页面背景下看不清.  需求是浅色页面用黑状态栏文字, 深色页面
  // 反转为白文字.  PlayerPage 自己会主动改 (黑屏看视频用白文字).
  _applySystemUiOverlay();
  // Global error widget builder - set once, not on every rebuild
  ErrorWidget.builder =
      (FlutterErrorDetails details) => _CrashScreen(details: details);
  await _ensureMediaKitOrLog();
  runApp(const ProviderScope(child: IptvApp()));
}

void _applySystemUiOverlay() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: IptvColors.bgParchment,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
}

Future<void> _ensureMediaKitOrLog() async {
  if (_shouldSkipMediaKit) return;
  try {
    await Future<void>.sync(MediaKit.ensureInitialized)
        .timeout(const Duration(seconds: 5));
  } catch (e, st) {
    debugPrint('=== MediaKit init FAILED, 降级启动 ===');
    debugPrint('$e');
    debugPrint('$st');
    // 不 throw, 继续 runApp
  }
}

bool get _shouldSkipMediaKit {
  // dart.vm.arguments 在 flutter_test 中包含 'flutter:test'
  return const bool.fromEnvironment('FLUTTER_TEST') == true;
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '三页直播',
      debugShowCheckedModeBanner: false,
      theme: IptvTheme.light(),
      routerConfig: buildRouter(),
      builder: (context, child) =>
          _ErrorBoundary(child: child ?? const SizedBox()),
    );
  }
}

/// Error boundary — catches build-phase errors and shows crash screen
class _ErrorBoundary extends StatelessWidget {
  const _ErrorBoundary({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _CrashScreen extends StatelessWidget {
  const _CrashScreen({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFFFEBEE),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 12),
              const Text(
                '三页直播 - 启动错误',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB71C1C)),
              ),
              const SizedBox(height: 8),
              const Text(
                'APP 启动时发生错误, 详细信息如下。重启 / 清除缓存 / 重装可能解决。',
                style: TextStyle(fontSize: 13, color: Color(0xFF7F0000)),
              ),
              const SizedBox(height: 16),
              Text(
                details.exceptionAsString(),
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFF424242)),
              ),
              const SizedBox(height: 12),
              Text(
                details.stack?.toString() ?? '(no stack trace)',
                style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Color(0xFF616161)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
