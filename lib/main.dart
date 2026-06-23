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
import 'data/remote_channels_source.dart';
// v0.3.8+133 (6/21 09:49 老板反馈 "启动白屏"):
//  预热 ChannelRepository — loadBundled 第一次 1-2s 读 + parse assets/data,
//  玩家进频道 initState await channelsProvider.future 会多等这一下.
//  跟 +124 media_kit 预热是同样思路:  runApp 之前 fire-and-forget 让
//  static _cached 缓存就绪,  后续 loadBundled 零 IO.
import 'data/repositories/channel_repository.dart';
// v0.3.8+102 (6/20 15:02 老板反馈): 删主题切换, 锁死浅色.
// theme_provider.dart 保留文件 (老 prefs key 兼容), 但 main.dart 不再 watch
// themeModeProvider / ThemeModeNotifier.  sharedPreferencesProvider 仍需 import —
// sharedPreferencesProvider 仍需 import — main.dart override + version_checker.dart 也用它.
// 之前一轮删 import 导致 build 挂 (lib/main.dart:86 Undefined name), 这里再加回.
import 'features/settings/theme_provider.dart';
// v0.3.8+178 (6/23 B+C splash fix): 换真 logo + 完整动画. 之前 v0.3.8+177
// 简陋版 _SplashOverlay 删掉,  改用 lib/features/splash/splash_logo.dart.
// 见该文件 design notes + motion_spec.md / motion.css v2 时间线.
// 设计决策: 不用 flutter_svg — flutter_svg 只能整图渲染, 不能对 #tv-body /
// #antenna-left / #play-triangle 分别加 stagger 动画. 而 motion_spec 要 3 个
// 独立动效 (TV pop-in + 天线伸展 + 三角 fade-in), 只能用 Flutter primitives.
// 跟 SVG viewBox 192×192 1:1 像素对齐 (widget 240×240 = ×1.25).
import 'features/splash/splash_logo.dart';
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
  // v0.3.8+120 (6/20 23:27 老板反馈 "退出全屏 变竖屏了"):
  // 之前 _toggleFullscreen 退出全屏用 setPreferredOrientations([]) = 系统默认
  // (portrait on phones) — 老板横屏全屏后退出变竖屏,  体验断裂.
  // 修法:  启动时全局允许 portrait + landscape,  player_page 切全屏再单独
  // 强制 landscape,  退出全屏用 [portrait, landscape] 让系统决定 (跟设备重力
  // 传感器联动 — 用户拨横还是拨竖都能用).  这样退出全屏不强制 portrait.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
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
  // v0.3.8+125 (6/21 老板拍):  远程频道预热 — 后台拉一次
  // aqiyoung/iptv-channels-organized 分类 JSON,  失败静默吞掉,  fallback
  // 本地 assets/data.  channelsProvider 内部 await remoteChannelsProvider.future,
  // 第一次 await 这时已 resolve → 直接用远程;  远程超时则 fallback 本地.
  // 不阻塞 runApp,  fire-and-forget.  不在 wait list 里 (主流程不等它).
  unawaited(_prewarmRemoteChannels());
  // Global error widget builder - set once, not on every rebuild
  ErrorWidget.builder =
      (FlutterErrorDetails details) => _CrashScreen(details: details);
  await _ensureMediaKitOrLog();
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
  // v0.3.8+124 (6/21 老板反馈 "启动慢 白屏 第一次进不去 点第二次"):
  // 之前 +109 在 player_page.initState 里 ref.read(playerServiceProvider) +
  // ref.read(channelsProvider.future) 预热了服务层,  但 media_kit 的
  // Player() + VideoController() 还要在 player_page 里 ref.watch 才创建,
  // 这两个都是 libmpv init,  第一次创建阻塞主线程 300-800ms.
  // 修法:  main 里 预热 mediaKitPlayerProvider + mediaKitVideoControllerProvider,
  //  启 app 后这俩 provider 已构建好,  进 player_page 只 ref.watch,  零初始化.
  // 三个 provider 一起预热:  Player + VideoController + PlayerService.
  container.read(mediaKitPlayerProvider); // 创建 Player (200-400ms)
  container.read(mediaKitVideoControllerProvider); // 创建 VideoController (300-800ms)
  // v0.3.10.6 (6/23 老板拍): 频道分类数据每日 03:00 自动后台刷新, 不用更新 APP.
  // 启动时: 如果 last refresh > 1 天就立即重拉一次.
  startChannelsAutoRefresh(container: container);
  // v0.3.8+133 (6/21 09:49 老板反馈 "启动白屏"):
  //  预热 ChannelRepository — loadBundled 第一次 1-2s 读 + parse assets/data,
  //  玩家进频道 initState await channelsProvider.future 会多等这一下.
  //  跟 +124 media_kit 预热是同样思路:  runApp 之前 fire-and-forget 让
  //  static _cached 缓存就绪,  后续 loadBundled 零 IO.
  //  tests 环境 (overrideWithValue 零 IO) 不受影响 — 这里是 main() 路径,  测试
  //  走 setUpAll 里自己的 ProviderContainer.
  unawaited(container.read(channelRepositoryProvider).loadBundled());
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

