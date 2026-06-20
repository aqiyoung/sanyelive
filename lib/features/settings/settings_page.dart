// 0.3.6+19 设置页.
//
// 一个 ListTile "主题" → 弹出 RadioListTile 选 系统 / 浅色 / 深色.
// 复用 theme_provider, 切换后立即持久化 (SharedPreferences),
// main.dart 的 ConsumerWidget 监听 themeModeProvider 同步给 MaterialApp.themeMode.
//
// v0.3.7+80 (6/19): 加 2 个 tile — "检查更新" + "关于三页直播".
//  关于: 描述项目 + 贴 GitHub 地址 + 一键复制按钮.  不用 url_launcher 包
//  (省 1MB + Android query intent 配置),  复制 URL 让老板自己粘贴到浏览器看.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// v0.3.7.2 (6/19): 不再 import main.dart (主 dart 写死 const 没用),  用 Provider 读运行时版本号.
import '../../services/version_checker.dart' show currentVersionStringProvider, currentVersionCodeProvider, versionCheckerProvider, VersionCheckState, VersionCheckUpToDate, VersionCheckOutdated, VersionCheckFailed, endpointProvider, kDefaultEndpointUrl;
import '../update/force_update_dialog.dart' show ForceUpdateDialog;
import 'theme_provider.dart';

// v0.3.8+93 (6/20 P1-1): settings_page 所有 IptvColors 颜色 (textPrimary
//   / textSecondary) 都改走 colorScheme.onSurface / onSurfaceVariant,  跟
//   暗色主题联动.  之前 hardcode 浅米色文字在暗背景下看不清.  不再 import
//   IptvColors — 全部跟主题走.

