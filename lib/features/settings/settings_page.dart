//
// 一个 ListTile "主题" → 弹出 RadioListTile 选 系统 / 浅色 / 深色.
// 复用 theme_provider, 切换后立即持久化 (SharedPreferences),
// main.dart 的 ConsumerWidget 监听 themeModeProvider 同步给 MaterialApp.themeMode.
//
//  关于: 描述项目 + 贴 GitHub 地址 + 一键复制按钮.  不用 url_launcher 包

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/version_checker.dart'
    show
        currentVersionStringProvider,
        versionCheckerProvider,
        VersionCheckState,
        VersionCheckUpToDate,
        VersionCheckOutdated,
        VersionCheckFailed,
        autoCheckUpdateProvider,
        betaChannelProvider;
import 'home_preview_provider.dart' show homePreviewProvider;
import '../update/force_update_dialog.dart' show ForceUpdateDialog;
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/vod_source.dart';
import '../../../services/tvbox_config_parser.dart';
import '../../../services/vod_source_registry.dart';
import 'theme_provider.dart';
import 'app_mode_provider.dart';
import 'province_provider.dart' show provinceProvider;
// 省份列表 (定位选择器).
import '../../data/province_util.dart' show kProvinces;
// 保留文件 (兼容老 prefs), 但 settings_page 不再 import, 也不暴露 UI.

//   / textSecondary) 都改走 colorScheme.onSurface / onSurfaceVariant,  跟
//   暗色主题联动.  之前 hardcode 浅米色文字在暗背景下看不清.  不再 import
//   IptvColors — 全部跟主题走.

