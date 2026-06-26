/// 播放页视频区 — media_kit 视频播放 + 加载动画 + 错误 UI.
/// 从 player_page.dart 拆出 (v0.3.6+43).
///
/// v0.3.10.11: controller 改 nullable — libmpv 加载失败时 controller 是
/// null, Video widget 不会渲染 (会崩).  显示 "本机播放器不可用" 占位.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/models/channel.dart';
import '../../../services/player_service.dart';
import 'source_picker_sheet.dart';

/// 视频区: media_kit + loading/error overlay.
class VideoArea extends StatelessWidget {
  const VideoArea({super.key, 
    required this.controller,
    required this.state,
    required this.channel,
  });

  // v0.3.10.11: libmpv 加载失败时 controller 为 null.
  final VideoController? controller;
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
    // v0.3.8+120 (6/20 23:27 老板反馈 "全屏后视频超出屏幕了"):
    // 之前 +115 用 BoxFit.cover + aspectRatio 16/9 — 在 2.22:1 横屏下视频 cover,
    //  左右裁剪各 ~5%.  老板看着 "视频超出屏幕" (实际是 cover 裁剪行为).
    // 修法:  用 LayoutBuilder 根据屏幕宽高比动态选 fit:
    //   - 横屏 (width/height > 1,  比如 2.22:1):  BoxFit.cover (保留比例 + 裁剪长边,
    //     看着像真全屏,  跟之前一致 — 老板在横屏是接受 cover 的)
    //   - 竖屏 (width/height < 1,  比如 9:16):  BoxFit.contain (保留视频完整 + 上下
    //     或左右黑边,  老板在嵌入布局 portrait 不接受裁剪)
    // 视觉效果:
    //   - 横屏全屏:  跟 +115 一样,  cover + 裁剪
    //   - 竖屏嵌入:  视频完整居中,  黑边补足 (左右/上下)
    //   - 老板竖屏看嵌入布局的 9:16 屏幕时不再觉得"超出"
    // v0.3.8+122 (6/21 老板反馈 05:45 "全屏后视频超出边框 保持模式"):
    // 之前 +120 在全屏态走 BoxFit.cover — 视频 cover 父区域,  2.22:1 横屏 (老板
    // 手机 2670x1200) 把 16:9 视频源长边溢出裁掉 ~5%,  老板看着 "视频超出屏幕了".
    // "保持模式" = BoxFit.contain:  保留视频原始比例 + 黑边填充不裁剪.
    // 修法:  统一 BoxFit.contain (不再 LayoutBuilder 动态判断),  全屏永远
    // 视频完整居中 + 上下/左右黑边补足.  视频人脸不变形,  画面完整,  老板
    //  看着 "视频没超出屏幕".
    // 视觉:
    //   - 横屏全屏 (2.22:1):  视频 16:9 完整居中,  上下各 ~63 px 黑边
    //   - 竖屏嵌入 (9:16):   视频 16:9 完整居中,  上下黑边补足
    //   - 不再裁切任何视频像素.  永远 contain.
    return SafeArea(
      top: false,
      bottom: false,
      left: false,
      right: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 视频底层 (黑色 + 居中 contain)
          ColoredBox(
            color: Colors.black,
            child: Center(
              // v0.3.10.11: controller == null (libmpv 加载失败) 时不渲染
              // Video widget — 它会崩.  改为 SizedBox.shrink + 让
              // ErrorOverlay 在上层显示 "本机播放器不可用" 信息.
              // v0.3.10.22: 平板/TV 修复 — LayoutBuilder 检测父容器尺寸,
              // 在 tablet (shortestSide >= 600) 时 fallback 到 BoxFit.cover
              // 确保视频铺满可用空间; 手机保持 BoxFit.contain.
              // SizedBox.expand 确保 Video widget 有正确的布局约束.
              child:
                  (state.status == PlayerStatus.playing && controller != null)
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final screenSize = MediaQuery.of(context).size;
                            final isTablet = screenSize.shortestSide >= 600;
                            // 平板/TV: 使用 cover 确保视频铺满屏幕
                            // 手机: 使用 contain 保持视频完整可见
                            final fit = isTablet ? BoxFit.cover : BoxFit.contain;
                            // v0.3.10.22: ValueKey(channel.id) 强制
                          // Video widget 在切台时全新重建 — 防止 media_kit
                          // 复用旧 State 导致 surface 尺寸=0 (平板黑屏).
                          return SizedBox.expand(
                              child: Video(
                                key: ValueKey(channel?.id ?? 'no-channel'),
                                controller: controller!,
                                fit: fit,
                                aspectRatio: 16 / 9,
                              ),
                            );
                          },
                        )
                      : const SizedBox.shrink(),
            ),
          ),
          // 加载 / 错误 / 空 占位 (覆盖在视频上方)
          switch (state.status) {
            PlayerStatus.idle || PlayerStatus.loading => LoadingOverlay(
                text: state.attempt == null
                    ? '正在打开…'
                    : '尝试源 ${state.attempt!.index}/${state.attempt!.total}',
              ),
            PlayerStatus.error => ErrorOverlay(message: state.error ?? '播放失败'),
            PlayerStatus.playing => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

/// 加载动画 overlay.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.text});
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
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
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
  const ErrorOverlay({super.key, required this.message});
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
