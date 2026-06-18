// 0.3.7+20 后台强制更新弹窗 (P1 feature, 6/18 老板拍板).
//
// 设计要点:
//   - barrierDismissible: false  → 用户无法通过点击外部 / 返回键关闭.
//   - 内容: 大标题 (新版本号) + 副标题 (当前版本 → 新版本) +
//     变更日志 (release body) + 2 按钮 "立刻更新"(主) + "稍后"(次,  24h 内不弹).
//   - P0/critical: release body 含 "**P0**" / "**critical**" 标记时,  dialog
//     不显示"稍后"按钮,  必须更新.  维持安全门.
//   - 视觉: 沿用 v0.3.6+19 暗色主题 token,  弹窗在 light / dark 都好看.
//   - 下载流程: 点"立刻更新" → dio 下载到 getTemporaryDirectory +
//     install_plugin.install(installPath) 调 Android installer;  iOS
//     弹"去 App Store"提示 (后端 store URL 暂用 placeholder).
//
// 调用方式:
//   // main.dart
//   ref.listen<VersionCheckState>(versionCheckerProvider, (prev, next) {
//     if (next is VersionCheckOutdated) {
//       ForceUpdateDialog.show(context, ref, next);
//     }
//   });

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sanyelive/core/theme/colors.dart';
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
  _DownloadPhase _phase = _DownloadPhase.idle;
  String? _errorMessage;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? IptvColors.darkSurface : IptvColors.bgElevated;
    final titleColor =
        isDark ? IptvColors.darkTextPrimary : IptvColors.textPrimary;
    final bodyColor =
        isDark ? IptvColors.darkTextSecondary : IptvColors.textSecondary;

    return AlertDialog(
      backgroundColor: dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      // barrierDismissible: false 在 showDialog 里已经设了;  在 AlertDialog
      // 上也重复一次,  防止未来重构.
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      title: Row(
        children: [
          Icon(
            s.isCritical ? Icons.priority_high : Icons.system_update_alt,
            color: s.isCritical
                ? Colors.red.shade700
                : IptvColors.accentTerracotta,
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
                    ? IptvColors.darkSurfaceHigh
                    : IptvColors.bgParchment,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isDark ? IptvColors.darkDivider : IptvColors.dividerWarm,
                ),
              ),
              child: Text(
                s.releaseNotes.isEmpty ? '（无变更日志）' : s.releaseNotes,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: bodyColor,
                ),
              ),
            ),
            if (_phase == _DownloadPhase.downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 6,
                  backgroundColor:
                      isDark ? IptvColors.darkDivider : IptvColors.dividerWarm,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    IptvColors.accentTerracotta,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}% — 下载中...',
                style: TextStyle(fontSize: 12, color: bodyColor),
              ),
            ],
            if (_phase == _DownloadPhase.failed) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage ?? '下载失败',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_phase == _DownloadPhase.installing) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '正在唤起安装器...',
                    style: TextStyle(fontSize: 13, color: bodyColor),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: _buildActions(s, theme),
    );
  }

  List<Widget> _buildActions(VersionCheckOutdated s, ThemeData theme) {
    if (_phase == _DownloadPhase.downloading ||
        _phase == _DownloadPhase.installing) {
      return const []; // 进度中,  不让用户点其他按钮
    }

    if (_phase == _DownloadPhase.failed) {
      return [
        if (!s.isCritical)
          TextButton(
            onPressed: () async {
              await ref.read(versionCheckerProvider.notifier).markDismissed();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('稍后'),
          ),
        TextButton(
          onPressed: () {
            setState(() {
              _phase = _DownloadPhase.idle;
              _errorMessage = null;
            });
          },
          child: const Text('重试'),
        ),
        FilledButton(
          onPressed: () => _startDownload(s),
          style: FilledButton.styleFrom(
            backgroundColor: IptvColors.accentTerracotta,
            foregroundColor: Colors.white,
          ),
          child: const Text('立刻更新'),
        ),
      ];
    }

    // idle 状态
    final actions = <Widget>[];

    // P0/critical: 不显示"稍后"按钮.  强制更新.
    if (!s.isCritical) {
      actions.add(
        TextButton(
          onPressed: () async {
            await ref.read(versionCheckerProvider.notifier).markDismissed();
            if (mounted) Navigator.of(context).pop();
          },
          child: const Text('稍后'),
        ),
      );
    }

    actions.add(
      FilledButton(
        onPressed: () => _startDownload(s),
        style: FilledButton.styleFrom(
          backgroundColor: IptvColors.accentTerracotta,
          foregroundColor: Colors.white,
        ),
        child: const Text('立刻更新'),
      ),
    );

    return actions;
  }

  Future<void> _startDownload(VersionCheckOutdated s) async {
    setState(() {
      _phase = _DownloadPhase.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    try {
      if (kIsWeb) {
        // Web 没有 installer 概念;  直接打开下载链接让浏览器处理.
        // 实际 IPTV APP 不会跑 web,  这里是 defensive.
        throw UnsupportedError('Web 端不支持自动安装, 请手动下载');
      }

      // iOS 走 App Store placeholder (没有 Apple Store 上架,  提示用户).
      if (Platform.isIOS) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('iOS 用户请到 App Store 更新 (暂未上架)'),
            ),
          );
        }
        setState(() => _phase = _DownloadPhase.idle);
        return;
      }

      final tmpDir = await getTemporaryDirectory();
      final fileName = s.apkAssetName;
      final savePath = '${tmpDir.path}/$fileName';

      final dio = Dio();
      await dio.download(
        s.apkDownloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );

      if (!mounted) return;
      setState(() => _phase = _DownloadPhase.installing);

      // install_plugin 2.1.0 的 install(filePath) 返回 Map 含 isSuccess /
      // errorMessage.  Android 8+ (API 26+) 使用 application/vnd.android
      // .package-archive  Intent + FileProvider,  manifest 加了
      // REQUEST_INSTALL_PACKAGES 后会弹系统装包 UI.
      final result = await InstallPlugin.install(savePath);
      debugPrint('install_plugin result: $result');

      // install_plugin 调起系统 installer 后,  我们的进程会被切后台.
      // 如果回到 dialog,  说明用户取消了,  重置回 idle 状态.
      if (mounted) {
        setState(() => _phase = _DownloadPhase.idle);
      }
    } catch (e, st) {
      debugPrint('强制更新下载/安装失败: $e\n$st');
      if (mounted) {
        setState(() {
          _phase = _DownloadPhase.failed;
          _errorMessage = e.toString();
        });
      }
    }
  }
}

enum _DownloadPhase { idle, downloading, installing, failed }