/// v0.3.8+125 (6/21):  启动预热 remote channels — 后台 fire-and-forget.
/// 失败静默,  channelsProvider 会自动 fallback 本地 assets/data.
/// 用独立 short-lived container — 不污染 main() 主 container 状态.
Future<void> _prewarmRemoteChannels() async {
  try {
    final warmContainer = ProviderContainer();
    try {
      await warmContainer.read(remoteChannelsProvider.future);
      debugPrint('_prewarmRemoteChannels: remote fetched OK');
    } finally {
      warmContainer.dispose();
    }
  } catch (e) {
    debugPrint('_prewarmRemoteChannels: failed (will use local fallback): $e');
  }
}

void _applySystemUiOverlay(SharedPreferences prefs) {
  // v0.3.7+59 (6/19): 启动时默认 overlay 跟当前主题走 — 浅色主题用深状态栏图标 +
  // 米色导航栏; 暗色主题用白状态栏图标 + 深色导航栏.  之前 v0.3.7+50 写死浅色,
  // 暗色主题下状态栏图标深色在深背景上看不清, 导航栏还是米色扮眼.
  // v0.3.8+102 (6/20 15:02 老板反馈): 删主题切换, 锁死浅色.  之前用
  // 持久化 themeMode 控制 status bar / nav bar 颜色,  现在强制浅色.
  // prefs 参数保留但暂未用 (其他功能如 favorite / endpoint / version cache 还用).
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
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
    // v0.3.8+102 (6/20 15:02 老板反馈): 删主题切换.  themeMode 锁死 light.
    // 之前 ref.watch(themeModeProvider) — 不再 watch, 直接 hardcode.
    // 0.3.7+20 (6/18): 后台强制更新 — 监听 versionCheckerProvider,
    // 检测到 outdated 时弹 ForceUpdateDialog.  ref.listen 的 context
    // 是 ConsumerWidget.build 提供的,  MaterialApp 已建好,  Navigator
    // 可访问.  v0.3.8+176 错误把 IptvApp 改成 ConsumerStatefulWidget 后,
    // ref.listen 在 State.build 顶层用,  context 是 widget 自身 (MaterialApp
    // 之上),  Navigator.of(context) 找不到 → ForceUpdateDialog 闪退.
    // v0.3.8+177 fix: 改回 ConsumerWidget, splash 动画下放为独立
    // _SplashOverlay,  由 MaterialApp.builder 包在 MaterialApp 内部 ——
    // Builder 拿到的 context 是 MaterialApp 之下的,  拿 Navigator 正常.
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
      themeMode: ThemeMode.light,
      routerConfig: buildRouter(playerObserver: playerObserver),
      // v0.3.8+178 (6/23 B+C splash fix): 换 SanyeliveSplash (SVG logo +
      // 完整动画).  保留 +177 的 MaterialApp.builder 架构 — context 在
      // MaterialApp 之下,  ref.listen 弹 ForceUpdateDialog 能找到 Navigator.
      builder: (context, child) => _ErrorBoundary(
        child: SanyeliveSplash(child: child ?? const SizedBox()),
      ),
    );
  }
}

/// v0.3.8+177: 3s 启动动画 — 独立 StatefulWidget,  避免污染 ConsumerWidget
/// 的 ref.listen 上下文.  MaterialApp.builder 会把 child (路由页面) 包在
/// _SplashOverlay 里,  splash 结束时渐隐.  3s 后自动消失.
///
/// v0.3.8+178 (6/23 B+C splash fix): 删.  改为 lib/features/splash/splash_logo.dart
/// 的 SanyeliveSplash — SVG logo 像素一致 + motion.css v2 完整动画时间线
/// + Material 包裹 + BoxShadow 修复 “黄线” 问题.  MaterialApp.builder 架构不变.
/// (以下 _SplashOverlay 旧类已删除 — 逻辑迁到 lib/features/splash/splash_logo.dart)

/// Error boundary — catches build-phase errors and shows crash screen.
/// Listens to [FlutterError.onError] so layout/render exceptions are surfaced
/// as [_CrashScreen] instead of a blank red error widget.
class _ErrorBoundary extends StatefulWidget {
  const _ErrorBoundary({required this.child});
  final Widget child;

  @override
  State<_ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<_ErrorBoundary> {
  FlutterErrorDetails? _error;

  @override
  void initState() {
    super.initState();
    FlutterError.onError = (details) {
      // Still call the default handler (prints to console / debugDumpApp).
      FlutterError.presentError(details);
      if (mounted) setState(() => _error = details);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _CrashScreen(details: _error!);
    }
    return widget.child;
  }
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

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

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
