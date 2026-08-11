import 'package:flutter/material.dart';

/// 嵌入布局骨架屏 — 首帧显示: 16:9 黑色视频区 + 顶栏灰条 + 节目卡占位。
class PlayerPageSkeleton extends StatelessWidget {
  const PlayerPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skeletonColor = scheme.surfaceContainerHighest;
    return Column(
      children: [
        const AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(color: Colors.black),
        ),
        Container(
          height: 56,
          color: scheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: skeletonColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
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

/// 全屏覆盖骨架屏 — 平板/TV 走全屏布局时的首帧占位 (黑底 + 中心 spinner)。
class PlayerFullscreenSkeleton extends StatelessWidget {
  const PlayerFullscreenSkeleton({super.key});

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
