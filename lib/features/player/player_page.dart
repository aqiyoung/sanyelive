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
/// 视频 16:9 在顶 + 下面是节目卡 + 频道横滑.  右下角全屏按钮点一下进真
/// 全屏 (immersiveSticky + landscape).  TV 端 (shortestSide >= 600) 保持
/// v0.3.0 Stack 全屏覆盖模式, 因为 TV 整个屏幕就是视频区.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  // P0-1 (6/17 ChatGPT 建议): 播放页 UI 3s 隐身 — 视频是唯一视觉中心,
  // 重度 IPTV 用户 90% 时间只看视频, 不需要控件抢眼球.
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  static const _hideAfter = Duration(seconds: 3);

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
    // 进入页面时尝试播放
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoPlay());
    // P0-1: 首帧后启动控件隐身计时器
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetHideTimer());
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
    // P0-1: 取消隐身计时器
    _hideControlsTimer?.cancel();
    // P2-2: 离开页面时如果还在全屏, 还原 system chrome.
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // empty list = "use whatever the platform default is" (portrait on
      // phones, landscape on TVs, etc.).  Passing null breaks the
      // argument_type_not_assignable analyzer check on Flutter 3.29.3.
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
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
  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      // v0.3.7+69 (6/19): immersiveSticky → immersive (sticky 模式边缘
      // 滑出再显示,  老板反馈 "状态栏横过来后没全屏沉浸").  改成 immersive
      // 强制完全隐藏状态栏 + 导航栏,  用户要退出点浮动按钮 (v0.3.7+64 加的)
      // 或用 Android back.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      // v0.3.7+69: 横屏时强制 landscape,  不管系统默认.
      // 之前 setPreferredOrientations([]) 退到默认 (portrait on phones),
      // 老板横屏拨横后还是会回到竖屏.
      SystemChrome.setPreferredOrientations(const [
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
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // empty list = "use whatever the platform default is" (portrait on
      // phones, landscape on TVs, etc.).  Passing null breaks the
      // argument_type_not_assignable analyzer check on Flutter 3.29.3.
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      // 6/18 P1 hotfix + v0.3.5.4: 退出全屏还原成全 APP 默认 — 状态栏黑图标
      // (跟浅米色页面配套), 系统导航栏用 colorScheme.surfaceContainer
      // 跟当前主题联动.
      _applySystemUiOverlayForApp();
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
  /// 节目卡 + 频道横滑.  视频区右下角有全屏按钮.
  Widget _buildMobile(BuildContext context) {
    final state = ref.watch(currentPlayerStateProvider);
    final controller = ref.watch(mediaKitVideoControllerProvider);
    final asyncChannels = ref.watch(channelsProvider);

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: asyncChannels.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: scheme.onSurfaceVariant),
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
                // 视频区 (16:9) + 右下角全屏按钮
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoArea(
                        controller: controller,
                        state: state,
                        channel: channel,
                      ),
                      // v0.3.5.4: 全屏按钮背景 + 图标都跟主题联动 —
                      // 浅色下浅底 + 深色图标 (跟浅米色页面风格一致),
                      // 暗色下深底 + 浅色图标 (跟深棕黑页面风格一致).
                      // 背景用 surfaceContainerHigh, 图标用 onSurface
                      // (跟 Material 3 M3 spec 一致).
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: Icon(
                              Icons.fullscreen,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 22,
                            ),
                            tooltip: '全屏',
                            onPressed: _toggleFullscreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 顶栏 (返回 / 频道名 / 收藏等)
                TopBar(
                  channel: channel,
                  state: state,
                  onBack: () => context.pop(),
                ),
                // 节目卡 + 频道横滑 (可滚动)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (channel != null) NowNextProgram(channel: channel),
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
      body: asyncChannels.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: scheme.onSurfaceVariant),
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
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
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
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Column(
                  children: [
                    // v0.3.7+64: TopBar 现在也进 AnimatedOpacity,  节目卡 + 横滑
                    // 跟之前一样贴底.
                    TopBar(
                      channel: channel,
                      state: state,
                      onBack: () => context.pop(),
                      // 6/19 改: 退出全屏按钮在 _controlsVisible=false 仍可点
                      // (独立浮动按钮在右下角,  这个 onExitFullscreen = null).
                      onExitFullscreen: null,
                    ),
                    const Spacer(),
                    if (channel != null)
                      Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NowNextProgram(channel: channel),
                            NextChannelsStrip(
                              currentChannelId: channel.id,
                              allChannels: channels,
                              onChannelTap: _switchTo,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              // 隐藏中提示: 右下角小点 (随时点一下又可以看控件)
              if (!_controlsVisible)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withOpacity(0.24),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              // v0.3.7+64 (6/19): 退出全屏浮动按钮 — 跟 _controlsVisible 独立,
              // 一直显示在右上角.  之前 v0.3.5.5 把它合并进 TopBar,  TopBar 跟着
              // 视频 3s 后一起隐,  用户反馈 "全屏时台标挡视频" 但用户依然需要
              // 一个永远在的退出按钮 (Android back 也可退出全屏,  但显示反馈
              // 是必须的).  现在小图标 (size 18) 半透明 surfaceContainerHigh 背景,
              //  跟 TopBar 的 fullscreen_exit 视觉一致.
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: scheme.surfaceContainerHigh.withOpacity(0.6),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: Icon(
                      Icons.fullscreen_exit,
                      color: scheme.onSurface,
                      size: 18,
                    ),
                    tooltip: '退出全屏',
                    onPressed: _toggleFullscreen,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

