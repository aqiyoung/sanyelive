/// 播放页视频区 — media_kit 视频播放 + 加载动画 + 错误 UI.
/// 从 player_page.dart 拆出 (v0.3.6+43).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/models/channel.dart';
import '../../../services/player_service.dart';
import 'source_picker_sheet.dart';

/// 视频区: media_kit + loading/error overlay.
class VideoArea extends StatelessWidget {
  const VideoArea({
    required this.controller,
    required this.state,
    required this.channel,
  });

  final VideoController controller;
  final PlayerState state;
  final Channel? channel;

  @override
  Widget build(BuildContext context) {
    // v0.3.7+61 (6/19): 顶部 SafeArea 让出状态栏空间,  避免视频覆盖状态栏.
    // 之前 ClipRect 直接包 AspectRatio,  状态栏在 edgeToEdge 模式下透明但仍
    // 存在,  视频画面会 "画" 在状态栏背后 = 状态栏区域被视频像素取代,
    // 老板 14:59 反馈 "播放页状态栏还是没修复" (跟 14:34 那次是同一问题).
    // 底部不让 SafeArea 缩进,  接下方的 ChannelNowNext/控制条.
    // v0.3.8+112 (6/20 老板反馈 19:20 "全屏左边白条 5% 屏幕宽 + 上白条"):
    // 之前 SafeArea 默认 left/right 也是 true,  某些 Android 设备 (Mi Pad / 刘海屏)
    // 左边有 cutout / 打孔,  让出 left 130 px ≈ 5% 屏幕宽.  Scaffold.bg = 黑
    // 但 Android 14+ edge-to-edge 强制让透出区显示 theme scaffold bg = 米白,
    //  老板看到 "左边白条".
    // 修法:  SafeArea left:false, right:false — 视频区全宽填满,  状态栏 + 导航栏
    // 颜色走 setSystemUIOverlayStyle (黑色).  top:false — 视频区撑到 status bar 后面,
    // 让 status bar 区域看到视频黑色 (而不是 Android 14+ 强制 edge-to-edge 时显示的
    // theme scaffold bg = 米白).  bottom:false — 接下方的 ChannelNowNext/控制条.
    // v0.3.8+115 (6/20 21:07 老板反馈 "没真正的全屏"):
    // 之前 AspectRatio(16/9) 强制视频 16:9 比例.  老板手机 2670x1200 (2.22:1),
    // 视频 16:9 (1.78:1) 在 1200 高 Stack 里:  height=1200, width=1200*16/9=2133.
    // Stack 宽 2670,  视频 2133,  左右各留 (2670-2133)/2 = 268 px 黑边.
    // 老板看着 "左右黑边" 不像全屏.
    // 修法:  删 AspectRatio(16/9) 让 video widget 自己 fill 父区域 (Stack expand).
    // media_kit Video 加 fit: BoxFit.cover + aspectRatio: 16/9:
    //   - fit: cover = 视频 cover 父区域 (2670x1200),  长边溢出被裁剪
    //   - aspectRatio: 16/9 = 告诉 media_kit 视频源比例,  正确计算 cover 时的居中偏移
    // 视觉:  视频铺满全屏 (2670x1200),  左右裁剪各约 134 px (视频源 16:9 映射到 2.22:1)
    //  — 上下完整,  左右边缘裁掉约 5% 屏幕宽.  用户体验:  看着像真全屏.
    // 注:  BoxFit.fill 会拉伸视频变形 (人脸变扁),  不推荐.  BoxFit.contain
    // 保留比例但有黑边 (老板不要).  BoxFit.cover 保留比例 + 裁剪长边 = 最优.
    return SafeArea(
      top: false,
      bottom: false,
      left: false,
      right: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 视频底层 (黑色) — cover 裁不到的区域补黑
          ColoredBox(color: Colors.black),
          // media_kit Video (播放时) — cover + 16:9 aspect ratio
          if (state.status == PlayerStatus.playing)
            Video(
              controller: controller,
              fit: BoxFit.cover,
              aspectRatio: 16 / 9,
            ),
          // 加载 / 错误 / 空 占位
          switch (state.status) {
            PlayerStatus.idle || PlayerStatus.loading => LoadingOverlay(
                text: state.attempt == null
                    ? '正在打开…'
                    : '尝试源 ${state.attempt!.index}/${state.attempt!.total}',
              ),
            PlayerStatus.error =>
              ErrorOverlay(message: state.error ?? '播放失败'),
            PlayerStatus.playing => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

/// 加载动画 overlay.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.shadow,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 错误 UI + 重试/换源按钮.
class ErrorOverlay extends ConsumerWidget {
  const ErrorOverlay({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 6/17 v0.2.3 P0-4: 错误时给用户「重试 + 换源」按钮.
    // current channel 从 currentPlayerStateProvider 拿.  避免外部多传一个
    // channel 参数导致状态不一致.
    final state = ref.watch(currentPlayerStateProvider);
    final channel = state.channel;
    final hasMultipleSources = (channel?.sources.length ?? 0) > 1;

    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.shadow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: scheme.error,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(
                '播放失败',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
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
                      foregroundColor: scheme.onPrimary,
                      side: BorderSide(color: scheme.outline),
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
                        backgroundColor: scheme.primary,
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