// v0.3.7+80 (6/19): GitHub 项目地址常量.  复制到剪贴板用.
const String kGitHubRepoUrl = 'https://github.com/aqiyoung/iptv-app';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // ─── 主题 ─────────────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(_modeLabel(mode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context, ref, current: mode),
          ),
          const _ThinDivider(),
          // ─── 检查更新 ─────────────────────────────────────────────────────
          // v0.3.7+80: 手动触发 versionCheckerProvider.notifier.checkOnStartup().
          // 逻辑跟启动时一样: 1h 内 cache 命中跳过,  否则 fetch GitHub API.
          // state 变化显示 SnackBar (upToDate / outdated / failed).
          ListTile(
            leading: const Icon(Icons.system_update_alt_outlined),
            title: const Text('检查更新'),
            subtitle: const Text(
              '当前版本 + 最新版本对比',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _checkUpdate(context, ref),
          ),
          const _ThinDivider(),
          // ─── 更新源 ──────────────────────────────────────────────────────
          // v0.3.7+92 (6/20 08:42 老板反馈): 默认 endpoint 改为 gh-proxy.com
          //   (代理 api.github.com),  国内 600ms 响应.  老板还是能在设置页手动改
          //   (重置默认 / 填别的代理 / 填自建镜像).
          // version_checker 用 endpointProvider 而不是 const kGitHubReleasesUrl.
          Consumer(
            builder: (context, ref, _) {
              final endpoint = ref.watch(endpointProvider);
              final isDefault = endpoint == kDefaultEndpointUrl;
              return ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('更新源'),
                subtitle: Text(
                  isDefault ? '默认 (gh-proxy.com 代理 api.github.com)' : endpoint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editEndpoint(context, ref),
              );
            },
          ),
          const _ThinDivider(),
          // ─── 关于三页直播 ─────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于三页直播'),
            subtitle: const Text(
              '项目介绍 + GitHub 地址',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAbout(context),
          ),
          const _ThinDivider(),
          // ─── 版本号 (静态展示,  从 Provider 读) ───────────────────────────
          Consumer(
            builder: (context, ref, _) {
              final version = ref.watch(currentVersionStringProvider);
              final code = ref.watch(currentVersionCodeProvider);
              return ListTile(
                leading: const Icon(Icons.tag_outlined),
                title: const Text('版本号'),
                subtitle: Text(
                  '$version (build $code)',
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // ─── 底部 footer (slogan,  跟 about 区分) ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              '三页直播 · 极简新中式 IPTV',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 关于对话框 ───────────────────────────────────────────────────────────
  // v0.3.7+80: 弹一个 dialog,  描述项目 (基于 Flutter + media_kit 视频播放,
  // 极简新中式设计,  IPTV 直播).  底部贴 GitHub 地址 + 复制按钮.
  void _showAbout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于三页直播'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '三页直播是一款 IPTV 直播 APP, 面向家用电视 / 盒子 / 手机, 极简新中式设计。',
                style: TextStyle(color: scheme.onSurface, height: 1.6),
              ),
              const SizedBox(height: 16),
              _AboutSection(
                label: '技术栈',
                child: Text(
                  'Flutter (Dart) · media_kit (libmpv 内核) · Riverpod · GoRouter · '
                  'GitHub Actions CI/CD · 自动源维护 (iptv-org 上游)。',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
              _AboutSection(
                label: '特性',
                child: Text(
                  '· 强制 IPv4 (修 wifi 加载不出来)\n'
                  '· Source Failover 自动切源\n'
                  '· 全屏沉浸 + 3s 自动隐控件\n'
                  '· 浅色 / 深色 / 跟随系统三主题\n'
                  '· 收藏本地持久化\n'
                  '· 后台强制更新 (GitHub Releases)',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
              _AboutSection(
                label: '项目地址',
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          kGitHubRepoUrl,
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        tooltip: '复制 GitHub 地址',
                        onPressed: () => _copyRepoUrl(ctx),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // v0.3.7+80: 复制 GitHub 地址到剪贴板 + SnackBar 提示.
  void _copyRepoUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: kGitHubRepoUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制 GitHub 地址, 粘贴到浏览器查看'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ─── 检查更新 ─────────────────────────────────────────────────────────────
  // v0.3.7+80: 调 versionCheckerProvider.notifier.checkOnStartup() —
  // 走跟启动时一样的逻辑 (cache 命中跳过, fetch GitHub API).
  // state 变化时用 listenManual 监听弹 SnackBar / Dialog.
  void _checkUpdate(BuildContext context, WidgetRef ref) {
    // 1. 显示 loading SnackBar.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在检查更新…'),
        duration: Duration(seconds: 2),
      ),
    );

    // 2. 监听 state 变化 — 一次性, 弹 SnackBar / Dialog 后不持续触发.
    // listenManual 在 widget dispose 时自动 cancel, 不会泄漏.
    ref.listenManual<VersionCheckState>(
      versionCheckerProvider,
      (prev, next) {
        if (next is VersionCheckUpToDate) {
          _showUpdateSnack(context, '已是最新版本 ${next.latestVersion}');
        } else if (next is VersionCheckOutdated) {
          // outdated 走 ForceUpdateDialog.show() (跟启动时一致, barrierDismissible=false
          // P0/critical 时强制更新,  老板点不过去).
          ForceUpdateDialog.show(context);
        } else if (next is VersionCheckFailed) {
          _showUpdateSnack(context, '检查更新失败: ${next.reason}');
        }
      },
      fireImmediately: true,
    );

    // 3. 触发 fetch (走 checkOnStartup 跟启动时一致 — 1h cache / fetch API).
    // ⚠️ 必须用 .read(provider.notifier) 而不是 .read(provider),
    // .notifier 拿 Notifier 实例,  才能调 checkOnStartup() 方法.
    ref.read(versionCheckerProvider.notifier).checkOnStartup();
  }

  void _showUpdateSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── 更新源 URL 编辑 (v0.3.7+85, v0.3.7+92) ────────────────────────────────────────────
  // v0.3.7+85: 老板手机国内访问 api.github.com 经常超时, 弹 dialog 让老板填国内中转 URL.
  // v0.3.7+92: 默认 endpoint 改为 gh-proxy.com (代理 api.github.com),
  //   国内 600ms.  老板还是能在 dialog 里改 (填别的代理 / 填自建镜像 / 重置回默认).
  // 填完调 endpointProvider.notifier.setEndpoint() 持久化.
  Future<void> _editEndpoint(BuildContext context, WidgetRef ref) async {
    final current = ref.read(endpointProvider);
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新源 URL'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '默认: gh-proxy.com 代理 api.github.com (国内 600ms)',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                '其他中转: gh-proxy.com / 自建镜像 (NAS + nginx)',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: '更新源 URL',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
                maxLines: 2,
                minLines: 1,
                keyboardType: TextInputType.url,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // 重置默认 (gh-proxy.com)
              await ref.read(endpointProvider.notifier).resetEndpoint();
              if (ctx.mounted) Navigator.of(ctx).pop('reset');
            },
            child: const Text('重置默认'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              await ref.read(endpointProvider.notifier).setEndpoint(url);
              if (ctx.mounted) Navigator.of(ctx).pop(url);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result == 'reset' ? '已重置为默认 gh-proxy.com 代理' : '已保存: $result'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ─── 主题选择对话框 (老功能保留) ──────────────────────────────────────────
  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref, {
    required ThemeMode current,
  }) async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('选择主题'),
          children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                title: Text(_modeLabel(mode)),
                value: mode,
                groupValue: current,
                onChanged: (v) => Navigator.of(ctx).pop(v),
              ),
          ],
        );
      },
    );
    if (picked != null && picked != current) {
      await ref.read(themeModeProvider.notifier).setMode(picked);
    }
  }

  static String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }
}

// ─── 内部组件 ──────────────────────────────────────────────────────────────

/// v0.3.7+80: 细分割线,  跟设置页 ListTile 之间分隔用,  复用 0.5px outlineVariant.
class _ThinDivider extends StatelessWidget {
  const _ThinDivider();
  @override
  Widget build(BuildContext context) {
    // v0.3.8+96 (6/20 13:08 老板反馈): _ThinDivider 完全看不见.
    // 之前用 outlineVariant.withOpacity(0.5) — outlineVariant 默认 = dividerWarm
    // #E8E0D4, 0.5 透明度泿到 bgParchment #F5F4ED = 几乎不可见.
    // 老板说 "设置页没看到分隔线, ListTile 粗在一起".
    // 现在改用 outline (直接 dividerWarm #E8E0D4), 厚度 1px, 浅米色对比
    // 采米色 bgParchment (lum 0.93 vs 0.85) — 对比度 1.4:1 (W3C AA 仅供参考,
    // M3 spec 推荐用 surfaceVariant 做 ListTile 间分隔, 不果来在采调上是低对比).
    // 为保证看得见,  让 divider 颜色稍深一点 (#C8C0B5) —  对比度 1.7:1
    // 看得清但采米色系统不破坏.
    return Divider(
      height: 1,
      thickness: 1,
      color: const Color(0xFFC8C0B5), // 稍深的米色分隔线 (visible on bgParchment)
    );
  }
}

/// v0.3.7+80: 关于对话框里的小节 (label + content),  label 加粗.
class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}