import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../services/player_service.dart';
import '../../services/startup_service.dart';
import 'system_ui_overlay.dart';
import 'widgets/next_channels_strip.dart';
import 'widgets/now_next_program.dart';
import 'widgets/player_top_bar.dart';
import 'widgets/video_area.dart';

/// 播放页 — 卡 5 实现
///   - 顶部: 返回 + 频道名 + 节目时间
///   - 中部: media_kit 视频区 (16:9)
///   - 底部: 当前/下一档节目卡 (NowNextProgram)
///   - 底部: 下一频道横滑条 (NextChannelsStrip)
///
/// P2-2 (6/18 老板反馈): 手机端 (shortestSide < 600) 用 v0.1.7 嵌入布局 —
/// 视频 16:9 在顶 + 下面是节目卡 + 频道横滑.
/// TV 端 (shortestSide >= 600) 保持
/// v0.3.0 Stack 全屏覆盖模式, 因为 TV 整个屏幕就是视频区.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  // v0.3.8+114 (6/20 老板 20:37 反馈):
  //   - +113 删 _hideControlsTimer 是错的! 老板明确要 "点一下出来 +
  //     3s 自动隐" 逻辑.  之前 v0.3.5.5 设计 + +111 修切频道 bug 的
  //     IgnorePointer 才是老板要的行为.
  //   - 删右下角 6×6 px 小点提示 — 老板问 "是什么",  3s 自动隐已足够.
  //   - TopBar.onExitFullscreen = _toggleFullscreen — 老板要 TopBar
  //     永远显示台标 + 返回 + 退出全屏按钮.
  //   - 保留 IgnorePointer + AnimatedOpacity —  控件隐时防切频道 bug.
  // 现在:
  //   - 点视频 → 显示控件 (TopBar + 节目卡 + 横滑),  3s 后自动隐
  //     (TopBar 例外 — 永远显示).
  //   - TopBar 永远显示 (不参与 3s 隐).  节目卡 + 横滑进 AnimatedOpacity.
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  static const _hideAfter = Duration(seconds: 3);

  // v0.3.8+127 (6/21 老板反馈 "启动白屏几秒后出现的"):
  // +125 移 _primeLoadingState 到 addPostFrameCallback (修 CI navigation_test
  // "modify during build" 异常),  但首帧 initState 设的 player state
  // 还是 idle,  老板看到白屏几秒才能看到 loading.  修法:  本地
  // _isInitializing 标志,  build 时检查这个判断显示 Skeleton/player state.
  // initState 同步设 true — 首帧就看到骨架屏 (不是空白).  postFrameCallback
  // 跑完 _primeLoadingState 后设 false — 接管 player state loading 显示.
  bool _isInitializing = true;

