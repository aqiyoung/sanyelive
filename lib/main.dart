import 'dart:async';
import 'dart:io' show HttpOverrides;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/cctv_source.dart';
import 'core/http/dns_warmup.dart';
import 'core/http/ipv4_client.dart';
import 'core/router/router.dart';
import 'core/theme/colors.dart';
import 'core/theme/theme.dart';
import 'features/settings/theme_provider.dart';
import 'features/update/force_update_dialog.dart';
import 'services/player_service.dart';
import 'services/version_checker.dart';

// v0.3.7.2 (6/19): 不再写 const 写死的 currentVersion / currentVersionCode.
// 从 PackageInfo 运行时读 pubspec.yaml,  每次 bump 版本自动同步到设置页.
// 之前 const 永远显示 0.3.5+37 是 subagent 漏改的 bug.
//
// 旧 const 保留用作 fallback (如果 PackageInfo 读失败,  e.g. test 环境):
// const currentVersion = '0.0.0+0';
// const currentVersionCode = 0;

void main() async {
  // 卡 7 (6/17 修复): 之前 v0.2.0 启动崩
  // 'MediaKit.ensureInitialized must be called', 因为 bootstrap 是 async
  // 跳到 runApp 才走完 await, 期间某个 widget build 触发了 Player() 构造.
  // 现在改成 main 同步等 init 完成再 runApp. WidgetsFlutterBinding
  // 也必须 await, 因为 ensureInitialized 要用到 binding.
  WidgetsFlutterBinding.ensureInitialized();
  // 6/18 P3-1: 把 PlayerService 创建提到 runApp 之前,  才可以传进
  // PlayerRouteObserver + WidgetsBindingObserver.  media_kit Player()
  // 必须 ensureInitialized() 后才能建,  上一步已 await 完成.
  // 0.3.6+19: shared_preferences 也提前拿,  override 给 themeModeProvider.
  // 跳过逻辑:  flutter_test 模式下 SharedPreferences 抛 MissingPluginException,
  //  改成 noop override (用空内存版),  行为退化为默认 system theme.
  final prefs = await _loadSharedPreferencesOrMock();
  // v0.3.6+42: 加载持久化 health_score (SharedPreferences)
  await CctvSourcePicker.loadPersistedScores();
  // v0.3.8+93 (6/20 P1-3): 启动时先读 prefs, 再调 _applySystemUiOverlay.
  // 之前用 system platformBrightness 近似,  用户手动切主题后启动会闪
  // (APP 启动那一顿是错的颜色,  几帧后才被 MaterialApp 修复).
  // 现在读 themeMode 持久化的值,  启动即正确.
  _applySystemUiOverlay(prefs);
  // v0.3.7+50 (6/19): 强制全 APP 走 IPv4 — 国内 wifi/4G IPv6 happy-eyeballs
  // 会拖慢 1-2s.  HttpOverrides.global 一键劫持 dart:io HttpClient.
  if (IPv4Client.defaultEnabled) {
    HttpOverrides.global = Ipv4HttpOverrides();
  }
  // v0.3.7+50 (6/19): DNS + TCP 预热 — 启动时后台跑,  让用户首切频道时
  // 跳过 DNS lookup + TCP handshake, 硬延迟砍半. fire-and-forget, 不阻塞.
  unawaited(DnsWarmup.warmup(_warmupHostnames()));
  // Global error widget builder - set once, not on every rebuild
  ErrorWidget.builder =
      (FlutterErrorDetails details) => _CrashScreen(details: details);
  await _ensureMediaKitOrLog();
  // v0.3.6+42: 加载持久化 health_score (SharedPreferences)
  await CctvSourcePicker.loadPersistedScores();
  // v0.3.7.2 (6/19): 运行时读 pubspec.yaml 真实版本号 — 替代之前 const 写死
  // '0.3.5+37' (subagent 漏改,  设置页永远停在老版本号).  现在每次 release
  // bump pubspec,  设置页/版本检查/强制更新都能读到新版本号.
  // test 环境读不到 PackageInfo,  catch + fallback 到 '0.0.0+0'.
  String runtimeVersion;
  int runtimeVersionCode;
  try {
    final info = await PackageInfo.fromPlatform();
    runtimeVersion = '${info.version}+${info.buildNumber}';
    runtimeVersionCode = int.tryParse(info.buildNumber) ?? 0;
  } catch (e) {
    runtimeVersion = '0.0.0+0';
    runtimeVersionCode = 0;
    debugPrint('=== PackageInfo.fromPlatform failed, fallback to 0.0.0+0: $e ===');
  }
  // 0.3.7+20 (6/18): 后台强制更新 — 注入当前 versionCode + versionString.
  // 编译期 const 来自 pubspec.yaml,  跟 release workflow 跑出来的 APK
  // tag +versionCode 一致.  也跟 services/version_checker.dart 里 parse
  // APK asset 名的 +N 格式对齐.
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentVersionCodeProvider.overrideWithValue(runtimeVersionCode),
      currentVersionStringProvider.overrideWithValue(runtimeVersion),
    ],
  );
  final playerService = container.read(playerServiceProvider);
  // 路由观察器: 离开 /player/* 时 stop + dispose.
  final playerObserver = PlayerRouteObserver(playerService);
  // APP 生命周期观察器: paused/inactive/hidden → pause, detached → stop+dispose.
  final lifecycleListener = _AppLifecycleListener(playerService);
  WidgetsBinding.instance.addObserver(lifecycleListener);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: IptvApp(playerObserver: playerObserver),
    ),
  );
  // 0.3.7+20 (6/18): 后台强制更新 — runApp 后 microtask 异步 check,  不阻塞
  // 启动.  1h 内有 cache 走 cache,  失败静默吞掉,  弹窗只对 outdated 触发.
  // 用 Future.microtask 而不是 scheduleMicrotask 是为了 async/await 一致.
  Future.microtask(() async {
    try {
      await container.read(versionCheckerProvider.notifier).checkOnStartup();
    } catch (e) {
      // 静默 — 后台任务, 失败不骚扰用户.
      debugPrint('=== version check failed (silenced): $e ===');
    }
  });
}

