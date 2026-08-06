/// 播放页顶栏 — 返回 + 频道名 + 状态 + 时钟.
///
///   之前 TopBar 有 4 个 IconButton — ← 返回 + ⋮ + ♡ + 退出全屏.
///   修法: 删 Icons.more_vert + FavoriteIcon + onExitFullscreen IconButton.
///   退出全屏靠 Android back (系统行为) + TopBar ← 返回按钮 (全屏态调
///   _toggleFullscreen,  嵌入布局调 context.pop — 走 _onTopBarBack).
///
///   嵌入布局背景是 scheme.surface (浅米色),  白字看不清.
///   加 isFullscreen prop: true=白字 (黑底), false=深棕 (浅米色).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/typography.dart';
import '../../../data/models/channel.dart';
import '../../../services/player_service.dart';

/// 播放页顶栏 — 返回 + 频道名 + 状态 + 时钟.
class TopBar extends StatefulWidget {
  const TopBar({super.key, 
    required this.channel,
    required this.state,
    required this.onBack,
    this.isFullscreen = false,
  });

  final Channel? channel;
  final PlayerState state;
  final VoidCallback onBack;

  /// 是否全屏布局.
  final bool isFullscreen;

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
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

    // - 嵌入布局 (scheme.surface 浅米色): 深棕字 (本次修)
    final scheme = Theme.of(context).colorScheme;
    final titleColor = widget.isFullscreen ? Colors.white : scheme.onSurface;
    final subColor =
        widget.isFullscreen ? Colors.white70 : scheme.onSurfaceVariant;
    final iconColor = widget.isFullscreen ? Colors.white : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // 之前 TopBar 还有 ⋮ (Icons.more_vert) + ♡ (FavoriteIcon)
          // 全删.  退出全屏靠 _onTopBarBack (全屏态) / context.pop (嵌入布局)
          IconButton(
            icon: Icon(Icons.arrow_back, color: iconColor),
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
                      .copyWith(color: titleColor, fontSize: 18),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _StatusDot(status: widget.state.status),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _clockText,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      PlayerStatus.playing => scheme.primary,
      PlayerStatus.loading => scheme.primary.withValues(alpha: 0.7),
      PlayerStatus.error => scheme.error,
      PlayerStatus.idle => scheme.onSurfaceVariant.withValues(alpha: 0.38),
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
