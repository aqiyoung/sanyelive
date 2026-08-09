//
// 设计要点:
//   - barrierDismissible: false → 用户无法通过点击外部 / 返回键关闭.
//   - 视觉去红: 不再使用品牌赤陶红作为头部/按钮主色, 改用青玉 teal 作为更新
//     流程专用强调色, 整体更干净、不刺眼.
//   - 结构: 顶部圆形图标 + 标题 + 版本对比 chips + 可滚动变更日志 + 底部操作.
//     去掉满幅渐变Header, 改为与内容区一体的玻璃卡片, 信息层级更清晰.
//   - P0/critical: release body 含 "**P0**" / "**critical**" 标记时, dialog
//     不显示"稍后"按钮, 必须更新. 维持安全门.
//   - 下载流程: 点"去下载" → url_launcher 打开 GitHub releases 页, 用户手动下载 APK.
//
// 调用方式:
//   // main.dart
//   ref.listen<VersionCheckState>(versionCheckerProvider, (prev, next) {
//     if (next is VersionCheckOutdated) {
//       ForceUpdateDialog.show(context, ref, next);
//     }
//   });

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sanyelive/services/version_checker.dart';
import 'package:sanyelive/widgets/liquid_glass_container.dart';

/// 更新流程专用强调色 — 青玉 teal, 与设置页「检查更新」弹窗保持一致.
const Color _kUpdateAccent = Color(0xFF2A9D8F);
const Color _kUpdateAccentContainer = Color(0xFFE6F4F2);

/// 公开入口: main.dart 在 VersionCheckOutdated 时调.
/// 用 ProviderScope.containerOf(context) 拿 ref, 避免外部传 ref.
class ForceUpdateDialog {
  static Future<void> show(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    final state = container.read(versionCheckerProvider);
    if (state is! VersionCheckOutdated) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // 不可点外部 / 返回键关闭
      useRootNavigator: true, // 路由栈里其他页面 (player / settings) 不会盖住
      builder: (ctx) => _ForceUpdateDialogContent(state: state),
    );
  }
}

class _ForceUpdateDialogContent extends ConsumerStatefulWidget {
  const _ForceUpdateDialogContent({required this.state});
  final VersionCheckOutdated state;

  @override
  ConsumerState<_ForceUpdateDialogContent> createState() =>
      _ForceUpdateDialogContentState();
}

class _ForceUpdateDialogContentState
    extends ConsumerState<_ForceUpdateDialogContent> {
  bool _launching = false;

  /// 构建 GitHub releases 页面 URL (直接跳转 GitHub).
  String _buildReleasesUrl(String tagName) {
    return 'https://github.com/aqiyoung/sanyelive/releases/tag/$tagName';
  }

  /// 构建 gh-proxy 代理跳转的 releases 页面 URL (国内/电视用户直连 GitHub
  /// 失败时兜底). 与 version_checker 的 _kGitHubProxyPrefixes 首选项一致.
  String _buildProxyReleasesUrl(String tagName) {
    return 'https://gh-proxy.com/https://github.com/aqiyoung/sanyelive/releases/tag/$tagName';
  }

  /// 唤起外部浏览器打开链接; 打不开则复制链接并提示 (对齐飞牛音乐 _openUrl).
  Future<void> _openUrl(BuildContext context, String url) async {
    setState(() => _launching = true);
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开浏览器, 下载链接已复制到剪贴板')),
          );
        }
      }
    } catch (e) {
      debugPrint('打开链接失败: $e');
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开浏览器, 下载链接已复制到剪贴板')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: LiquidGlassContainer(
          variant: isDark ? LiquidGlassVariant.dark : LiquidGlassVariant.light,
          borderRadius: 24,
          margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 顶部图标 + 标题 ──
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _kUpdateAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      s.isCritical ? Icons.priority_high_rounded : Icons.rocket_launch_outlined,
                      color: _kUpdateAccent,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.isCritical ? '重要更新' : '发现新版本',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (s.releaseName.isNotEmpty &&
                      s.releaseName != s.latestVersion) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.releaseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              // ── 版本对比 chips ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _VersionChip(label: s.currentVersion, dim: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  _VersionChip(label: s.latestVersion, dim: false),
                ],
              ),
              const SizedBox(height: 16),
              // ── 变更日志 ──
              Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 240),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  child: _ReleaseNotesText(notes: s.releaseNotes),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '「前往下载」跳转 GitHub Release 页；若访问不畅，可用「代理下载」',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              // ── 操作区 ──
              _buildActions(s, scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(VersionCheckOutdated s, ColorScheme scheme) {
    if (_launching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final actions = <Widget>[];

    // P0/critical: 不显示"稍后"按钮. 强制更新.
    if (!s.isCritical) {
      actions.add(
        Expanded(
          child: OutlinedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(versionCheckerProvider.notifier).markDismissed();
              if (mounted) navigator.pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('稍后'),
          ),
        ),
      );
      actions.add(const SizedBox(width: 10));
    }

    // 代理下载
    actions.add(
      Expanded(
        child: OutlinedButton(
          onPressed: () => _openUrl(context, _buildProxyReleasesUrl(s.latestVersion)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kUpdateAccent,
            side: BorderSide(color: _kUpdateAccent.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: const Text('代理下载'),
        ),
      ),
    );

    actions.add(const SizedBox(width: 10));

    // 主操作: 前往下载
    actions.add(
      Expanded(
        child: FilledButton.icon(
          onPressed: () => _openUrl(context, _buildReleasesUrl(s.latestVersion)),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('前往下载'),
          style: FilledButton.styleFrom(
            backgroundColor: _kUpdateAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: actions,
    );
  }
}

/// 版本 chip — 当前版本(暗)/最新版本(高亮) 两个药丸.
class _VersionChip extends StatelessWidget {
  final String label;
  final bool dim;

  const _VersionChip({required this.label, required this.dim});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dim
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : _kUpdateAccentContainer,
        borderRadius: BorderRadius.circular(999),
        border: dim ? null : Border.all(color: _kUpdateAccent.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: dim ? scheme.onSurfaceVariant : _kUpdateAccent,
        ),
      ),
    );
  }
}

/// 简单渲染 release notes: Markdown 标题/列表基础高亮.
class _ReleaseNotesText extends StatelessWidget {
  const _ReleaseNotesText({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (notes.isEmpty) {
      return Text(
        '(无变更日志)',
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.6),
      );
    }

    final spans = <TextSpan>[];
    final lines = notes.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }

      if (line.startsWith('### ')) {
        spans.add(TextSpan(
          text: '${line.substring(4)}\n',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            height: 1.6,
          ),
        ));
      } else if (line.startsWith('## ')) {
        spans.add(TextSpan(
          text: '${line.substring(3)}\n',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _kUpdateAccent,
            height: 1.6,
          ),
        ));
      } else {
        var content = line;
        if (content.startsWith('- ')) content = content.substring(2);
        if (content.startsWith('* ')) content = content.substring(2);
        spans.add(TextSpan(
          text: '• $content\n',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurfaceVariant,
            height: 1.6,
          ),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}
