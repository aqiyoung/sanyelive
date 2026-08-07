import 'dart:async';
import 'dart:io' show HttpOverrides;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/cctv_source.dart';
import 'core/http/dns_warmup.dart';
import 'core/http/ipv4_client.dart';
import 'core/router/router.dart';
import 'core/theme/colors.dart';
import 'core/theme/theme.dart';
import 'data/remote_channels_source.dart';
// sources/known.json.  main.dart 预热用.
import 'data/sources/remote_sources_source.dart';
//  预热 ChannelRepository — loadBundled 第一次 1-2s 读 + parse assets/data,
//  玩家进频道 initState await channelsProvider.future 会多等这一下.
//  跟 +124 media_kit 预热是同样思路:  runApp 之前 fire-and-forget 让
//  static _cached 缓存就绪,  后续 loadBundled 零 IO.
import 'data/repositories/channel_repository.dart';
// 离线台标清单 (TV 模式优先 AssetImage 渲染, 不再依赖运行时网络拉 logo).
import 'data/tv_logo_manifest.dart';
// theme_provider.dart 保留文件 (老 prefs key 兼容), 但 main.dart 不再 watch
// themeModeProvider / ThemeModeNotifier.  sharedPreferencesProvider 仍需 import —
// sharedPreferencesProvider 仍需 import — main.dart override + version_checker.dart 也用它.
// 之前一轮删 import 导致 build 挂 (lib/main.dart:86 Undefined name), 这里再加回.
import 'features/settings/theme_provider.dart';
import 'services/vod_source_registry.dart';
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
// adb pull /sdcard/Android/data/com.threelive.tv/files/crash.log 看错误.
import 'utils/crash_logger.dart';

// 从 PackageInfo 运行时读 pubspec.yaml,  每次 bump 版本自动同步到设置页.
//
// 旧 const 保留用作 fallback (如果 PackageInfo 读失败,  e.g. test 环境):
// const currentVersion = '0.0.0+0';
// const currentVersionCode = 0;


