// 0.3.6+19 设置页.
//
// 一个 ListTile "主题" → 弹出 RadioListTile 选 系统 / 浅色 / 深色.
// 复用 theme_provider, 切换后立即持久化 (SharedPreferences),
// main.dart 的 ConsumerWidget 监听 themeModeProvider 同步给 MaterialApp.themeMode.
//
// v0.3.7+80 (6/19): 加 2 个 tile — "检查更新" + "关于视界".
//  关于: 描述项目 + 贴 GitHub 地址 + 一键复制按钮.  不用 url_launcher 包
//  (省 1MB + Android query intent 配置),  复制 URL 让老板自己粘贴到浏览器看.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// v0.3.11 Beta 分支

// v0.3.7.2 (6/19): 不再 import main.dart (主 dart 写死 const 没用),  用 Provider 读运行时版本号.
import '../../services/version_checker.dart'
    show
        currentVersionStringProvider,
        versionCheckerProvider,
        VersionCheckState,
        VersionCheckUpToDate,
        VersionCheckOutdated,
        VersionCheckFailed,
        endpointProvider,
        kDefaultEndpointUrl;
import '../update/force_update_dialog.dart' show ForceUpdateDialog;
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/vod_source.dart';
import '../../../services/tvbox_config_parser.dart';
import '../../../services/vod_source_registry.dart';
import 'theme_provider.dart';
import 'widgets/recent_history.dart';
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
      backgroundColor: context.bgBase,
      appBar: AppBar(
        backgroundColor: context.bgBase,
        foregroundColor: context.fgMain,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              context.appBrightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              context.appBrightness == Brightness.dark ? Brightness.dark : Brightness.light,
        ),
        title: Text(
          '设置',
          style: TextStyle(color: context.fgMain),
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
          // ─── 品牌 header: 视界 logo ──────────────────────────────────
          const _SettingsGroupLabel(label: '功能'),
          const SizedBox(height: 6),
          _FeatureCardGrid(
                              onCheckUpdate: () => _checkUpdate(context, ref),
                              onShowAbout: () => _showAbout(context),
                            ),
          const SizedBox(height: 16),

          // ─── 卡片 1: 外观 ──────────────────────────────────────────────
          const _SettingsGroupLabel(label: '外观'),
          const SizedBox(height: 6),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('主题模式'),
                subtitle: Consumer(
                  builder: (context, ref, _) {
                    final mode = ref.watch(themeModeProvider);
                    return Text(_modeLabel(mode));
                  },
                ),
                onTap: () => _showThemeDialog(context, ref),
              ),
              const _SettingsGap(),
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome),
                title: const Text('自动深色'),
                subtitle: const Text('日落后自动切换深色'),
                value: _autoDarkMode,
                onChanged: (v) => _setAutoDark(context, ref, v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ─── 卡片 2: 系统 ──────────────────────────────────────────────
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
                title: const Text('关于视界'),
                subtitle: const Text('项目介绍 + GitHub 地址'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAbout(context),
              ),
              const _SettingsGap(),
              Consumer(
                builder: (context, ref, _) {
                  final version = ref.watch(currentVersionStringProvider);
                  final displayVersion = '$version (Beta)';
                  return ListTile(
                    leading: const Icon(Icons.tag_outlined),
                    title: const Text('版本号'),
                    subtitle: Text(displayVersion),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ─── v0.3.13.0: 影视源管理卡片 ──────────────────────────────
          const _SettingsGroupLabel(label: '影视源'),
          const SizedBox(height: 6),
          _VodSourceManagementCard(),
          const SizedBox(height: 16),
          // ─── 最近浏览记录 ──────────────────────────────────────────
          const _SettingsGroupLabel(label: '最近浏览'),
          const SizedBox(height: 6),
          const RecentHistory(),
          const SizedBox(height: 32),

          // ─── 底部 footer (slogan,  跟 about 区分) ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              '视界 · 极简新中式 IPTV',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 关于对话框 ───────────────────────────────────────────────────────────
  // v0.3.7+80: 弹一个 dialog,  描述项目 (基于 Flutter + media_kit 视频播放,
  // 极简新中式设计,  直播 + 影视).  底部贴 GitHub 地址 + 复制按钮.
  void _showAbout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于视界'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '视界是一款直播 + 影视综合平台, 面向家用电视 / 盒子 / 手机, 极简新中式设计。',
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
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
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

/// 顶部功能导航网格：收藏 / 播放历史 / 检查更新 / 关于.
class _FeatureCardGrid extends StatelessWidget {
  const _FeatureCardGrid({
    required this.onCheckUpdate,
    required this.onShowAbout,
    super.key,
  });
  final VoidCallback onCheckUpdate;
  final VoidCallback onShowAbout;

  void _navigate(String location, BuildContext context) {
    if (context.mounted) {
      context.push(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = <_FeatureCardItem>[
      _FeatureCardItem(
        label: '我的收藏',
        icon: Icons.bookmark_outline,
        color: Colors.blue,
        onTap: () => _navigate('/favorites', context),
      ),
      _FeatureCardItem(
        label: '播放历史',
        icon: Icons.history_outlined,
        color: Colors.green,
        onTap: () => _navigate('/playback-history', context),
      ),
      _FeatureCardItem(
        label: '检查更新',
        icon: Icons.system_update_outlined,
        color: Colors.orange,
        onTap: onCheckUpdate,
      ),
      _FeatureCardItem(
        label: '关于视界',
        icon: Icons.info_outline,
        color: Colors.purple,
        onTap: onShowAbout,
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: context.bgCard,
        child: Row(
          children: cards
              .map((item) => Expanded(
                    child: _FeatureCardItemView(item),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _FeatureCardItemView extends StatelessWidget {
  const _FeatureCardItemView(this.item, {super.key});
  final _FeatureCardItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      onTapDown: (_) => _splashController.add(SplashPosition(item.label)),
      onTapUp: (_) => _splashController.remove(SplashPosition(item.label)),
      onTapCancel: () => _splashController.remove(SplashPosition(item.label)),
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            _SplashOverlay(position: SplashPosition(item.label)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 28, color: item.color),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF333333),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SplashController {
  final Set<SplashPosition> _positions = {};
  void add(SplashPosition position) => _positions.add(position);
  void remove(SplashPosition position) => _positions.remove(position);
  bool isPressed(String key) => _positions.any((p) => p.key == key);
}

final _splashController = _SplashController();

class SplashPosition {
  SplashPosition(this.key);
  final String key;
}

class _SplashOverlay extends StatelessWidget {
  const _SplashOverlay({required this.position, super.key});
  final SplashPosition position;

  @override
  Widget build(BuildContext context) {
    if (!_splashController.isPressed(position.key)) return const SizedBox();
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05)),
      ),
    );
  }
}

class _FeatureCardItem {
  const _FeatureCardItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

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
      color: context.bgBase,
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
        color: context.bgCard,
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
      // v0.3.13.0: 标题字体跟 _MineTile 一致 (15sp / w900 Roboto — 老板要求
      // 设置页和我的页 UI 字体保持一致). DefaultTextStyle 让内部所有 ListTile
      // title 自动继承, 不再用 ListTile 默认的 16sp/w500 Material 样式.
      child: DefaultTextStyle(
        style: IptvTypography.sansTitle.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
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

// ─── 主题模式辅助 ───

String _modeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return '跟随系统';
    case ThemeMode.light:
      return '浅色';
    case ThemeMode.dark:
      return '深色';
  }
}

bool _autoDarkMode = false;

Future<void> _showThemeDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(themeModeProvider);
  var selected = current;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
      title: const Text('主题模式'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: ThemeMode.values.map((mode) {
          return RadioListTile<ThemeMode>(
            title: Text(_modeLabel(mode)),
            value: mode,
            groupValue: selected,
            onChanged: (v) => setLocal(() => selected = v!),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            ref.read(themeModeProvider.notifier).setMode(selected);
            Navigator.of(ctx).pop();
          },
          child: const Text('确定'),
        ),
      ],
    ),
    ),
  );
}

Future<void> _setAutoDark(BuildContext context, WidgetRef ref, bool value) async {
  _autoDarkMode = value;
  // TODO: 实现自动深色 (日落检测)
}

/// v0.3.13.0: VOD 源管理卡片 (设置页).
/// 当前源 / 管理源 toggle / 导入 TVBox 源.
class _VodSourceManagementCard extends ConsumerWidget {
  const _VodSourceManagementCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(vodSourceRegistryProvider);
    final sources = registry.sources;
    final active = registry.activeSource;

    return _SettingsCard(
      children: [
        // 当前源.
        ListTile(
          leading: const Icon(Icons.play_circle_outline),
          title: const Text('当前源'),
          subtitle: Text(active.name),
          trailing: Text('${sources.length} 个源'),
          onTap: () => _showSourcePicker(context, ref, registry),
        ),
        const _SettingsGap(),
        // 管理源 (toggle 列表).
        ...sources.map((s) => SwitchListTile(
              secondary: Icon(
                s.builtIn ? Icons.verified : Icons.public,
                size: 20,
              ),
              title: Text(s.name),
              subtitle: Text(
                s.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              value: true,
              onChanged: s.builtIn
                  ? null // 内置不可删
                  : (v) {
                      if (!v) {
                        ref
                            .read(vodSourceRegistryProvider)
                            .removeSource(s.id);
                      }
                    },
            )),
        const _SettingsGap(),
        // 操作按钮行.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              // 添加自定义源.
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                  onPressed: () => _showAddSourceDialog(context, ref),
                ),
              ),
              const SizedBox(width: 8),
              // 导入 TVBox 源.
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('导入 TVBox'),
                  onPressed: () => _importTvBoxSources(context, ref),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 选源 bottom sheet.
  void _showSourcePicker(
      BuildContext context, WidgetRef ref, VodSourceRegistry registry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择影视源', style: TextStyle(fontSize: 16)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: registry.sources.map((s) {
                  final active = s.id == registry.activeSourceId;
                  return ListTile(
                    leading: Icon(
                      active ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: active ? Theme.of(ctx).colorScheme.primary : null,
                    ),
                    title: Text(s.name),
                    subtitle: Text(s.host),
                    onTap: () {
                      registry.setActiveSource(s.id);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 添加自定义源对话框.
  void _showAddSourceDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var scheme = VodTypeIdScheme.bfzyapi;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('添加影视源'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '如: 量子资源',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'MacCMS API 地址',
                    hintText: 'https://xxx.com/api.php/provide/vod',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('typeId 方案:'),
                    const SizedBox(width: 8),
                    DropdownButton<VodTypeIdScheme>(
                      value: scheme,
                      items: VodTypeIdScheme.values
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text(e.label)))
                          .toList(),
                      onChanged: (v) => setLocal(() => scheme = v ?? scheme),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _doAdd(context, ref, nameCtrl, urlCtrl, scheme, ctx),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback _doAdd(
    BuildContext context,
    WidgetRef ref,
    TextEditingController nameCtrl,
    TextEditingController urlCtrl,
    VodTypeIdScheme scheme,
    BuildContext ctx,
  ) {
    return () {
      final name = nameCtrl.text.trim();
      final url = urlCtrl.text.trim();
      if (name.isEmpty || url.isEmpty) return;
      String host;
      try {
        host = Uri.parse(url).host;
      } catch (_) {
        host = 'vod';
      }
      final id = '${host}_${DateTime.now().millisecondsSinceEpoch}';
      ref.read(vodSourceRegistryProvider).addSource(VodSource(
            id: id,
            name: name,
            baseUrl: url,
            typeIds: scheme.typeIds,
          ));
      Navigator.pop(ctx);
    };
  }

  /// 导入 TVBox 源 — 拉 4 个 URL,  展示新发现数,  一键导入.
  Future<void> _importTvBoxSources(BuildContext context, WidgetRef ref) async {
    // 加载指示.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    List<VodSource> found;
    try {
      final parser = TvBoxConfigParser();
      found = await parser.fetchTvBoxSources();
      parser.dispose();
    } catch (e) {
      found = [];
    }
    if (context.mounted) Navigator.pop(context); // 关加载

    if (!context.mounted) return;
    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现可导入的 MacCMS 源, 请检查网络')),
      );
      return;
    }

    // 过滤已存在的 (同 host).
    final registry = ref.read(vodSourceRegistryProvider);
    final existingHosts = registry.sources.map((s) => s.host).toSet();
    final newOnes = found.where((s) => !existingHosts.contains(s.host)).toList();

    if (newOnes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入全部 ${found.length} 个源, 无新增')),
      );
      return;
    }

    // 确认导入对话框.
    final selected = List<bool>.filled(newOnes.length, true);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('发现 ${newOnes.length} 个新源'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: newOnes.length,
              itemBuilder: (ctx, i) => CheckboxListTile(
                title: Text(newOnes[i].name),
                subtitle: Text(newOnes[i].host),
                value: selected[i],
                onChanged: (v) => setLocal(() => selected[i] = v ?? false),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );

    if (result == true && context.mounted) {
      final toImport = <VodSource>[];
      for (var i = 0; i < newOnes.length; i++) {
        if (selected[i]) toImport.add(newOnes[i]);
      }
      if (toImport.isNotEmpty) {
        await ref.read(vodSourceRegistryProvider).addSources(toImport);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已导入 ${toImport.length} 个影视源')),
          );
        }
      }
    }
  }
}
