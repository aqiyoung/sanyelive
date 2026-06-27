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
import '../../core/theme/colors.dart';
import '../../services/version_checker.dart'
    show
        currentVersionStringProvider,
        currentVersionCodeProvider,
        versionCheckerProvider,
        VersionCheckState,
        VersionCheckUpToDate,
        VersionCheckOutdated,
        VersionCheckFailed,
        endpointProvider,
        kDefaultEndpointUrl;
import '../update/force_update_dialog.dart' show ForceUpdateDialog;
// v0.3.8+102 (6/20 15:02 老板反馈): 删主题切换, 锁死浅色.  theme_provider
// 保留文件 (兼容老 prefs), 但 settings_page 不再 import, 也不暴露 UI.

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
    // v0.3.8+102 (6/20 15:02 老板反馈): 删主题切换, 锁死浅色. 不再 watch themeModeProvider.
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '设置',
          // v0.3.8+103 (6/20 15:46 老板反馈): 显式 color: textPrimary.
          // 之前 AppBar title 靠 theme.appBarTheme.titleTextStyle = serifTitle
          // (没 hardcode color,  走 system default).  老板装 +102 后看
          // 到"设置"是白色的看不清.  现在显式指定 color 跟 textPrimary.
          style: TextStyle(color: IptvColors.textPrimary),
        ),
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
        // v0.3.8+97 (6/20 13:11 老板反馈): _ThinDivider 太原始,  老板要高端.
        // 改成 iOS-style 卡片分组:
        //   - 3 张卡片 (外观 / 系统 / 关于)
        //   - 卡片间靠间距 + group label 区分,  不画线
        //   - 每张卡片圆角 12 + bgElevated 背景 + 内部 ListTile 用 1px divider
        //   - 卡片间 16px vertical padding
        //   - group label (小字 12px,  onSurfaceVariant,  左侧 padding 4)
        // 参见 iOS Settings.app + Material 3 cards 设计语言.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // v0.3.8+102 (6/20 15:02 老板反馈): 删"外观 / 主题"卡片 (锁死浅色).
          // 之前这里有 主题 tile + _pickTheme 对话框. 现在直接跳到"系统".
          // ─── 卡片 1: 系统 ──────────────────────────────────────────────
          const _SettingsGroupLabel(label: '系统'),
          const SizedBox(height: 6),
          _SettingsCard(
            children: [
              // v0.3.7+80: 手动触发 versionCheckerProvider.notifier.checkOnStartup().
              ListTile(
                leading: const Icon(Icons.system_update_alt_outlined),
                title: const Text('检查更新'),
                subtitle: const Text('当前版本 + 最新版本对比'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _checkUpdate(context, ref),
              ),
              // v0.3.8+98 (6/20 13:39): 用透明间隔条代替 divider — 老板说
              // "所有容器分割不要线".  视觉上是空白,  不是线.
              const _SettingsGap(),
              // v0.3.7+92 (6/20 08:42 老板反馈): 默认 endpoint 改为 gh-proxy.com
              // v0.3.8+95: 启动时 pattern match 自动迁移老 api.github.com URL.
              Consumer(
                builder: (context, ref, _) {
                  final endpoint = ref.watch(endpointProvider);
                  final isDefault = endpoint == kDefaultEndpointUrl;
                  return ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('更新源'),
                    subtitle: Text(
                      isDefault ? '默认 (api.github.com 直连)' : endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editEndpoint(context, ref),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ─── 卡片 3: 关于 ──────────────────────────────────────────────
          const _SettingsGroupLabel(label: '关于'),
          const SizedBox(height: 6),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于三页直播'),
                subtitle: const Text('项目介绍 + GitHub 地址'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAbout(context),
              ),
              const _SettingsGap(),
              Consumer(
                builder: (context, ref, _) {
                  final version = ref.watch(currentVersionStringProvider);
                  final code = ref.watch(currentVersionCodeProvider);
                  return ListTile(
                    leading: const Icon(Icons.tag_outlined),
                    title: const Text('版本号'),
                    subtitle: Text('$version (build $code)'),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),

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
    ref.read(versionCheckerProvider.notifier).checkForce();
  }

  void _showUpdateSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── 更新源 URL 编辑 (v0.3.7+85, v0.3.10.13) ──────────────────────────────────────────
  // v0.3.7+85: 老板手机国内访问 api.github.com 经常超时, 弹 dialog 让老板填国内中转 URL.
  // v0.3.10.13 (6/24): 默认改为直连 api.github.com,  老 gh-proxy.com URL 自动迁移.
  // 老板还是能在 dialog 里改 (填 CF Worker / 自建镜像 / 重置回默认).
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
                '默认: api.github.com 直连',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                '备选: 自建镜像 (NAS + nginx)',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '更新源 URL',
                  // v0.3.8+99 (6/20 14:03 老板反馈): 删 OutlineInputBorder 四
                  // 周边框线,  改 UnderlineInputBorder (只保留 focus 时的下
                  // 划线).  iOS-style 极简风格.
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
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
              // 重置默认 (api.github.com 直连)
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
          content: Text(result == 'reset'
              ? '已重置为默认 (api.github.com 直连)'
              : '已保存: $result'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

// ─── 内部组件 ──────────────────────────────────────────────────────────────

/// v0.3.7+80: 细分割线,  跟设置页 ListTile 之间分隔用,  复用 0.5px outlineVariant.
/// v0.3.8+98 (6/20 13:39 老板反馈): _SettingsGap = 卡片内部两个 ListTile
/// 之间的"透明间隔条" (背景色 = bgParchment, 高度 8).
/// 老板原话: "所有容器分割不要线. 用其他方式来把它隔开".
/// 跟 _SettingsDivider (线条) 不同,  这个是"留白"分隔:
///   - 从 bgElevated 卡片背景 → bgParchment scaffold 背景的色块
///   - 高度 8px,  让两个 ListTile 不粘在一起
///   - 视觉上像"切开两个 tile 的水平空隙",  但实际是色块
class _SettingsGap extends StatelessWidget {
  const _SettingsGap();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      color: const Color(0xFFF5F4ED), // bgParchment 跟 scaffold 同色
      margin: EdgeInsets.zero,
    );
  }
}

/// v0.3.8+97 (6/20 13:11 老板反馈): _SettingsCard = iOS-style 卡片.
/// 圆角 12 + bgElevated (#FFFCF6) 背景 + 内部 ListTile 自动适配.
/// 卡片间不画线, 靠 group label + spacing 区分.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6), // bgElevated — 浅一档米色, 跟 bgParchment 区分
        borderRadius: BorderRadius.circular(12),
        // v0.3.8+97: 不画边框, 靠背景色差 + 圆角 + 阴影让卡片"浮"起来
        // boxShadow: [
        //   BoxShadow(
        //     color: Colors.black.withValues(alpha: 0.04),
        //     blurRadius: 8,
        //     offset: const Offset(0, 2),
        //   ),
        // ],
      ),
      clipBehavior: Clip.antiAlias, // 让内部 ListTile ripple 不溢出圆角
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// v0.3.8+97: _SettingsGroupLabel = 卡片上方的小标题 (12px, onSurfaceVariant).
/// iOS Settings.app 风格: "外观" / "系统" / "关于".
class _SettingsGroupLabel extends StatelessWidget {
  const _SettingsGroupLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
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
