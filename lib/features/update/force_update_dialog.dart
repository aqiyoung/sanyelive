//
// 设计要点:
//   - barrierDismissible: false  → 用户无法通过点击外部 / 返回键关闭.
//   - 结构参考 FeiNiuMusic 的 app_update_dialog.dart: 满幅渐变头部
//     (primary→tertiary) + 火箭图标 + 标题 + releaseName, 下方「当前→最新」
//     版本 chip + 可滚动变更日志.  外壳仍用 sanyelive 的液态玻璃面板
//     (LiquidGlassContainer), 保持全 app 一致的玻璃质感.
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
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sanyelive/services/version_checker.dart';
import 'package:sanyelive/widgets/liquid_glass_container.dart';

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

  /// 复制指定链接到剪贴板并弹 toast.  url 由调用方决定 (官方 release 页 或
  /// 代理 APK 直链).  对齐飞牛音乐: 复制而非自动下载, 避开 TV 自动下 APK 权限坑.
  Future<void> _copyLink(
    BuildContext context,
    String url,
    String toastMsg,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toastMsg), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint('复制链接失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // barrierDismissible: false 只阻止点击外部,  不阻止返回键.
    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: LiquidGlassContainer(
          variant: isDark ? LiquidGlassVariant.dark : LiquidGlassVariant.light,
          borderRadius: 24,
          margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          // padding 设 0: 头部满幅铺到卡片上沿 (外层 ClipRRect 自动把上角收圆),
          // 下方内容区单独用 Padding 留白.
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 渐变头部 (参考 FeiNiuMusic: primary→tertiary + 火箭图标) ──
              Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        s.isCritical ? Icons.priority_high : Icons.rocket_launch_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.isCritical ? '重要更新' : '发现新版本',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (s.releaseName.isNotEmpty &&
                              s.releaseName != s.latestVersion) ...[
                            const SizedBox(height: 2),
                            Text(
                              s.releaseName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── 内容区 (单独留白) ──
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 版本 chip: 当前 → 最新 (参考 FeiNiuMusic 的 _VersionChip)
                    Row(
                      children: [
                        _VersionChip(label: s.currentVersion, dim: true),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        _VersionChip(label: s.latestVersion, dim: false),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.maxFinite,
                      constraints: const BoxConstraints(maxHeight: 240),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          s.releaseNotes.isEmpty ? '(无变更日志)' : s.releaseNotes,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '「复制下载链接」复制官方 Release 页 (跟飞牛一致); '
                      '国内 TV 直连下不动时, 用「代理下载」复制 gh-proxy APK 直链',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: _buildActions(s, theme),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

    // 次要: 去浏览器打开 GitHub 官方 releases 页 (手动挑架构下载).
    actions.add(
      TextButton(
        onPressed: () => _openGitHub(context, s.latestVersion),
        child: const Text('去浏览器下载'),
      ),
    );

    // 代理直链: 复制带 gh-proxy 前缀的 APK 文件直链 (国内 TV 可直下).
    actions.add(
      TextButton(
        onPressed: () => _copyLink(
          context,
          s.apkDownloadUrl,
          '已复制代理 APK 直链（国内可直下），粘贴到浏览器下载',
        ),
        child: const Text('代理下载'),
      ),
    );

    // 主操作: 复制官方 GitHub Release 页链接 (对齐飞牛音乐, 链接永不失效).
    actions.add(
      FilledButton(
        onPressed: () => _copyLink(
          context,
          _buildReleasesUrl(s.latestVersion),
          '已复制官方下载页链接，粘贴到浏览器打开',
        ),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        child: const Text('复制下载链接'),
      ),
    );

    return actions;
  }
}

/// 版本 chip — 当前版本(暗)/最新版本(高亮) 两个药丸.  参考 FeiNiuMusic.
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
            : scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: dim
            ? null
            : Border.all(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: dim ? scheme.onSurfaceVariant : scheme.primary,
        ),
      ),
    );
  }
}
