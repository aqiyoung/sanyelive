// 0.3.7+20 后台强制更新弹窗 (P1 feature, 6/18 老板拍板).
// 0.3.10+20: 改为跳转 GitHub releases 页下载, 不再 Dio 下载 APK + 调系统安装器.
//
// 设计要点:
//   - barrierDismissible: false  → 用户无法通过点击外部 / 返回键关闭.
//   - 内容: 大标题 (新版本号) + 副标题 (当前版本 → 新版本) +
//     变更日志 (release body) + 2 按钮 "去下载"(主) + "稍后"(次, 24h 内不弹).
//   - P0/critical: release body 含 "**P0**" / "**critical**" 标记时,  dialog
//     不显示"稍后"按钮,  必须更新.  维持安全门.
//   - 视觉: 沿用 v0.3.6+19 暗色主题 token,  弹窗在 light / dark 都好看.
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

  /// 构建 GitHub releases 页面 URL (fallback).
  String _buildReleasesUrl(String tagName) {
    return 'https://github.com/aqiyoung/iptv-app/releases/tag/$tagName';
  }

  Future<void> _openGitHub(BuildContext context, VersionCheckOutdated state) async {
    setState(() => _launching = true);
    // v0.3.10.22: 在 async gap 之前 capture ScaffoldMessenger 引用,
    // 避免 use_build_context_synchronously lint 警告.
    final messenger = ScaffoldMessenger.of(context);
    try {
      // v0.3.10.22: 优先用 apkDownloadUrl 直链下载,  失败 fallback 到 releases 页面.
      // apkDownloadUrl 已经是 browser_download_url (如 sanyelive-v0.3.10.20-arm64-v8a.apk),
      // 直接下载 APK,  避免用户还要在 releases 页面找哪个文件.
      final urlsToTry = <String>[
        state.apkDownloadUrl, // 优先: APK 直链
        _buildReleasesUrl(state.latestVersion), // fallback: releases 页面
      ];
      bool launched = false;
      for (final url in urlsToTry) {
        try {
          final uri = Uri.parse(url);
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            launched = true;
            break;
          }
        } catch (e) {
          debugPrint('打开 $url 失败: $e');
        }
      }
      if (!launched && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('无法打开浏览器, 请手动访问 GitHub')),
        );
      }
    } catch (e) {
      debugPrint('打开 GitHub 失败: $e');
      if (mounted) {
        messenger.showSnackBar(
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

    // v0.3.8+169: PopScope(canPop: false) 阻止 Android 返回键关闭弹窗.
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
                  // v0.3.10.22: withValues 替代 withOpacity (deprecated)
                color: bodyColor.withValues(alpha: 0.6), // v0.3.10.22: withValues (withOpacity deprecated)
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
            // v0.3.10.22: 先 capture navigator, 避免 async gap 后
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
        onPressed: () => _openGitHub(context, s),
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