void main() async {
  // 保证任何异常都不阻塞 runApp().  之前 SharedPreferences 重试
  // 失败会抛异常中断 main(),  runApp 永远不执行 → 白屏闪退.
  await CrashLogger.log('=== main() START ===');
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // 预加载离线台标清单 (assets/logos/manifest.json).  CI 构建前由
    // scripts/fetch_tv_logos.py 下载打包, 本地若未跑脚本则清单为空, 显示层
    // 自动回退 logoUrl / 文字台标, 不阻塞启动.
    try {
      await CrashLogger.log('step1.5: before loadTvLogoManifest');
      await loadTvLogoManifest();
      await CrashLogger.log('step1.5: loadTvLogoManifest OK');
    } catch (e) {
      await CrashLogger.log('step1.5: loadTvLogoManifest FAILED: $e');
    }
    try {
      await CrashLogger.init();
      await CrashLogger.log('step1: CrashLogger OK');
    } catch (e) {
      debugPrint('=== CrashLogger init failed (non-fatal): $e ===');
    }
    await CrashLogger.log('step2: before orientations');
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SharedPreferences prefs;
    try {
      await CrashLogger.log('step3: before SharedPreferences');
      prefs = await _loadSharedPreferencesOrMock();
      await CrashLogger.log('step3: SharedPreferences OK');
    } catch (e) {
      await CrashLogger.log('step3: SharedPreferences FAILED: $e');
      debugPrint('=== SharedPreferences failed, falling back to in-memory: $e ===');
      // 兜底: 用内存版空 SharedPreferences, 不让 app 崩到顶层 fatal 崩溃页.
      // 关键修复: 不要再调 SharedPreferences.getInstance() — 它仍会抛,
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        await CrashLogger.log('step3: in-memory fallback OK');
      } catch (e2) {
        await CrashLogger.log('step3: in-memory fallback FAILED: $e2');
        debugPrint('=== SharedPreferences fallback also failed: $e2 ===');
        rethrow; // 真·无法恢复, 交给 main() 顶层 fatal handler
      }
    }
    try {
      await CrashLogger.log('step4: before loadPersistedScores');
      await CctvSourcePicker.loadPersistedScores();
      await CrashLogger.log('step4: loadPersistedScores OK');
    } catch (e) {
      debugPrint('=== loadPersistedScores failed (non-fatal): $e ===');
      await CrashLogger.log('step4: loadPersistedScores FAILED: $e');
    }
    _applySystemUiOverlay(prefs);
    if (IPv4Client.defaultEnabled) {
      HttpOverrides.global = Ipv4HttpOverrides();
    }
    unawaited(DnsWarmup.warmup(_warmupHostnames()));
    unawaited(_prewarmRemoteChannels());
    unawaited(_prewarmRemoteSources());
    ErrorWidget.builder =
        (FlutterErrorDetails details) => _CrashScreen(details: details);
    String runtimeVersion;
    int runtimeVersionCode;
    try {
      await CrashLogger.log('step5: before PackageInfo');
      final info = await PackageInfo.fromPlatform();
      runtimeVersion = 'v${info.version}.${info.buildNumber}';
      runtimeVersionCode = int.tryParse(info.buildNumber) ?? 0;
      await CrashLogger.log('step5: PackageInfo OK: $runtimeVersion');
    } catch (e) {
      runtimeVersion = '0.0.0+0';
      runtimeVersionCode = 0;
      await CrashLogger.log('step5: PackageInfo FAILED: $e');
      debugPrint('=== PackageInfo.fromPlatform failed, fallback: $e ===');
    }
    bool libmpvAvailable = true;
    try {
      await CrashLogger.log('step6: before checkLibmpv');
      const channel = MethodChannel('com.threelive.iptv/check_libmpv');
      libmpvAvailable =
          await channel.invokeMethod<bool>('checkLibmpv') ?? false;
      await CrashLogger.log('step6: checkLibmpv OK: $libmpvAvailable');
    } catch (e) {
      await CrashLogger.log('step6: checkLibmpv FAILED: $e');
      debugPrint('=== libmpv 预检异常 (非致命): $e ===');
      libmpvAvailable = true;
    }
    await CrashLogger.log('step7: before ProviderContainer');
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        vodSharedPreferencesProvider.overrideWithValue(prefs),
        currentVersionCodeProvider.overrideWithValue(runtimeVersionCode),
        currentVersionStringProvider.overrideWithValue(runtimeVersion),
        libmpvAvailableProvider.overrideWithValue(libmpvAvailable),
      ],
    );
    try {
      startChannelsAutoRefresh(container: container);
      startSourcesAutoRefresh(container: container);
    } catch (e) {
      debugPrint('=== auto refresh start failed (non-fatal): $e ===');
      await CrashLogger.log('step8: autoRefresh FAILED: $e');
    }
    unawaited(container.read(channelRepositoryProvider).loadBundled());
    final playerObserver = PlayerRouteObserver(container);
    final lifecycleListener = _AppLifecycleListener(container);
    WidgetsBinding.instance.addObserver(lifecycleListener);
    await CrashLogger.log('step9: before runApp');
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: IptvApp(playerObserver: playerObserver),
      ),
    );
    Future.microtask(() async {
      try {
        await container.read(versionCheckerProvider.notifier).checkOnStartup();
      } catch (e) {
        debugPrint('=== version check failed (silenced): $e ===');
      }
    });
  } catch (fatal) {
    // 终极兜底: 任何未预料的异常都不阻塞.
    // 写 crash log + 仍然 runApp 显示错误页.
    await CrashLogger.log('FATAL init error: $fatal');
    debugPrint('=== FATAL init error: $fatal ===');
    ErrorWidget.builder =
        (FlutterErrorDetails d) => ColoredBox(
          color: const Color(0xFFFFEBEE),
          child: Center(
            child: Text(
              '启动失败: ${d.exceptionAsString()}',
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        );
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              '启动失败, 请查看 /sdcard/Download/iptv_crash.log',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

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

/// 失败静默,  channelsProvider._enrichWithRemoteSources 会自动 fallback 本地.
/// 用独立 short-lived container — 不污染 main() 主 container 状态.
Future<void> _prewarmRemoteSources() async {
  try {
    final warmContainer = ProviderContainer();
    try {
      await warmContainer.read(remoteSourcesProvider.future);
      debugPrint('_prewarmRemoteSources: remote fetched OK');
    } finally {
      warmContainer.dispose();
    }
  } catch (e) {
    debugPrint('_prewarmRemoteSources: failed (will use local fallback): $e');
  }
}

void _applySystemUiOverlay(SharedPreferences prefs) {
  //   - prefs 里 theme_mode == 'light' → 黑图标
  //   - prefs 里 theme_mode == 'dark'  → 白图标
  //   - prefs 里 theme_mode == 'system' / 未设置 → 跟 platformBrightness
  // runApp 之后各页面用 AnnotatedRegion 再覆盖一次, 这里只是首屏启动兜底.
  final brightness = _resolvedBrightness(prefs);
  final isDark = brightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor:
          isDark ? IptvColors.darkBg : IptvColors.bgParchment,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ),
  );
}

/// 根据 prefs theme_mode + 系统亮度, 解析当前应该是亮/暗.
Brightness _resolvedBrightness(SharedPreferences prefs) {
  switch (prefs.getString(ThemeModeNotifier.kThemeModeKey)) {
    case 'light':
      return Brightness.light;
    case 'dark':
      return Brightness.dark;
    case 'system':
    default:
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }
}

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
    // 之前锁死深色 (ThemeMode.dark) 导致 settings 页面切主题无效.
    // 现在 settings → 外观 → 主题模式 的 system/浅色/深色选择真正生效.
    // 检测到 outdated 时弹 ForceUpdateDialog.  ref.listen 的 context
    // 是 ConsumerWidget.build 提供的,  MaterialApp 已建好,  Navigator
    // ref.listen 在 State.build 顶层用,  context 是 widget 自身 (MaterialApp
    // 之上),  Navigator.of(context) 找不到 → ForceUpdateDialog 闪退.
    // _SplashOverlay,  由 MaterialApp.builder 包在 MaterialApp 内部 ——
    // Builder 拿到的 context 是 MaterialApp 之下的,  拿 Navigator 正常.
    ref.listen<VersionCheckState>(versionCheckerProvider, (prev, next) {
      if (next is VersionCheckOutdated) {
        ForceUpdateDialog.show(context);
      }
    });
    return MaterialApp.router(
      title: '视界',
      debugShowCheckedModeBanner: false,
      theme: IptvTheme.light(),
      darkTheme: IptvTheme.dark(),
      themeMode: ref.watch(themeModeProvider), // 跟随用户选择
      routerConfig: buildRouter(playerObserver: playerObserver),
      // 完整动画).  保留 +177 的 MaterialApp.builder 架构 — context 在
      // MaterialApp 之下,  ref.listen 弹 ForceUpdateDialog 能找到 Navigator.
      builder: (context, child) => _ErrorBoundary(
        child: SplashScreen(child: child ?? const SizedBox()),
      ),
    );
  }
}

