import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
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
    final asyncChannels = ref.watch(channelsProvider);

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
            loading: () => const _LoadingState(),
            error: (e, _) => _ErrorState(message: e.toString()),
            data: (channels) => _buildContent(context, channels),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Channel> all) {
    // 派生 3 大分类 — 主页是「容器」, 分类页是「真实列表」
    // 卡 6 会做收藏/历史; 此处只读 lastChannelId
    final cctv = ChannelFilter.cctv(all).length;
    final satellite = ChannelFilter.satellite(all).length;
    final local = all.length - cctv - satellite;

    const items = [
      CategoryItem(
        id: 'cctv',
        title: '央视',
        subtitle: 'CCTV 频道',
        icon: Icons.tv,
      ),
      CategoryItem(
        id: 'satellite',
        title: '卫视',
        subtitle: '省级卫视',
        icon: Icons.public,
      ),
      CategoryItem(
        id: 'local',
        title: '地方',
        subtitle: '省市地方台',
        icon: Icons.location_city,
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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: IptvColors.accentTerracotta,
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
                color: IptvColors.textPrimary,
                tooltip: '搜索频道',
                onPressed: onSearchTap,
              ),
              // 6/17 v0.2.3 P1-2: 收藏页入口,  在 search 旁加 ❤️ icon
              IconButton(
                icon: const Icon(Icons.favorite_border),
                color: IptvColors.textPrimary,
                tooltip: '我的收藏',
                onPressed: () => context.push('/favorites'),
              ),
              // 0.3.6+19: 暗色主题设置入口,  加齿轮 icon
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                color: IptvColors.textPrimary,
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    // P0-2 (6/17 老板): 冷启动 < 1.5s — 主页骨架先出, 频道数据后填.
    // 用静态灰色占位卡代替 CircularProgressIndicator, 用户立刻看到布局,
    // 感知更快. 频道 async 加载完后 _buildContent 接管.
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _AppHeaderSkeleton()),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(child: _ContinueWatchingSkeleton()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverGrid.count(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: const [
              _CategoryCardSkeleton(),
              _CategoryCardSkeleton(),
              _CategoryCardSkeleton(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 骨架屏 — 单个占位块 (灰色 12 圆角 + 12% 白边)
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    this.width,
    this.height = 16,
    this.borderRadius = 6,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // 暖米色骨架色 — 在 IptvColors.dividerWarm 基础上加透明度, 不刺眼
        color: IptvColors.dividerWarm.withOpacity(0.4),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// 骨架屏 — AppHeader (logo + 标题 + 搜索/收藏 按钮)
class _AppHeaderSkeleton extends StatelessWidget {
  const _AppHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: const [
          _SkeletonBox(width: 36, height: 36, borderRadius: 8),
          SizedBox(width: 12),
          _SkeletonBox(width: 96, height: 22),
          Spacer(),
          _SkeletonBox(width: 36, height: 36, borderRadius: 18),
          SizedBox(width: 4),
          _SkeletonBox(width: 36, height: 36, borderRadius: 18),
        ],
      ),
    );
  }
}

/// 骨架屏 — 「继续观看」卡占位 (一档频道预览)
class _ContinueWatchingSkeleton extends StatelessWidget {
  const _ContinueWatchingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IptvColors.dividerWarm.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: IptvColors.dividerWarm.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: const Row(
        children: [
          _SkeletonBox(width: 60, height: 36, borderRadius: 6),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 120, height: 16),
                SizedBox(height: 6),
                _SkeletonBox(width: 80, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 骨架屏 — 单个 CategoryCard 占位
class _CategoryCardSkeleton extends StatelessWidget {
  const _CategoryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: IptvColors.dividerWarm.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: IptvColors.dividerWarm.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 44, height: 44, borderRadius: 12),
          SizedBox(height: 12),
          _SkeletonBox(width: 56, height: 18),
          SizedBox(height: 6),
          _SkeletonBox(width: 80, height: 12),
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
          const Icon(
            Icons.error_outline,
            color: IptvColors.accentTerracotta,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
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