const String kGitHubRepoUrl = 'https://github.com/aqiyoung/sanyelive';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        // 改成 iOS-style 卡片分组:
        //   - 3 张卡片 (外观 / 系统 / 关于)
        //   - 卡片间靠间距 + group label 区分,  不画线
        //   - 每张卡片圆角 12 + bgElevated 背景 + 内部 ListTile 用 1px divider
        //   - 卡片间 16px vertical padding
        //   - group label (小字 12px,  onSurfaceVariant,  左侧 padding 4)
        // 参见 iOS Settings.app + Material 3 cards 设计语言.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
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
              const _SettingsGap(),
              // 完整功能模式: 默认关 = 电视直播精简界面 (首页+我的),
              // 开 = 显示全部 5 个底部标签 (首页/短视频/会员/发现/我的).
              Consumer(
                builder: (context, ref, _) {
                  final full = ref.watch(appModeProvider);
                  return SwitchListTile(
                    secondary: const Icon(Icons.grid_view_rounded),
                    title: const Text('完整功能模式'),
                    subtitle: const Text('开启后显示短视频/会员/发现等全部入口'),
                    value: full,
                    onChanged: (v) =>
                        ref.read(appModeProvider.notifier).setFull(v),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ─── 卡片 2: 系统 ──────────────────────────────────────────────
          const _SettingsGroupLabel(label: '系统'),
          const SizedBox(height: 6),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.system_update_alt_outlined),
                title: const Text('检查更新'),
                subtitle: const Text('当前版本 + 最新版本对比'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _checkUpdate(context),
              ),
              const _SettingsGap(),
              Consumer(
                builder: (context, ref, _) {
                  final province = ref.watch(provinceProvider);
                  return ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('当前省份'),
                    subtitle: Text(province == null
                        ? '未设置（卫视按默认顺序）'
                        : '当前：$province'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showProvinceDialog(context, ref),
                  );
                },
              ),
              const _SettingsGap(),
              Consumer(
                builder: (context, ref, _) {
                  final auto = ref.watch(autoCheckUpdateProvider);
                  return SwitchListTile(
                    secondary: const Icon(Icons.autorenew_outlined),
                    title: const Text('启动时自动检查更新'),
                    subtitle: const Text('关闭时启动后不再主动弹窗，可手动点「检查更新」'),
                    value: auto,
                    onChanged: (v) =>
                        ref.read(autoCheckUpdateProvider.notifier).set(v),
                  );
                },
              ),
              const _SettingsGap(),
              Consumer(
                builder: (context, ref, _) {
                  final beta = ref.watch(betaChannelProvider);
                  return SwitchListTile(
                    secondary: const Icon(Icons.new_releases_outlined),
                    title: const Text('接收 Beta 版更新'),
                    subtitle: const Text('开启后检测 Beta 预发布版本（本应用仅有 Beta 版）'),
                    value: beta,
                    onChanged: (v) =>
                        ref.read(betaChannelProvider.notifier).set(v),
                  );
                },
              ),
              const _SettingsGap(),
              Consumer(
                builder: (context, ref, _) {
                  final enabled = ref.watch(homePreviewProvider);
                  return SwitchListTile(
                    secondary: const Icon(Icons.preview_outlined),
                    title: const Text('首页直播预览'),
                    subtitle: const Text(
                      '关闭后首页顶部只显示静态卡片，可解决部分设备花屏',
                    ),
                    value: enabled,
                    onChanged: (v) =>
                        ref.read(homePreviewProvider.notifier).set(v),
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
                onTap: () => _showAbout(context, ref),
              ),
              const _SettingsGap(),
              Consumer(
                builder: (context, ref, _) {
                  final version = ref.watch(currentVersionStringProvider);
                  final displayVersion =
                      'v${version.replaceFirst(RegExp(r'^v'), '')} (Beta)';
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

          // 影视源 (VOD) 仅完整功能模式可见, TV 直播模式隐藏.
          if (ref.watch(appModeProvider)) ...[
            const _SettingsGroupLabel(label: '影视源'),
            const SizedBox(height: 6),
            _VodSourceManagementCard(),
            const SizedBox(height: 32),
          ],

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
  // 精简玻璃小窗: 一句话介绍 + 版本 + GitHub 地址复制, 避免像一整页.
  void _showAbout(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final version = ref.watch(currentVersionStringProvider);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => AlertDialog(
        title: const Text('关于视界',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '极简新中式 IPTV · 直播 + 影视综合平台',
              style: TextStyle(color: scheme.onSurface, height: 1.6),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
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
            const SizedBox(height: 10),
            Text(
              'v$version (Beta) · Flutter · media_kit · Riverpod',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
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
  // 单个玻璃小窗, 内部用 Consumer 订阅 versionCheckerProvider, state 一变
  // 小窗自动刷新: 检查中 → 已是最新 / 发现新版本 / 失败. 单 dialog 实例,
  // 避免旧版"先弹 loading 再弹结果"两段式弹窗关闭错乱的隐患.
  void _checkUpdate(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => const AlertDialog(
        content: _CheckUpdateDialogBody(),
      ),
    );
  }

  // ─── 当前省份 (定位) ──────────────────────────────────────────────────────
  // 自动定位 (IP 地理, best-effort) + 手动选择. 选择后卫视列表把该省排最前.
  void _showProvinceDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(provinceProvider.notifier);
    // detecting 必须声明在 showDialog 之外 —— 放进 StatefulBuilder 的 builder
    // 里会在每次 setLocal 重建时被重置回 false, "定位中" 状态永远显示不出来.
    var detecting = false;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      // Consumer 提供 dialog 自己的 ref: 在 dialog 回调里用外层页面的 ref.watch
      // 会被 Riverpod 断言拦下 (watch 只能在 build 中调用).
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Consumer(
          builder: (ctx, dRef, _) {
            final current = dRef.watch(provinceProvider);
            final scheme = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Text('定位当前省份',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              content: SizedBox(
                width: double.maxFinite,
                height: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      icon: detecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.my_location, size: 18),
                      label: Text(detecting ? '定位中…' : '自动定位'),
                      onPressed: detecting
                          ? null
                          : () async {
                              setLocal(() => detecting = true);
                              final p = await notifier.autoDetect();
                              setLocal(() => detecting = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(p == null
                                        ? '自动定位失败，请手动选择'
                                        : '已定位到：$p'),
                                  ),
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          ...kProvinces.map(
                            (p) => RadioListTile<String?>(
                              title: Text(p),
                              value: p,
                              groupValue: current,
                              onChanged: (v) {
                                notifier.setProvince(v);
                                setLocal(() {});
                              },
                            ),
                          ),
                          RadioListTile<String?>(
                            title: const Text('不设置（默认顺序）'),
                            value: null,
                            groupValue: current,
                            onChanged: (v) {
                              notifier.setProvince(v);
                              setLocal(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('完成', style: TextStyle(color: scheme.primary)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 更新流程专用强调色 — 青玉 teal, 替代品牌赤陶红, 避免更新弹窗"红得刺眼".
const Color _kUpdateAccent = Color(0xFF2A9D8F);
const Color _kUpdateAccentContainer = Color(0xFFE6F4F2);

/// 检查更新小窗内容 — Consumer 订阅 state, 自动在 检查中/结果 间切换.
/// 新版设计: 居中状态图标 + 大标题 + 内容卡片 + 底部操作, 去红、去拥挤.
class _CheckUpdateDialogBody extends ConsumerStatefulWidget {
  const _CheckUpdateDialogBody();

  @override
  ConsumerState<_CheckUpdateDialogBody> createState() =>
      _CheckUpdateDialogBodyState();
}

class _CheckUpdateDialogBodyState extends ConsumerState<_CheckUpdateDialogBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(versionCheckerProvider.notifier).checkForce();
      }
    });
  }

  @override
  Widget build(BuildContext ctx) {
    final scheme = Theme.of(ctx).colorScheme;
    final state = ref.watch(versionCheckerProvider);
    final current = ref.watch(currentVersionStringProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(scheme, state),
        const SizedBox(height: 20),
        _buildBody(scheme, state, current),
        const SizedBox(height: 24),
        _buildActions(ctx, scheme, state),
      ],
    );
  }

  Widget _buildHeader(ColorScheme scheme, VersionCheckState state) {
    if (state is VersionCheckUpToDate) {
      return _StatusHeader(
        icon: Icons.check_circle_outline_rounded,
        accent: _kUpdateAccent,
        title: '已是最新版本',
        subtitle: '当前版本无需更新',
      );
    }
    if (state is VersionCheckOutdated) {
      return _StatusHeader(
        icon: Icons.rocket_launch_outlined,
        accent: _kUpdateAccent,
        title: '发现新版本',
        subtitle: '升级后可体验最新功能',
      );
    }
    if (state is VersionCheckFailed) {
      return _StatusHeader(
        icon: Icons.cloud_off_outlined,
        accent: scheme.onSurfaceVariant,
        title: '检查更新失败',
        subtitle: '网络或 GitHub 访问受限',
      );
    }
    return _StatusHeader(
      icon: Icons.sync_outlined,
      accent: _kUpdateAccent,
      title: '正在检查更新',
      subtitle: '连接 GitHub 获取最新版本…',
      isLoading: true,
    );
  }

  Widget _buildBody(ColorScheme scheme, VersionCheckState state, String current) {
    if (state is VersionCheckUpToDate) {
      return _VersionMetaCard(
        child: Text(
          '当前 v$current 已为最新版本',
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.6),
        ),
      );
    }
    if (state is VersionCheckOutdated) {
      return _OutdatedInfo(state: state, current: current);
    }
    if (state is VersionCheckFailed) {
      return _VersionMetaCard(
        child: Text(
          state.reason,
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.6),
        ),
      );
    }
    return _VersionMetaCard(
      child: Text(
        '正在连接 GitHub 获取最新版本信息，请稍候…',
        style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.6),
      ),
    );
  }

  Widget _buildActions(BuildContext ctx, ColorScheme scheme, VersionCheckState state) {
    if (state is VersionCheckUpToDate) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: _kUpdateAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text('确定'),
        ),
      );
    }
    if (state is VersionCheckOutdated) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('查看更新详情'),
            style: FilledButton.styleFrom(
              backgroundColor: _kUpdateAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              ForceUpdateDialog.show(ctx);
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '稍后再说',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    if (state is VersionCheckFailed) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => ref.read(versionCheckerProvider.notifier).checkForce(),
            style: FilledButton.styleFrom(
              backgroundColor: _kUpdateAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('重试'),
          ),
        ],
      );
    }
    // 检查中: 不显示操作按钮, 避免用户误点.
    return const SizedBox.shrink();
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.isLoading = false,
  });
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
                  ),
                )
              : Icon(icon, color: accent, size: 30),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _VersionMetaCard extends StatelessWidget {
  const _VersionMetaCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.maxFinite,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
      ),
      child: child,
    );
  }
}

