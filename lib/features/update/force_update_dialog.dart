//
// 设计要点:
//   - barrierDismissible: false  → 用户无法通过点击外部 / 返回键关闭.
//   - 内容: 大标题 (新版本号) + 副标题 (当前版本 → 新版本) +
//     变更日志 (release body) + 2 按钮 "去下载"(主) + "稍后"(次, 24h 内不弹).
//   - P0/critical: release body 含 "**P0**" / "**critical**" 标记时,  dialog
//     不显示"稍后"按钮,  必须更新.  维持安全门.
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sanyelive/services/version_checker.dart';

/// 公开入口:  main.dart 在 VersionCheckOutdated 时调.
/// 用 ProviderScope.containerOf(context) 拿 ref,  避免外部传 ref.
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

  /// 构建 GitHub releases 页面 URL.
  String _buildReleasesUrl(String tagName) {
    return 'https://github.com/aqiyoung/sanyelive/releases/tag/$tagName';
  }

  Future<void> _openGitHub(BuildContext context, String tagName) async {
    setState(() => _launching = true);
    try {
      final url = Uri.parse(_buildReleasesUrl(tagName));
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开浏览器, 请手动访问 GitHub')),
          );
        }
      }
    } catch (e) {
      debugPrint('打开 GitHub 失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;
    final titleColor =
        isDark ? theme.colorScheme.onSurface : theme.colorScheme.onSurface;
    final bodyColor = isDark
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurfaceVariant;

    // barrierDismissible: false 只阻止点击外部,  不阻止返回键.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: dialogBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        title: Row(
          children: [
            Icon(
              s.isCritical ? Icons.priority_high : Icons.system_update_alt,
              color: s.isCritical
                  ? Colors.red.shade700
                  : theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.isCritical ? '重要更新' : '发现新版本',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.currentVersion} → ${s.latestVersion}',
                style: TextStyle(
                  fontSize: 15,
                  color: bodyColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s.releaseNotes.isEmpty ? '(无变更日志)' : s.releaseNotes,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: bodyColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '点击"去下载"将跳转 GitHub 下载最新 APK',
                style: TextStyle(
                  fontSize: 12,
                  color: bodyColor.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: _buildActions(s, theme),
      ),
    );
  }

  List<Widget> _buildActions(VersionCheckOutdated s, ThemeData theme) {
    if (_launching) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ];
    }

    final actions = <Widget>[];

    // P0/critical: 不显示"稍后"按钮.  强制更新.
    if (!s.isCritical) {
      actions.add(
        TextButton(
          onPressed: () async {
            // 使用 context 触发 use_build_context_synchronously lint.
            final navigator = Navigator.of(context);
            await ref.read(versionCheckerProvider.notifier).markDismissed();
            if (mounted) navigator.pop();
          },
          child: const Text('稍后'),
        ),
      );
    }

    actions.add(
      FilledButton(
        onPressed: () => _openGitHub(context, s.latestVersion),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        child: const Text('去下载'),
      ),
    );

    return actions;
  }
}
