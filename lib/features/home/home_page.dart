import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/typography.dart';
import '../../core/tv/tv_focus.dart';
import '../../data/channel_filter.dart';
import '../../data/models/channel.dart';
import '../../data/repositories/channel_repository.dart';
import '../../services/startup_service.dart';
import '../../widgets/serif_headline.dart';
import 'widgets/category_grid.dart';

/// 主页 — 3 大分类 (央视/卫视/地方) + 上次观看 CTA + 搜索入口
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.onClearLastWatched});

  /// 清除上次观看的回调 (留给父级实现)
  final VoidCallback? onClearLastWatched;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String? _lastChannelId;

  @override
  void initState() {
    super.initState();
    _loadLastChannel();
  }

  Future<void> _loadLastChannel() async {
    final svc = ref.read(startupServiceProvider);
    final id = await svc.loadLastChannel();
    if (mounted) setState(() => _lastChannelId = id);
  }

  Future<void> _clearLast() async {
    final svc = ref.read(startupServiceProvider);
    await svc.clearLastChannel();
    if (mounted) setState(() => _lastChannelId = null);
    widget.onClearLastWatched?.call();
  }

  @override
  Widget build(BuildContext context) {
    // v0.3.8+132 (6/21 老板反馈 "启动白屏"):  之前用 channelsProvider (FutureProvider
    // 返本地).  改用 channelsStreamProvider (StreamProvider 同步 yield 本地 → background
    // 远端覆盖).  这样首帧拿到本地 198 频道,  UI 不空白;  远端 360 频道 (36 sat +
    // 101 local + 44 cctv + 133 intl) 到了后 UI 刷新,  老板看到正确的分类 (卫视
    // 36 个 vs 老 35 个 加上 HenanTVSatellite + 中文命名).
    final asyncChannels = ref.watch(channelsStreamProvider);

    return Scaffold(
      // 6/17 v0.2.3 P1-5: TV 端 root 包 TvFocusGroup,  CategoryCard /
      // ContinueWatchingCard 内部已经各自包了 TvFocus (deviceTier == tv
      // 才包),  这里是方向键导航容器.  手机端 child 就是原 CustomScrollView,
      //  零成本.
      // 6/17 v0.3.0: 移除 AppBar title — 身体 _AppHeader 已带 logo+标题+搜索
      // 收藏, AppBar 重复显示.  保留 AppBar 用于返回 / 状态栏 spacing.
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: TvFocusGroup(
          child: asyncChannels.when(
            loading: () => const SizedBox.expand(),
            error: (e, _) => _ErrorState(message: e.toString()),
            data: (channels) => _buildContent(context, channels),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Channel> all) {
    // 派生分类 — 主页是「容器」, 分类页是「真实列表」
    final cctv = ChannelFilter.cctv(all).length;
    final satellite = ChannelFilter.satellite(all).length;
    final news = ChannelFilter.byCategory(all, '新闻').length;
    final movies = ChannelFilter.byCategory(all, '影视').length;
    final kids = ChannelFilter.byCategory(all, '少儿').length;
    final international = ChannelFilter.international(all).length;
    // 地方 = 总数 - 央视 - 卫视
    final local = all.length - cctv - satellite;

    final items = [
      const CategoryItem(
        id: 'cctv',
        title: '央视',
        subtitle: 'CCTV 频道',
        icon: Icons.tv,
      ),
      const CategoryItem(
        id: 'satellite',
        title: '卫视',
        subtitle: '省级卫视',
        icon: Icons.public,
      ),
      CategoryItem(
        id: '新闻',
        title: '新闻',
        subtitle: '$news 个频道',
        icon: Icons.newspaper,
      ),
      CategoryItem(
        id: '影视',
        title: '影视',
        subtitle: '$movies 个频道',
        icon: Icons.movie,
      ),
      CategoryItem(
        id: '少儿',
        title: '少儿',
        subtitle: '$kids 个频道',
        icon: Icons.child_care,
      ),
      const CategoryItem(
        id: 'local',
        title: '地方',
        subtitle: '省市地方台',
        icon: Icons.location_city,
      ),
      // v0.3.8+110 (6/20 老板加国际频道):  i18n 频道 (非中文区 country)
      CategoryItem(
        id: 'international',
        title: '国际',
        subtitle: '$international 个频道',
        icon: Icons.language,
      ),
    ];

    // 找上次的频道 (轻量查找, 500 条不算多)
    final lastChannel = _lastChannelId == null
        ? null
        : all.where((c) => c.id == _lastChannelId).cast<Channel?>().firstOrNull;

    // P2-1 (6/18): 一屏焦点项上限守卫 — ChatGPT 6/17 21:18 建议
    //   当前 home_page (TV) 焦点项:
    //     - 3 个 AppBar actions (search / favorites / settings) — 0.3.6+19 加了 settings
    //     - 1 个 ContinueWatchingCard (当有 lastChannel 时)
    //     - 3 个 CategoryCard
    //   最多 7 个, 远低于 9. 但用 TvFocusScope 断言, 后续加新焦点项时
    //   超出上限会报 assert 警告, 防止漂移.
    final focusableCount = 3 + 3 + (lastChannel != null ? 1 : 0);

    return TvFocusScope(
      actualFocusableCount: focusableCount,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AppHeader(
                  onSearchTap: () => context.go('/search'),
                  onSettingsTap: () => context.push('/settings'),
                ),
                // 上次观看 (有记录才显示)
                if (lastChannel != null) ...[
                  ContinueWatchingCard(
                    channelName: lastChannel.displayName,
                    channelLogo: lastChannel.logoUrl,
                    subtitle: '继续播放',
                    onTap: () => context.push('/player/${lastChannel.id}'),
                    onClear: _clearLast,
                  ),
                  const SizedBox(height: 24),
                ],
                const SerifHeadline(
                  '频道分类',
                  // 6/17 v0.2.3 P0-1: 实事求是,  实际 bake 了 484 个 CN 频道.
                  // 7800+ 是 iptv-org 全量,  未进 APP.  改 500+.
                  // 未来 v0.3.0 会重 bake + 二级分类.
                  subtitle: '500+ 国内频道 · iptv-org 数据源',
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: CategoryGrid(
              items: items,
              onItemTap: (item) {
                final count = switch (item.id) {
                  'cctv' => cctv,
                  'satellite' => satellite,
                  'local' => local,
                  // v0.3.8+110 (6/20 老板加国际频道):  i18n 频道 count
                  'international' => international,
                  _ => 0,
                };
                context.push(
                  '/category/${item.id}?title=${Uri.encodeComponent(item.title)}',
                  extra: count,
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({this.onSearchTap, this.onSettingsTap});

  final VoidCallback? onSearchTap;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          // v0.3.7+84 (6/19 老板反馈): 恢复 home 顶部 logo 原版 (v0.3.6+41 之前).
          // 老板 22:37 反馈 "首页的logo换回来 不要3 你理解错了 我要改的是app的图标
          // 但是也不能是3":
          //   - 首页 logo: 恢复 v0.3.7+64 老设计 (红底 + Icons.live_tv 白图标)
          //   - launcher icon: 老板说 "app 的图标"  = launcher,  v0.3.7+83 已
          //     改成 TV 直播图标 (无 "3"),  保持
          // 总结: 首页 logo 回到红底白电视;  launcher icon 不动 (TV 直播图标).
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.live_tv,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '三页直播',
            style: IptvTypography.serifTitle,
          ),
          const Spacer(),
          // P2-1 (6/18 老板拍): AppBar actions 套 TvFocusCapWrap,
          //  maxPerRow=3, 加新按钮超出上限会报 assert 警告.
          //  Wrap 布局对 3 个 IconButton 跟原 Row 等价 (不会折行).
          TvFocusCapWrap(
            maxPerRow: 3,
            spacing: 0,
            runSpacing: 0,
            children: [
              IconButton(
                icon: const Icon(Icons.search),
                // 6/18 v0.3.6.1 hotfix: textPrimary → onSurface
                color: Theme.of(context).colorScheme.onSurface,
                tooltip: '搜索频道',
                onPressed: onSearchTap,
              ),
              // 6/17 v0.2.3 P1-2: 收藏页入口,  在 search 旁加 ❤️ icon
              IconButton(
                icon: const Icon(Icons.favorite_border),
                // 6/18 v0.3.6.1 hotfix: textPrimary → onSurface
                color: Theme.of(context).colorScheme.onSurface,
                tooltip: '我的收藏',
                onPressed: () => context.push('/favorites'),
              ),
              // 0.3.6+19: 暗色主题设置入口,  加齿轮 icon
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                // 6/18 v0.3.6.1 hotfix: textPrimary → onSurface
                color: Theme.of(context).colorScheme.onSurface,
                tooltip: '设置',
                onPressed: onSettingsTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            '加载频道失败',
            style: IptvTypography.serifTitle,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: IptvTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