/// v0.3.7+50 (6/19): 启动 DNS 预热 host 列表 — 选国内常用公开源, top10 热门频道.
/// 真实清单: 来自 assets/data/known_sources.json 的 CCTV1-15/5+/4K/35 卫视 top2 URL
/// 抽 host.  这些是用户首屏会点的高频频道,  预热后切台硬延迟砍半.
List<String> _warmupHostnames() => const <String>[
  'ldncctvwbcdtxy.liveplay.myqcloud.com', // CCTV 1/2/3... myqcloud 主源
  '198.204.240.250', //  198.204 IPTV 平台
  'go.bkpcp.top', //  老公开源兜底
  'ivi.bupt.edu.cn', //  北邮公开源兜底
  'play-qukan.cztv.com', //  浙江卫视
  '39.134.115.163', //  39.134 IPTV 平台
  '183.207.248.71', //  江苏卫视
  '39.134.24.166', //  上海卫视
  '118.81.195.79', //  北京卫视
  'ottrrs.hl.chinamobile.com', //  CCTV5 移动源
];

void _applySystemUiOverlay(SharedPreferences prefs) {
  // v0.3.7+59 (6/19): 启动时默认 overlay 跟当前主题走 — 浅色主题用深状态栏图标 +
  // 米色导航栏; 暗色主题用白状态栏图标 + 深色导航栏.  之前 v0.3.7+50 写死浅色,
  // 暗色主题下状态栏图标深色在深背景上看不清, 导航栏还是米色扮眼.
  // v0.3.8+93 (6/20 P1-3): 从 prefs 读持久化 ThemeMode,  不用 system
  // platformBrightness 近似 — 用户切过暗色后启动不再闪.
  // ThemeMode.system: 跟 system 走.  light/dark: 强制跟随.  undefined: 当 system.
  final stored = prefs.getString(ThemeModeNotifier.kThemeModeKey);
  final platformIsDark = WidgetsBinding.instance.platformDispatcher
          .platformBrightness ==
      Brightness.dark;
  final isDark = stored == 'dark' || (stored != 'light' && platformIsDark);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? IptvColors.darkSurface
          : IptvColors.bgParchment,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
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

/// 0.3.6+19: 拿 SharedPreferences.  生产等异步 init,  测试时调用方
/// 会在 setUp 里调 SharedPreferences.setMockInitialValues({}) 让
/// getInstance 返回一个内存版 (flutter_test 自带 fixture),  无需特殊处理.
Future<SharedPreferences> _loadSharedPreferencesOrMock() async {
  return SharedPreferences.getInstance();
}

class IptvApp extends ConsumerWidget {
  const IptvApp({super.key, this.playerObserver});

  final NavigatorObserver? playerObserver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 0.3.6+19: 监听 themeModeProvider, 切换后 MaterialApp 立刻用新 themeMode.
    final themeMode = ref.watch(themeModeProvider);
    // 0.3.7+20 (6/18): 后台强制更新 — 监听 versionCheckerProvider,
    // 检测到 outdated 时弹 ForceUpdateDialog.  ref.listen 的 context
    // 是 MaterialApp 内部 context,  Navigator.of(context, rootNavigator:true)
    // 拿 root Navigator 弹 dialog,  不会被路由栈里其他页面 (player / settings)
    // 盖住.  对话框本身是 barrierDismissible:false,  不点 "立刻更新" / "稍后"
    // 关不掉.  main() runApp 后用 Future.microtask 异步调 checkOnStartup.
    ref.listen<VersionCheckState>(versionCheckerProvider, (prev, next) {
      if (next is VersionCheckOutdated) {
        ForceUpdateDialog.show(context);
      }
    });
    return MaterialApp.router(
      title: '三页直播',
      debugShowCheckedModeBanner: false,
      theme: IptvTheme.light(),
      darkTheme: IptvTheme.dark(),
      themeMode: themeMode,
      routerConfig: buildRouter(playerObserver: playerObserver),
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

/// 6/18 P3-1: APP 生命周期监听器.  切后台 (home 键) 时暂停推流,  系统
/// 杀进程 (detached) 时彻底释放.  配合 Android manifest 的
/// android:stopWithTask=true + PlayerRouteObserver,  三层保险.
class _AppLifecycleListener with WidgetsBindingObserver {
  _AppLifecycleListener(this._player);

  final PlayerService _player;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        // 切后台 (home 键 / 多任务) — 暂停推流,  保留 libmpv 实例.
        // 用户回前台 (resumed) 不会自动恢复,  需要点播放键,  这是预期.
        _player.pause();
        break;
      case AppLifecycleState.inactive:
        // 多窗口/来电/控制中心 — 跟 paused 同样处理,  防止音频透过
        // 其他 APP 听到底声.
        _player.pause();
        break;
      case AppLifecycleState.hidden:
        // Flutter 3.13+ 新增:  类似 inactive,  但 UI 已完全不可见.
        _player.pause();
        break;
      case AppLifecycleState.detached:
        // APP 进程即将被销毁 (系统杀 / 任务划掉 + stopWithTask=true).
        // 彻底释放,  避免 libmpv handle 泄漏.
        _player.stop();
        // dispose 是 ChangeNotifier override,  同步生效;  不能 await,
        // 因为当前 isolate 即将死亡.  释放后 widget 引用本 service 的
        // 状态会失效,  但反正进程要没了.
        // ignore: discarded_futures
        _player.dispose();
        break;
      case AppLifecycleState.resumed:
        // 回前台 — 故意不自动 resume,  让用户主动点播放,  避免
        // 切回 APP 时突然出声吓一跳 (尤其半夜追剧).
        break;
    }
  }
}
