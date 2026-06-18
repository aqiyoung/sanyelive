import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../features/favorites/favorite_button.dart';
import '../../services/player_service.dart';
import '../../services/startup_service.dart';
import 'widgets/next_channels_strip.dart';
import 'widgets/now_next_program.dart';
import 'widgets/source_picker_sheet.dart';

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
    // 6/17 (UI 优化): 不再用 immersiveSticky (完全隐藏状态栏) — 老板反馈
    // immersive 时状态栏被隐, 拉下来也看不到频道名.  改成 edgeToEdge 保留
    // 状态栏可见, 但用浅色文字 + 黑色背景.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 卡 7 (6/17 老板需求): 播放页背景黑, 状态栏文字用白图标.
    // 退出时 dispose 还原.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Android: 白图标
        statusBarBrightness: Brightness.dark, // iOS: 黑背景 -> 白文字
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    // 进入页面时尝试播放
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoPlay());
    // P0-1: 首帧后启动控件隐身计时器
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetHideTimer());
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
    // 卡 7: 还原成全 APP 默认 (黑图标, 跟浅米色页面配套)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
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

  /// P2-2: 切真全屏 ↔ 退出.  全屏: immersiveSticky + landscape, 让视频占满
  /// 整个屏幕并隐藏状态栏/导航栏.  退出: edgeToEdge + portrait (默认).
  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // empty list = "use whatever the platform default is" (portrait on
      // phones, landscape on TVs, etc.).  Passing null breaks the
      // argument_type_not_assignable analyzer check on Flutter 3.29.3.
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: asyncChannels.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          ),
          error: (e, _) => Center(
            child: Text(
              '加载失败: $e',
              style: const TextStyle(color: Colors.white54),
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
                      _VideoArea(
                        controller: controller,
                        state: state,
                        channel: channel,
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(
                              Icons.fullscreen,
                              color: Colors.white,
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
                _TopBar(
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
  Widget _buildFullscreenOverlay(BuildContext context) {
    final state = ref.watch(currentPlayerStateProvider);
    final controller = ref.watch(mediaKitVideoControllerProvider);
    final asyncChannels = ref.watch(channelsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: asyncChannels.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          ),
          error: (e, _) => Center(
            child: Text(
              '加载失败: $e',
              style: const TextStyle(color: Colors.white54),
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
                    child: _VideoArea(
                      controller: controller,
                      state: state,
                      channel: channel,
                    ),
                  ),
                ),
                // 控件层: 顶部 + 底部, 统一控制可见性
                Column(
                  children: [
                    _TopBar(
                      channel: channel,
                      state: state,
                      onBack: () => context.pop(),
                    ),
                    const Spacer(),
                    if (channel != null)
                      AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.55),
                          child: Builder(builder: (context) {
                            // Outer if (channel != null) has already
                            // promoted the local channel to non-null for
                            // this subtree (Dart 3 propagates the
                            // promotion into the nested Builder closure
                            // for locals), so we can use it directly here
                            // without re-checking or non-null asserting.
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                NowNextProgram(channel: channel),
                                NextChannelsStrip(
                                  currentChannelId: channel.id,
                                  allChannels: channels,
                                  onChannelTap: _switchTo,
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
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
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                // P2-2: 移动端用户主动全屏时, 给个"退出全屏"按钮 (TV 端没有)
                if (_isFullscreen)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(
                          Icons.fullscreen_exit,
                          color: Colors.white,
                          size: 22,
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
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.channel,
    required this.state,
    required this.onBack,
  });

  final Channel? channel;
  final PlayerState state;
  final VoidCallback onBack;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  late Timer _clockTimer;
  String _clockText = _clockNow();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _clockText = _clockNow());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  static String _clockNow() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = switch (widget.state.status) {
      PlayerStatus.idle => '准备中',
      PlayerStatus.loading => widget.state.attempt == null
          ? '正在尝试源…'
          : '尝试源 ${widget.state.attempt!.index}/${widget.state.attempt!.total}',
      PlayerStatus.playing => 'LIVE',
      PlayerStatus.error => '播放失败',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.channel?.displayName ?? '加载中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IptvTypography.serifTitle
                      .copyWith(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _StatusDot(status: widget.state.status),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _clockText,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
          if (widget.channel != null) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FavoriteIcon(
                channelId: widget.channel!.id,
                channelName: widget.channel!.name,
                size: 24,
                onChanged: (isFav) {
                  // 收藏状态变化不需要额外动作, sqflite 已持久化
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final PlayerStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PlayerStatus.playing => IptvColors.accentTerracotta,
      PlayerStatus.loading => Colors.amber,
      PlayerStatus.error => Colors.redAccent,
      PlayerStatus.idle => Colors.white38,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _VideoArea extends StatelessWidget {
  const _VideoArea({
    required this.controller,
    required this.state,
    required this.channel,
  });

  final VideoController controller;
  final PlayerState state;
  final Channel? channel;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // 6/17 修容器超出: Wrap AspectRatio 16/9 + Stack in ClipRect, 防止在
      // 某些比例 (e.g. 21:9 曲面屏, iPad 分屏) 上 video widget 算出意外高度
      // 溢出顶/底栏.
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频底层 (黑色)
            ColoredBox(color: Colors.black),
            // media_kit Video (播放时)
            if (state.status == PlayerStatus.playing)
              Video(controller: controller),
            // 加载 / 错误 / 空 占位
            switch (state.status) {
              PlayerStatus.idle || PlayerStatus.loading => _LoadingOverlay(
                  text: state.attempt == null
                      ? '正在打开…'
                      : '尝试源 ${state.attempt!.index}/${state.attempt!.total}',
                ),
              PlayerStatus.error =>
                _ErrorOverlay(message: state.error ?? '播放失败'),
              PlayerStatus.playing => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  IptvColors.accentTerracotta,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _ErrorOverlay extends ConsumerWidget {
  const _ErrorOverlay({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 6/17 v0.2.3 P0-4: 错误时给用户「重试 + 换源」按钮.
    // current channel 从 currentPlayerStateProvider 拿.  避免外部多传一个
    // channel 参数导致状态不一致.
    final state = ref.watch(currentPlayerStateProvider);
    final channel = state.channel;
    final hasMultipleSources = (channel?.sources.length ?? 0) > 1;

    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 48,
              ),
              const SizedBox(height: 8),
              const Text(
                '播放失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 16),
              // 重试 + 换源 两个按钮.  重试: 重调 play(当前 channel), 走
              // SourceFailover 自动选源.  换源: 弹底部 sheet, 选单源调
              // playSingleSource.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: channel == null
                        ? null
                        : () {
                            ref.read(playerServiceProvider).play(channel);
                          },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                  if (hasMultipleSources) ...[
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: channel == null
                          ? null
                          : () async {
                              final url = await pickSourceUrl(context, channel);
                              if (url == null) return; // 取消
                              ref
                                  .read(playerServiceProvider)
                                  .playSingleSource(url, channel: channel);
                            },
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('换源'),
                      style: FilledButton.styleFrom(
                        backgroundColor: IptvColors.accentTerracotta,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
