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

/// 播放页 — 卡 5 实现
///   - 顶部: 返回 + 频道名 + 节目时间
///   - 中部: media_kit 视频区 (16:9)
///   - 底部: 当前/下一档节目卡 (NowNextProgram)
///   - 底部: 下一频道横滑条 (NextChannelsStrip)
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late Future<List<Channel>> _channelsFuture;

  @override
  void initState() {
    super.initState();
    // 卡 6: 进入播放页 → 沉浸式状态栏 (隐藏状态栏 + 导航栏, 拉上去才出)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 卡 7 (6/17 老板需求): 播放页背景黑, 如果状态栏没隐藏 (拉下来时) 也要
    // 保证白字可见.  退出时 dispose 还原.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,  // 白图标
        statusBarBrightness: Brightness.dark,       // iOS: 暗背景 -> 白文字
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _channelsFuture = ref.read(channelRepositoryProvider).loadBundled();
    // 进入页面时尝试播放
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoPlay());
  }

  @override
  void dispose() {
    // 卡 6: 退出播放页 → 还原状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 卡 7: 还原成全 APP 默认 (黑图标, 跟浅米色页面配套)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    super.dispose();
  }

  Future<void> _tryAutoPlay() async {
    final channels = await _channelsFuture;
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
    } catch (_) {
      // 测试环境 / dispose 窗口期: 吞掉异常, 不影响测试
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
    final state = ref.watch(currentPlayerStateProvider);
    final controller = ref.watch(mediaKitVideoControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FutureBuilder<List<Channel>>(
          future: _channelsFuture,
          builder: (context, snap) {
            final channel = snap.data == null
                ? null
                : _findChannel(snap.data!, widget.channelId);
            return Column(
              children: [
                _TopBar(
                  channel: channel,
                  state: state,
                  onBack: () => context.pop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _VideoArea(
                          controller: controller,
                          state: state,
                          channel: channel,
                        ),
                        const SizedBox(height: 12),
                        if (channel != null) NowNextProgram(channel: channel),
                        if (snap.data != null && channel != null)
                          NextChannelsStrip(
                            currentChannelId: channel.id,
                            allChannels: snap.data!,
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
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.channel,
    required this.state,
    required this.onBack,
  });

  final Channel? channel;
  final PlayerState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final statusText = switch (state.status) {
      PlayerStatus.idle => '准备中',
      PlayerStatus.loading => state.attempt == null
          ? '正在尝试源…'
          : '尝试源 ${state.attempt!.index}/${state.attempt!.total}',
      PlayerStatus.playing => 'LIVE',
      PlayerStatus.error => '播放失败',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel?.name ?? '加载中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IptvTypography.serifTitle
                      .copyWith(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _StatusDot(status: state.status),
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
                      _clockNow(),
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
          if (channel != null) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FavoriteIcon(
                channelId: channel!.id,
                channelName: channel!.name,
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

  String _clockNow() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
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
    return AspectRatio(
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
            PlayerStatus.error => _ErrorOverlay(message: state.error ?? '播放失败'),
            PlayerStatus.playing => const SizedBox.shrink(),
          },
        ],
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

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
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
            ],
          ),
        ),
      ),
    );
  }
}