// P2-2 (6/18): 移动端嵌入布局 ↔ 全屏覆盖 之间的状态机.
  bool _isFullscreen = false;

  /// P2-2: 移动端判断 — shortestSide < 600 走嵌入布局, TV / 平板走现状
  /// Stack 全屏覆盖.  mounted 检查避免 dispose 后访问 context.
  bool get _isMobile {
    if (!mounted) return true;
    return MediaQuery.of(context).size.shortestSide < 600;
  }

  @override
  void initState() {
    super.initState();
    // v0.3.7+61 (6/19): 进入播放页只边到边 (edgeToEdge) — 状态栏可见 + 透明,
    // 不隐藏.  之前 v0.3.5.19 改回 immersiveSticky 完全隐藏状态栏 + 导航栏
    // (line 57-58 注释),  老板 6/19 14:59 反馈 "播放页状态栏还是没修复".
    // 全屏时 (toggleFullscreen) 才用 immersiveSticky.
    // 状态栏颜色 (透明 + 白图标) 走 _applySystemUiOverlayForPlayer 跟主题.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // v0.3.5.4: SystemUI 样式延后到 postFrameCallback 里设置, 这样能
    // 拿到 Theme.of(context).colorScheme.surfaceContainer 跟当前主题配套.
    // 退出全屏/退出页面会在 _toggleFullscreen / dispose 里同样用主题色.
    // (initState 没 context, 不能直接 Theme.of.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applySystemUiOverlayForPlayer();
    });
    // v0.3.8+109 (6/20 17:52 老板反馈 "点频道 半天进不去 必须点第二下"):
    // 之前 _tryAutoPlay 在 addPostFrameCallback 里跑.  1帧后  await channelsProvider
    // (第一次 lazy load 要 1-2s 读 + parse) 再 play().  loading 状态延后,
    //  老板看到 idle UI + TopBar空态 → 以为没响应 → 再点一次.
    // 修法: initState 同步 ref.read(playerServiceProvider) 预热 player 避免延后
    //       + _tryAutoPlay 立即调 player.play() (即使 ch 还没找到) 让 state.loading 立即亮.
    //       后续 await channelsProvider.future 拿 ch 后若不同 (极少), 不改.
    // v0.3.8+109: 预热 player (避免 _tryAutoPlay 首次 ref.read 的延后)
    ref.read(playerServiceProvider);
    // v0.3.8+109: 预热 channelsProvider (避免 _tryAutoPlay await channels.future 的 1-2s 延后)
    unawaited(ref.read(channelsProvider.future));
    // v0.3.8+125 (6/21): _primeLoadingState 移到 addPostFrameCallback —
    // 同步调会触发 ChangeNotifier.notifyListeners 在 build 中, Riverpod 抛
    // "Tried to modify a provider while the widget tree was building" (CI
    // navigation_test / player_theme_test / fullscreen_overlay_test 全部 fail).
    // addPostFrameCallback 在第一帧 drawFrame 后才跑, 这时 player service
    // 立刻变 loading,  老板点频道第二帧看到 "正在打开…"  UI.
    // v0.3.8+127 (6/21 老板反馈 "启动白屏几秒后出现"):
    // +125 改为 postFrameCallback 后,  首帧 UI 看不到 loading 状态 (还是 idle
    // 或初始状态),  老板看到空白骨架屏几秒后才看到 "正在打开…".  修法:
    // initState 同步设 _isInitializing = true (本地状态),  build 看到
    // _isInitializing=true 就显示 Skeleton widget (本地),  不依赖 player state.
    // postFrameCallback 跑 _primeLoadingState 后立即 setState(false) 接管
    // player state 监听,  首帧就是 Skeleton (不是空白).
    // v0.3.8+127: setState(false) 接管后 player state.loading 接管渲染.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _primeLoadingState();
      setState(() => _isInitializing = false);
    });
    // 进入页面时尝试播放
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoPlay());
    // v0.3.8+114:  恢复控件隐身计时器 — 点屏幕显示 + 3s 自动隐.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetHideTimer());
  }

  /// v0.3.8+109 (6/20): 让 player state 进入 loading — 不等 addPostFrameCallback
  /// 也不等 channelsProvider.  老板点进频道 第一帧/第二帧 就看到 "正在打开…"
  /// loading,  不会以为没响应.
  /// v0.3.8+125 (6/21): 改成 addPostFrameCallback 调 (player_page.dart initState
  /// 注释详述) — 同步调会触发 Riverpod "modify during build" 异常.
  void _primeLoadingState() {
    final svc = ref.read(playerServiceProvider);
    svc.primeLoadingState();
  }

  /// v0.3.7+50: 状态栏/导航栏图标亮度跟主题走 — 浅色主题深图标, 暗色
  /// 主题白图标.  纯函数逻辑在 system_ui_overlay.dart,  给 test/ 调.
  void _applySystemUiOverlayForPlayer() {
    SystemChrome.setSystemUIOverlayStyle(
      buildSystemUiOverlayForPlayer(
        Theme.of(context).colorScheme,
        Theme.of(context).brightness,
      ),
    );
  }

  /// v0.3.7+50: 退出全屏 / 退出页面时还原成全 APP 默认.
  void _applySystemUiOverlayForApp() {
    SystemChrome.setSystemUIOverlayStyle(
      buildSystemUiOverlayForApp(
        Theme.of(context).colorScheme,
        Theme.of(context).brightness,
      ),
    );
  }

  @override
  void dispose() {
    // v0.3.8+114:  恢复取消隐身计时器.
    _hideControlsTimer?.cancel();
    // P2-2: 离开页面时如果还在全屏, 还原 system chrome.
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // v0.3.8+120:  跟 _toggleFullscreen else 保持一致,  允许 portrait + landscape.
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    // 6/17: 退出时还原 edgeToEdge (不是 immersiveSticky).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 卡 7: 还原成全 APP 默认 — 状态栏黑图标 (跟浅米色页面配套),
    // 系统导航栏用 colorScheme.surfaceContainer 跟主题联动.  (v0.3.5.4)
    // 用 try-catch 包起来: dispose 期间 InheritedWidget 可能已经拆, Theme.of
    // 会抛.  异常情况下降级成原全 APP 默认 (黑图标 + 透明 nav bar).
    try {
      _applySystemUiOverlayForApp();
    } catch (_) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      );
    }
    // 6/18 P3-1 (老板反馈): 路由 pop 时显式 stop native player.  不做
    // dispose, 保留 libmpv 实例在内存中 (后续返回频道会重新 open).  这
    // 是 RouteObserver + AppLifecycleListener 之外的第一道保险:  当用户
    // 退到首页 / 切频道时,  player_page 的 State 也会被 Flutter 调
    // dispose,  这时只要调 stop 就能让 libmpv 停止推 PCM,  声音立即停.
    // ChangeNotifierProvider 在 widget 树全部拆掉后才 release service,  所以
    // 这里 read() 仍然拿到同一个 PlayerService 实例,  安全.
    try {
      ref.read(playerServiceProvider).stop();
    } catch (_) {
      // widget 树已拆 + provider 链可能已被释放,  静默忽略.
    }
    super.dispose();
  }

  /// P0-1: 重置隐身计时器 — 用户任何输入 (D-pad / 触屏) 都调这个.
  void _resetHideTimer() {
    if (!mounted) return;
    _hideControlsTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _hideControlsTimer = Timer(_hideAfter, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  /// P2-2: 切真全屏 ↔ 退出.  全屏: immersiveSticky + landscape + 状态栏透
  /// 明 + 白图标, 让视频占满整个屏幕并隐藏状态栏/导航栏.  退出: edgeToEdge
  /// + portrait (默认) + 还原成全 APP 默认 (黑图标 + colorScheme nav bar).
  /// v0.3.5.4: 退出全屏时 nav bar 用 colorScheme.surfaceContainer 跟主题联动.
  /// P2-2: 切真全屏 ↔ 退出.  全屏: immersiveSticky + landscape + 状态栏透
  /// 明 + 白图标, 让视频占满整个屏幕并隐藏状态栏/导航栏.  退出: edgeToEdge
  /// + portrait (默认) + 还原成全 APP 默认 (黑图标 + colorScheme nav bar).
  /// v0.3.5.4: 退出全屏时 nav bar 用 colorScheme.surfaceContainer 跟主题联动.
  /// v0.3.8+127 (6/21 老板反馈 "全屏过程变形"):
  /// 之前 setState 跟 SystemChrome.setPreferredOrientations 是同步
  /// setState + 异步 SystemChrome,  视频 widget 重建后屏幕方向还没切到
  /// landscape,  看着 "过程变形".  修法:  async 函数,  先 await 系统
  /// SystemChrome 调用完,  再 setState.  多等一帧 (await Future.delayed
  /// 16ms) 让视频 widget 拿到新尺寸后再 rebuild.
  Future<void> _toggleFullscreen() async {
    final nextIsFullscreen = !_isFullscreen;
    if (nextIsFullscreen) {
      // v0.3.7+69 (6/19): immersiveSticky → immersive (sticky 模式边缘
      // 滑出再显示,  老板反馈 "状态栏横过来后没全屏沉浸").  改成 immersive
      // 强制完全隐藏状态栏 + 导航栏,  用户要退出点浮动按钮 (v0.3.7+64 加的)
      // 或用 Android back.
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      // v0.3.7+69: 横屏时强制 landscape,  不管系统默认.
      // 之前 setPreferredOrientations([]) 退到默认 (portrait on phones),
      // 老板横屏拨横后还是会回到竖屏.
      // v0.3.8+127:  await setPreferredOrientations 完成 —  物理传感器
      // 响应需要时间,  await 让物理方向真切换了再 setState,  避免中间状态.
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // 6/18 P1 hotfix: 全屏时 status bar 透明 + 白图标, 跟黑底视频配套.
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light, // Android: 白图标
          statusBarBrightness: Brightness.dark, // iOS: 黑背景 -> 白文字
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // v0.3.8+120 (6/20 23:27 老板反馈 "退出全屏 变竖屏了"):
      // 之前 const <DeviceOrientation>[] = 系统默认 = portrait on phones.
      // 老板横屏全屏看视频,  退出后变竖屏 = 体验断裂.
      // 修法:  退出全屏用 [portrait, landscape] 显式允许两个方向 — 系统会根据
      // 设备重力传感器决定方向 (老板拨横还是拨竖都行).  跟 +120 main.dart
      // 全局方向设置一致.
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // 6/18 P1 hotfix + v0.3.5.4: 退出全屏还原成全 APP 默认 — 状态栏黑图标
      // (跟浅米色页面配套), 系统导航栏用 colorScheme.surfaceContainer
      // 跟当前主题联动.
      _applySystemUiOverlayForApp();
    }
    // v0.3.8+127: SystemChrome 调用都 await 完了,  才 setState 切 _isFullscreen.
    // 这样视频 widget rebuild 时屏幕方向已经对了,  不会出现 "过程变形".
    if (!mounted) return;
    setState(() => _isFullscreen = nextIsFullscreen);
    // v0.3.8+114:  恢复 _resetHideTimer 调用 — 切全屏时立即让控件可见
    // (避免老板等 3s 自动隐的第 2 次点击被误判为退出全屏).
    _resetHideTimer();
    // v0.3.8+127: 多等 1 帧 (16ms) 让视频 widget 拿到新尺寸后再 rebuild.
    // 避免方向刚变 + 布局刚变时 视频 contain 计算用的是旧尺寸.
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  /// v0.3.8+115 (6/20 21:07 老板反馈): TopBar ← 返回按钮处理.
  /// 之前 +114 让 onBack = context.pop() — 全屏态点 ← 直接退出页面, 跟
  ///  老板 "点返回可以退出全屏" 不符.  +115 改为:  全屏态点 ← = 退出全屏;
  ///  嵌入布局点 ← = 退回首页.  跟 Android back 系统行为一致 (PopScope 之前
  ///  在 _buildFullscreenOverlay 里没显式拦截 back — back 走系统默认, 等于
  ///  pop.  现在跟我们的 onBack 行为对齐).
  void _onTopBarBack() {
    if (_isFullscreen) {
      _toggleFullscreen();
    } else {
      context.pop();
    }
  }

  Future<void> _tryAutoPlay() async {
    final channels = await ref.read(channelsProvider.future);
    if (!mounted) return;
    final ch = _findChannel(channels, widget.channelId);
    if (ch == null) {
      // 频道 id 找不到, 不动 player
      return;
    }
    if (!mounted) return; // 再检查一次, 避免 dispose 之后调用
    // 卡 6: 保存 last channel id, 主页下次进入会显示「继续观看」
    unawaited(ref.read(startupServiceProvider).saveLastChannel(ch.id));
    try {
      await ref.read(playerServiceProvider).play(ch);
    } catch (e) {
      debugPrint('PlayerPage._tryAutoPlay failed: $e');
    }
  }

  Channel? _findChannel(List<Channel> all, String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _switchTo(Channel ch) async {
    // 用 go_router 切 URL (同时触发 initState 重新 autoPlay)
    context.push('/player/${ch.id}');
  }

  @override
  Widget build(BuildContext context) {
    // P2-2: TV 端 / 全屏时走 v0.3.0 Stack 全屏覆盖.  移动端默认走嵌入布局.
    if (_isFullscreen || !_isMobile) {
      return _buildFullscreenOverlay(context);
    }
    return _buildMobile(context);
  }

  /// P2-2: 移动端嵌入布局 (v0.1.7 风格) — 视频 16:9 在顶, 下面是 TopBar +
  /// 节目卡 + 频道横滑.
  Widget _buildMobile(BuildContext context) {
    final state = ref.watch(currentPlayerStateProvider);
    final controller = ref.watch(mediaKitVideoControllerProvider);
    final asyncChannels = ref.watch(channelsProvider);

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        // v0.3.8+127 (6/21 老板反馈 "启动白屏几秒后出现"):
        // _isInitializing=true (initState 同步设的) → 显示骨架屏,  不依赖
        // asyncChannels.when (后者可能还在 loading).  首帧不是空白.
        child: _isInitializing
            ? const _PlayerPageSkeleton()
            : asyncChannels.when(
                loading: () => Center(
                  child:
                      CircularProgressIndicator(color: scheme.onSurfaceVariant),
                ),
                error: (e, _) => Center(
                  child: Text(
                    '加载失败: $e',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                data: (channels) {
                  final channel = _findChannel(channels, widget.channelId);
                  return Column(
                    children: [
                      // 视频区 (16:9)
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: VideoArea(
                          controller: controller,
                          state: state,
                          channel: channel,
                        ),
                      ),
                      // 顶栏 (返回 / 频道名 / 时钟)
                      // v0.3.8+115: 嵌入布局用 _onTopBarBack (现在只 pop, 因为嵌入
                      // 布局 _isFullscreen=false — 跟全屏 _buildFullscreenOverlay 一致).
                      // v0.3.8+131: 嵌入布局背景 scheme.surface (浅米色),  深棕字.
                      TopBar(
                        channel: channel,
                        state: state,
                        onBack: _onTopBarBack,
                        isFullscreen: false,
                      ),
                      // 节目卡 + 频道横滑 (可滚动)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (channel != null)
                                NowNextProgram(channel: channel),
                              if (channel != null)
                                NextChannelsStrip(
                                  currentChannelId: channel.id,
                                  allChannels: channels,
                                  onChannelTap: _switchTo,
                                ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// P2-2: 全屏覆盖布局 (v0.3.0 行为保留) — 视频填满全屏, 控件盖在上面,
  /// 3s 后自动隐身.  TV 端直接走这条.  移动端点右下角全屏按钮进入.
  /// 6/18 P1 hotfix: 移除 SafeArea (status bar 已隐, SafeArea 反而留 padding
  /// 让视频被压下 ~80px 看着像有顶栏).  _TopBar 也移进 AnimatedOpacity, 3s
  /// 控件隐身时跟节目卡 / 频道横滑一起隐.
  Widget _buildFullscreenOverlay(BuildContext context) {
    final state = ref.watch(currentPlayerStateProvider);
    final controller = ref.watch(mediaKitVideoControllerProvider);
    final asyncChannels = ref.watch(channelsProvider);

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      // v0.3.7+77 (6/19 老板反馈):  全屏背景 Colors.black.
      // 之前 scheme.surface 在浅色主题下是米白色 (0xF5F4ED),  周围米白背景
      //  老板说 "两比才正式全屏" = 第 1 次点完看到米白背景不像全屏态.
      //  改 Colors.black 全面沉浸,  视频底色跟黑背景一体化.
      // (这条注释代替之前的 scheme.surface,  跟 _buildFullscreenOverlay 一体.)
      // 6/18 P1 hotfix: 全屏时不 SafeArea.
      // 6/18 P1 hotfix: 全屏时不 SafeArea.  immersiveSticky 已隐 status bar /
      // nav bar 视觉, 但 SafeArea 仍会按 MediaQuery padding 布局, 压下视频
      // ~24-32px (Android) / ~44px (iOS) 看着像有顶栏.
      // v0.3.8+127 (6/21 老板反馈 "启动白屏几秒后出现"):
      // _isInitializing=true (initState 同步设的) → 显示骨架屏,  不依赖
      // asyncChannels.when (后者可能还在 loading).  首帧不是空白.
      // v0.3.8+133 (6/21 09:49 老板反馈 "全屏也白屏"):
      // 之前 _buildFullscreenOverlay 直接走 asyncChannels.when(loading:)
      // 显示 spinner — 平板 / TV (shortestSide >= 600) 走这条路径,  首帧空白
      // 直到 channelsProvider resolve.  修法:  跟 _buildMobile 一样加
      // _isInitializing 检查,  显示 _PlayerFullscreenSkeleton (黑底 + spinner).
      // initState 同步设 _isInitializing=true,  postFrameCallback 跑完
      // _primeLoadingState 后设 false,  接管 player state loading 显示.
      body: _isInitializing
          ? const _PlayerFullscreenSkeleton()
          : asyncChannels.when(
              loading: () => Center(
                child:
                    CircularProgressIndicator(color: scheme.onSurfaceVariant),
              ),
              error: (e, _) => Center(
                child: Text(
                  '加载失败: $e',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              data: (channels) {
                final channel = _findChannel(channels, widget.channelId);
                // P0-1: 视频区点一下切控件可见性 (原本不可见 -> 显示, 显示中 -> 立即隐藏)
                return Stack(
                  children: [
                    // 视频区填满全屏 (控件盖在上面, 隐身时露出视频)
                    // v0.3.7+79 (6/19 老板反馈): 加 onDoubleTap handler 防止双击切频道误触.
                    //  老板反馈 "全屏播放双击后切换频道的 bug".
                    // 根因: GestureDetector 默认有 double-tap recognizer,  双击拆成 2 次
                    //  onTap,  看着像 控件显示/隐藏快速切换,  加上 _controlsVisible 切
                    //  节目卡 + 横滑 立即显/隐,  老板误以为 "切频道".
                    // 修法: 显式 onDoubleTap handler (什么都不做,  只 触发一次),  让 Flutter
                    //  gesture arena 把双击识别为 "双击" 而不是 2 次单击,  控件不会快速切换.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // v0.3.8+114: 恢复 +111 之前的设计 — onTap 切控件显隐.
                        // 老板 20:37 反馈: "你那点一下出来, 等 3 秒它自动隐藏,
                        // 这个必须要有的, 要不然一直挂着不好看".  +113 删 3s 隐
                        // 是错的逻辑.  恢复 +111 的 IgnorePointer + AnimatedOpacity
                        // 设计 (3s 自动隐 + 防切频道 bug).
                        onTap: () {
                          if (_controlsVisible) {
                            // 显示中: 立即隐藏, 不重置计时器
                            _hideControlsTimer?.cancel();
                            setState(() => _controlsVisible = false);
                          } else {
                            // 隐藏中: 显示并重置计时器
                            _resetHideTimer();
                          }
                        },
                        onDoubleTap: () {
                          // v0.3.7+79: 显式空 handler.  让 Flutter gesture arena
                          // 识别为双击 (不拆成 2 次 onTap).  实际行为: 什么都不做.
                        },
                        child: VideoArea(
                          controller: controller,
                          state: state,
                          channel: channel,
                        ),
                      ),
                    ),
                    // v0.3.7+64 (6/19 老板反馈): 全屏态下 TopBar 也参与 _controlsVisible
                    // 隐身 — 之前 v0.3.5.5 永远 visible 导致全屏时台标 (CCTV 频道名 + LIVE
                    // + 状态条 + 心形收藏) 一直显示挡视频.  现在 3s 后整体隐,  视频是
                    // 唯一视觉中心. 退出全屏按钮改成独立浮动按钮 (右上角 small icon),
                    // 全屏隐身后仍可点 (用户最关键操作).
                    // 6/18 P1 hotfix: 控件层 — 整体走 _controlsVisible 隐身
                    // (TopBar + 节目卡 + 频道横滑一起进 AnimatedOpacity).
                    // v0.3.8+107 (6/20 老板反馈 16:38 "全屏上白边和左边白边"):
                    // 之前只有 Container(半透明黑) 包 节目卡+横滑,  TopBar 区域
                    // 透明渲染在 Scaffold background 上.  某些设备在 immersive 模式
                    // 状态栏不完全隐,  状态栏区域泄露是白色,  老板看到 "上白边".
                    // 修法: 整控件层 Column 外面包 Container(半透明黑 0.55) =
                    // 整控件一致.  删内部重复的 Container.
                    // v0.3.8+111 (6/20 老板反馈 19:13 "点左下/右下切频道 bug"):
                    // 之前只有 AnimatedOpacity 包控件层,  opacity=0 时 children 仍
                    // 响应 tap.  NextChannelsStrip 底部是 InkWell chip 阵列,  第一个
                    // chip 在左下/最后一个在右下, 控件隐藏后仍能点 → 切频道.
                    // 根因:  Flutter Opacity widget 不阻止 hit test.  需要套
                    // IgnorePointer(ignoring: !_controlsVisible).
                    // 修法:  AnimatedOpacity 外包 IgnorePointer,  invisible 时控件
                    // 整体不响应 tap.  visible 时跟之前一样.
                    // v0.3.8+114 (6/20 老板 20:37 反馈):
                    //   - 老板要: 点一下显示控件 + 3s 自动隐 (恢复 +111 设计)
                    //   - TopBar 永远显示 (不参与 3s 隐) — 含台标 + 返回 + 退出全屏
                    //   - 节目卡 + 横滑进 AnimatedOpacity — 3s 自动隐
                    //   - IgnorePointer 防切频道 bug (控件隐时)
                    //   - 删右下角 6×6 px 小点 (老板问 "是什么", 不需要了)
                    //
                    // 结构:
                    //   Stack
                    //     ├── [0] 视频区 GestureDetector (onTap 切显隐)
                    //     ├── [1] TopBar (永远显示, 无 opacity wrap)
                    //     └── [2] IgnorePointer + AnimatedOpacity (节目卡 + 横滑)
                    //
                    // 为什么不把 TopBar 也放进 AnimatedOpacity?
                    //   老板 20:25 反馈 "点一下也要显示台标和返回 + 退出全屏按钮".
                    //   这意味着 TopBar 必须永远显示 (或只被 IgnorePointer 跟 AnimatedOpacity 控制).
                    //   选 "永远显示" — 避免隐藏时老板找不到退出按钮 / 返回按钮.

                    // v0.3.8+115 (6/20 21:07 老板反馈): 整控件层 (TopBar + 节目卡 +
                    // 横滑) 一起 3s 隐.  之前 +114 只 TopBar 永远显示 — 老板反馈
                    // "多了三个控件右侧中间" (⋮ ♡ ↔) + "台标不是一直显示 要自动隐藏
                    // 点击后再出现".  我之前误判 "老板要台标永远显示" 是错的.
                    //  真正需求: 整控件层 3s 隐 + onTap 显示 + 隐.
                    //  +115 修法:  TopBar 进 [2] 的 IgnorePointer + AnimatedOpacity
                    //  一起.  TopBar 简化成只有 ← 返回 (删 ⋮ ♡ ↔ — 删 onExitFullscreen
                    //  删 FavoriteIcon 删 Icons.more_vert).  退出全屏靠 Android back
                    //  (系统行为,  _buildFullscreenOverlay 顶层 PopScope 处理 — 见下面).
                    // v0.3.8+129 (6/21 08:20 老板反馈反转 "台标和返回 要3s影藏啊 点屏幕显示"):
                    // +128 改 TopBar 永远显示是错的.  老板 6/21 08:20 明确反:
                    //  "台标和返回 要3s影藏啊 点屏幕显示".  恢复 +115 设计:  TopBar + 节目
                    // 卡 + 横滑 一起 3s 隐,  点视频区 onTap 唤出.  TopBar 单独显示会跳
                    // 出 控制层 (不如统一隐),  老板全屏时点视频控制台都隐,  看视频清静.
                    //  +129 修法:  TopBar + 节目卡 + 横滑 统一在 _controlsVisible 控制下
                    //  3s 隐.  onTap 视频区 切显示.  跟 +115 一致,  跟 +128 反.
                    // v0.3.8+130 (6/21 08:38 老板反馈 "全屏的台标 有显示了 透明的看不清 改成白色 而且没有返回按钮"):
                    // 老板说 "没有返回按钮"  — 但 TopBar 里 Icons.arrow_back 还在,  问题
                    // 是 Colors.black.withValues(alpha: 0.55) 太浅 + TopBar 文字用
                    // scheme.onSurface (浅色主题是深色)  在黑底视频上几乎隐形 — 看不到
                    // 按了.  修法:  Container 背景加深到 0.85 + TopBar 里全部强制
                    // Colors.white / Colors.white70 不靠主题.  返回按钮 + 台标 + LIVE 状态 +
                    // 时钟  全都清晰可见.
                    IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          color: Colors.black.withOpacity(0.85),
                          child: SafeArea(
                            bottom: false,
                            child: TopBar(
                              channel: channel,
                              state: state,
                              onBack: _onTopBarBack,
                              // v0.3.8+131: 全屏黑底,  白字 (v0.3.8+130 行为).
                              isFullscreen: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // [2] 节目卡 + 频道横滑 — IgnorePointer + AnimatedOpacity 一起,
                    //  3s 自动隐 + 防切频道 bug.  +115: 整控件层 3s 隐 (含 TopBar).
                    //  TopBar 在 [1] 也走 _controlsVisible (跟 [2] 同步显隐).
                    //  关键:  Positioned 放底部 — NowNextProgram + NextChannelsStrip.
                    //  整体结构:
                    //    Stack
                    //      ├── [0] Positioned.fill → 视频 GestureDetector (onTap 切显隐)
                    //      ├── [1] Padding → TopBar (always show in tree, 走 [2] opacity)
                    //      └── [2] Positioned(bottom) → IgnorePointer + AnimatedOpacity (TopBar + 节目卡 + 横滑)
                    //  但实际 +115 还是分开 [1] 和 [2] 各自有自己的 opacity wrap — 这样
                    //  TopBar 是 Padding non-Positioned, 节目卡是 Positioned bottom,
                    //  两者 opacity 同步 (都 _controlsVisible).
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: AnimatedOpacity(
                          opacity: _controlsVisible ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            color: Colors.black.withOpacity(0.55),
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (channel != null)
                                  NowNextProgram(channel: channel),
                                if (channel != null)
                                  NextChannelsStrip(
                                    currentChannelId: channel.id,
                                    allChannels: channels,
                                    onChannelTap: _switchTo,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // v0.3.7+79 (6/19 老板反馈): 删右上角退出全屏浮动按钮.
                    // 老板反馈: "右上角的退出全屏 去掉吧".  v0.3.7+64 加的浮动按钮
                    // 干扰老板,  老板要干净的全屏体验.  退出全屏靠:
                    //   1. Android back (标准行为)
                    //   2. TopBar 里的 fullscreen_exit (v0.3.7+64 在 _buildMobile
                    //      TopBar 里也有全屏/退出全屏按钮,  _controlsVisible=false 时
                    //      TopBar 隐,  但 Android back 总能用)
                    //   3. 双击视频不响应 (下面 onDoubleTap 显式 null)
                    //
                  ],
                );
              },
            ),
    );
  }
}

/// v0.3.8+127 (6/21 老板反馈 "启动白屏几秒后出现"):
/// 嵌入布局骨架屏 — 首帧显示: 16:9 黑色视频区 + 顶栏灰条 + 节目卡占位.
/// 跟 _buildMobile data 状态布局一致,  但所有内容是灰骨架,  不是空白.
/// postFrameCallback 跑 _primeLoadingState 后,  _isInitializing=false,
/// build 接管显示 player state.loading.
class _PlayerPageSkeleton extends StatelessWidget {
  const _PlayerPageSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skeletonColor = scheme.surfaceContainerHighest;
    return Column(
      children: [
        // 16:9 黑色视频区 (跟 data 状态一致)
        const AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(color: Colors.black),
        ),
        // 顶栏灰条 (跟 TopBar 高度一致 ~ 56 px)
        Container(
          height: 56,
          color: scheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              // 返回按钮占位
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: skeletonColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              // 频道名占位
              Container(
                width: 120,
                height: 16,
                decoration: BoxDecoration(
                  color: skeletonColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        // 节目卡灰条
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 当前节目卡占位
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 12),
                // 下一档节目占位
                Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                // 频道横滑占位
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// v0.3.8+133 (6/21 09:49 老板反馈 "全屏也白屏几秒"):
/// 全屏覆盖骨架屏 — 平板/TV (shortestSide >= 600) 走 _buildFullscreenOverlay,
/// 首帧 channelsProvider 还没 resolve,  之前直接显示 spinner 在白底 (其实是
/// Scaffold 黑底) 看着像空白.  修法:  _isInitializing=true 时显示黑底 + 中
/// 间 CircularProgressIndicator,  postFrameCallback 跑 _primeLoadingState
/// 后设 false 接管 player state.loading.
/// 跟 _PlayerPageSkeleton 区别:  全屏不需 AspectRatio (已经覆盖整个屏幕),
///  也不需 TopBar/节目卡/横滑占位 (控件层是后叠上去的,  skeleton 阶段还没
///  频道数据无法知道渲染什么).  简化:  黑底 + 中心 spinner.
class _PlayerFullscreenSkeleton extends StatelessWidget {
  const _PlayerFullscreenSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      ),
    );
  }
}