class _OutdatedInfo extends StatelessWidget {
  const _OutdatedInfo({required this.state, required this.current});
  final VersionCheckOutdated state;
  final String current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 版本对比: 当前(灰) → 最新(青玉)
        Row(
          children: [
            _VersionChip(label: 'v$current', dim: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
            _VersionChip(label: state.latestVersion, dim: false),
          ],
        ),
        if (state.releaseName.isNotEmpty && state.releaseName != state.latestVersion) ...[
          const SizedBox(height: 12),
          Text(
            state.releaseName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
            ),
            child: SingleChildScrollView(
              child: _ReleaseNotesText(notes: state.releaseNotes),
            ),
          ),
        ),
      ],
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.label, required this.dim});
  final String label;
  final bool dim;

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

/// 简单渲染 release notes: 把 Markdown 标题/粗体/列表做基础高亮, 提升可读性.
class _ReleaseNotesText extends StatelessWidget {
  const _ReleaseNotesText({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (notes.isEmpty) {
      return Text(
        '暂无变更日志',
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

      // 标题: ## / ###
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
        // 列表项 / 普通行: 去掉前导 "- " 后加小圆点
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

// ─── 内部组件 ──────────────────────────────────────────────────────────────

/// 之间的"透明间隔条" (背景色 = bgParchment, 高度 8).
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

/// 圆角 12 + bgElevated (#FFFCF6) 背景 + 内部 ListTile 自动适配.
/// 卡片间不画线, 靠 group label + spacing 区分.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
      ),
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
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('主题模式',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
              child: Text('取消', style: TextStyle(color: scheme.onSurfaceVariant)),
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
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => Container(
        margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8, top: 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SafeArea(
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
                        color: active ? scheme.primary : null,
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
      ),
    );
  }

  /// 添加自定义源对话框.
  void _showAddSourceDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var scheme = VodTypeIdScheme.bfzyapi;
    final colorScheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('添加影视源',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
              child: Text('取消', style: TextStyle(color: colorScheme.onSurfaceVariant)),
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
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('发现 ${newOnes.length} 个新源',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
              child: Text('取消', style: TextStyle(color: scheme.onSurfaceVariant)),
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