/// 的 ref.listen 上下文.  MaterialApp.builder 会把 child (路由页面) 包在
/// _SplashOverlay 里,  splash 结束时渐隐.  3s 后自动消失.
///
/// 的 SplashScreen — SVG logo 像素一致 + motion.css v2 完整动画时间线
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
      // CachedNetworkImage 的 errorWidget 已兜底显示默认图标,
      // 不要拦截到 crash screen 上.
      if (_isNetworkImageError(details)) return;
      if (mounted) setState(() => _error = details);
    };
  }

  /// 判断是否为网络图片加载失败 (非致命, 不应触发 crash screen).
  bool _isNetworkImageError(FlutterErrorDetails details) {
    final exc = details.exceptionAsString().toLowerCase();
    return exc.contains('http request failed') ||
        exc.contains('network_image') ||
        exc.contains('image resource') ||
        exc.contains('httpexception') ||
        exc.contains('无效请求方法') ||
        exc.contains('connection refused') ||
        exc.contains('连接被拒绝') ||
        (details.stack?.toString().contains('network_image_io') ?? false);
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
                'APP 启动时发生错误, 详细信息如下。重启 / 清除缓存 / 重装可能解决。',
                style: TextStyle(fontSize: 13, color: Color(0xFF7F0000)),
              ),
              const SizedBox(height: 8),
              const Text(
                '崩溃日志: /sdcard/Download/iptv_crash.log\n'
                '用盒子文件管理器打开 Download 文件夹查看',
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF1565C0)),
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

/// 杀进程 (detached) 时彻底释放.  配合 Android manifest 的
/// android:stopWithTask=true + PlayerRouteObserver,  三层保险.
///
/// 启动时不读 playerServiceProvider (避免触发 libmpv native crash).
/// 生命周期事件触发时才懒读,  如果 libmpv 没初始化成功则 noop.
class _AppLifecycleListener with WidgetsBindingObserver {
  _AppLifecycleListener(this._container);

  final ProviderContainer _container;

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  PlayerService? _tryGetService() {
    try {
      return _container.read(playerServiceProvider);
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final player = _tryGetService();
    if (player == null) return;
    switch (state) {
      case AppLifecycleState.paused:
        player.pause();
        break;
      case AppLifecycleState.inactive:
        player.pause();
        break;
      case AppLifecycleState.hidden:
        player.pause();
        break;
      case AppLifecycleState.detached:
        player.stop();
        // ignore: discarded_futures
        player.dispose();
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }
}


