import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sanyelive/widgets/channel_logo.dart';
import 'package:sanyelive/widgets/liquid_glass_container.dart';

import '../../../core/theme/colors.dart';
import '../settings/app_mode_provider.dart';
import '../../../data/providers/vod_provider.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/content.dart';
import '../../../data/channel_filter.dart';
import '../../../data/province_util.dart' show sortSatelliteByProvince;
import '../../../features/settings/province_provider.dart'
    show provinceProvider;
import '../../../services/platform/mdk_opener.dart' show configureDeinterlace;
import '../../../data/repositories/channel_repository.dart';
import '../../../data/source_dispatcher.dart';
import '../../../di/player_providers.dart';
import 'widgets/special_zone_section.dart';

/// 视界 海报墙首页
class PosterWallPage extends ConsumerWidget {
  const PosterWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 电视直播模式 (默认): 首页只展示 TV 频道模块 (_LiveTvModule),
    // 隐藏影视海报轮播 / 分类快捷 / 今日推荐 / 热播剧集等 VOD 内容.
    // 完整功能模式: 展示全部模块 (顺序与之前一致).
    final fullMode = ref.watch(appModeProvider);
    return ColoredBox(
      color: context.bgBase,
      child: SafeArea(
        bottom: false,
        top: false,
        child: FutureBuilder<List<Channel>>(
          // 本地 logo 为 null 时拿远程 logo fill, 台标出现.
          // channelsProvider 同步返本地 (loadBundled 有缓存, 零 IO), 远程拉取
          // fire-and-forget, FutureBuilder 首帧不白屏.
          future: ref.read(channelsProvider.future),
          builder: (context, snapshot) {
            final channels = snapshot.data ?? const <Channel>[];
            final liveChannels = channels
                .where((ch) => ch.categories.any((c) => ['央视', '卫视', '体育', '地方', '影视'].contains(c)))
                .toList();
            final displayChannels = liveChannels.isNotEmpty ? liveChannels : channels;

            final isLoading = snapshot.connectionState == ConnectionState.waiting;

            return Column(
              children: [
                _HomeTopBar(showSearch: fullMode),
                Expanded(
                  child: fullMode
                      ? ListView(
                          padding: const EdgeInsets.only(bottom: 20),
                          children: [
                            const _HeroBanner(),
                            const SizedBox(height: 18),
            const _CategoryShortcutBar(),
            const SizedBox(height: 18),
            const SpecialZoneSection(),
            const SizedBox(height: 20),
            _LiveTvModule(
                              isLoading: isLoading,
                              channels: displayChannels.take(4).toList(),
                              error: snapshot.error,
                            ),
                            const SizedBox(height: 20),
                            _VodSection(
                              title: '今日推荐',
                              provider: vodRecommendedProvider,
                              badges: const ['HOT', 'VIP', '独播'],
                            ),
                            const SizedBox(height: 20),
                            _VodSectionWithTabs(
                              title: '热播剧集',
                              provider: vodSeriesProvider,
                              badges: const ['热播', 'VIP', '热播', 'VIP', 'VIP'],
                              tabs: const ['全部', '古装', '都市', '悬疑', '爱情'],
                            ),
                            const SizedBox(height: 20),
                          ],
                        )
                      : _TvLeanbackHome(
                          isLoading: isLoading,
                          channels: displayChannels,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({this.showSearch = true});

  /// 电视直播模式 (showSearch=false) 隐藏搜索框 + 播放记录图标, 仅留品牌 + 模式标签.
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10 + MediaQuery.of(context).padding.top, 16, 8),
      child: Row(
        children: [
          // 品牌 icon
          Image.asset(
            'assets/icons/app_logo.png',
            width: 28,
            height: 28,
          ),
          const SizedBox(width: 8),
          Text(
            '视界',
            style: TextStyle(
              color: context.fgMain,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          if (showSearch) ...[
            const SizedBox(width: 14),
            Expanded(
                child: GestureDetector(
                  onTap: () => context.go('/search'),
                  child: LiquidGlassContainer(
                    variant: LiquidGlassVariant.light,
                    borderRadius: 19,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: context.fgSub, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '庆余年 第二季',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.fgSub, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _TopIcon(icon: Icons.history_rounded, onTap: () => context.go('/playback-history')),
          ] else ...[
            const Spacer(),
            const _ClockText(),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.fgAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '电视直播',
                style: TextStyle(color: context.fgAccent, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: context.fgMain, size: 22),
      onPressed: onTap,
    );
  }
}

/// TV 模式下栏右侧的实时时钟 (每 30s 刷新), 增强电视端氛围.
class _ClockText extends StatelessWidget {
  const _ClockText();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 30), (i) => i),
      builder: (context, _) {
        final now = TimeOfDay.now();
        final h = now.hour.toString().padLeft(2, '0');
        final m = now.minute.toString().padLeft(2, '0');
        return Text(
          '$h:$m',
          style: TextStyle(color: context.fgSub, fontSize: 13, fontWeight: FontWeight.w600),
        );
      },
    );
  }
}

/// TV 模式首页 (Leanback 风格):
/// 精选 Hero (主推直播) → 横向分类 chips → 多行「正在直播 / 央视 / 卫视 / 体育」频道墙.
class _TvLeanbackHome extends ConsumerWidget {
  const _TvLeanbackHome({required this.isLoading, required this.channels});

  final bool isLoading;
  final List<Channel> channels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hero 主推优选第一个 (CCTV-1), 而不是频道库原始首项
    final hotList = ChannelFilter.hot(channels, limit: 12);
    final featured = hotList.isNotEmpty ? hotList.first : null;
    // 复用 ChannelFilter (与分类页 / chips 路由一致), 避免 categories 派生
    // 与分类页过滤逻辑不一致导致首页分类行缺失.
    final cctv = ChannelFilter.cctv(channels);
    final satelliteAll = ChannelFilter.satellite(channels);
    // 定位: 当前省份的卫视排到最前.
    final province = ref.watch(provinceProvider);
    final satellite = sortSatelliteByProvince(satelliteAll, province);
    final local = ChannelFilter.local(channels);
    final sports = ChannelFilter.byCategory(channels, '体育');
    final movie = ChannelFilter.byCategory(channels, '影视');

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (isLoading && featured == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          _TvHero(channel: featured, isLoading: isLoading),
        const SizedBox(height: 18),
        const _ChannelChips(),
        const SizedBox(height: 22),
        const SpecialZoneSection(),
        const SizedBox(height: 20),
        // 优选热门频道 (央视 + 头部卫视), 不再铺全量 198 个频道
        _ChannelRow(title: '正在直播', channels: hotList),
        const SizedBox(height: 20),
        if (cctv.isNotEmpty) ...[
          _ChannelRow(title: '央视频道', channels: cctv),
          const SizedBox(height: 20),
        ],
        if (satellite.isNotEmpty) ...[
          _ChannelRow(title: '卫视频道', channels: satellite),
          const SizedBox(height: 20),
        ],
        if (local.isNotEmpty) ...[
          _ChannelRow(title: '地方频道', channels: local),
          const SizedBox(height: 20),
        ],
        if (sports.isNotEmpty) ...[
          _ChannelRow(title: '体育频道', channels: sports),
          const SizedBox(height: 20),
        ],
        if (movie.isNotEmpty) ...[
          _ChannelRow(title: '影视频道', channels: movie),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// 精选 Hero — 主推一个直播频道 (默认 CCTV-1), 内嵌**静音**实时播放预览
/// (首页专用独立 Player + VideoController, 与全屏播放页的 Player 隔离, 互不争用
/// 纹理). 叠加 LIVE 徽标 + 节目信息条. 点击进入全屏播放页 (带声音).
///
/// 预览默认 setVolume(0) 静音, 避免一进首页就出声; 全屏播放页用独立 Player
/// 以正常音量播放. libmpv 不可用 / 取流失败时, 自动降级到静态台标 + 播放键
/// 兜底 (_HeroBackdrop), 不会崩.
class _TvHero extends ConsumerStatefulWidget {
  const _TvHero({required this.channel, required this.isLoading});

  final Channel? channel;
  final bool isLoading;

  @override
  ConsumerState<_TvHero> createState() => _TvHeroState();
}

class _TvHeroState extends ConsumerState<_TvHero> {
  bool _previewReady = false;
  bool _previewFailed = false;
  String? _openedChannelId;
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    // 首帧后再开流 — 避免 build 期间触发 Riverpod "modify during build".
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startPreview()));
  }

  @override
  void didUpdateWidget(covariant _TvHero old) {
    super.didUpdateWidget(old);
    if (old.channel?.id != widget.channel?.id) _startPreview();
  }

  Future<void> _startPreview() async {
    final ch = widget.channel;
    if (ch == null) return;
    // 同一频道已尝试过 (成功或失败) 不再重复开流.
    if (_openedChannelId == ch.id && (_previewReady || _previewFailed)) return;

    // 复用全局共享 Player / VideoController —— 与全屏播放页共用同一实例.
    // 首页与播放页是不同路由, 两个 Video widget 不会同时挂载, 不存在纹理争用;
    // 这正是历史上能正常出画面的实现. 独立 Player 方案在本设备反而花屏.
    final player = ref.read(mediaKitPlayerProvider);
    final controller = ref.read(mediaKitVideoControllerProvider);
    if (player == null || controller == null) {
      // libmpv 不可用 → 静态兜底.
      if (mounted) setState(() => _previewFailed = true);
      return;
    }
    final sources = SourceDispatcher.dispatch(ch);
    if (sources.isEmpty) {
      if (mounted) setState(() => _previewFailed = true);
      return;
    }
    _player = player;
    _controller = controller;
    _openedChannelId = ch.id;
    if (mounted) setState(() => _previewReady = false);
    try {
      // 央视 1080i 隔行源必须软件去隔行 (bwdif), 否则预览出梳状隔行纹/花屏.
      // 等价于全屏播放页 MediaKitStreamOpener 的处理, 不能省.
      await configureDeinterlace(player);
      // 首页预览默认静音 — 进播放页时 PlayerService.play() 会恢复音量 (setVolume(100)).
      await player.setVolume(0);
      await player.open(Media(sources.first));
      if (mounted && _openedChannelId == ch.id) {
        setState(() => _previewReady = true);
      }
    } catch (_) {
      if (mounted && _openedChannelId == ch.id) {
        setState(() => _previewFailed = true);
      }
    }
  }

  @override
  void dispose() {
    // 离开首页: 暂停共享 Player, 避免预览声音在其他页面或后台继续播放.
    // 不 dispose 共享 Player — 其生命周期由 PlayerService 管理.
    try {
      _player?.pause();
    } catch (_) {
      // 共享 player 可能已被释放, 静默忽略.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // watch 保持共享 Player / controller 在首页期间存活 (与全屏播放页同一实例).
    final player = ref.watch(mediaKitPlayerProvider);
    final controller = ref.watch(mediaKitVideoControllerProvider);
    _player ??= player;
    _controller ??= controller;

    final channel = widget.channel;
    final onTap = channel == null ? null : () => context.go('/player/${channel.id}');
    final showVideo = _controller != null && !_previewFailed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 预览就绪即挂 Video (立即, 不等 videoParams) — 首帧一到就显示实时画面.
                if (showVideo)
                  SizedBox.expand(
                    child: Video(
                      // Key 含频道 id: 切换精选频道时强制 Video 与 texture 重建,
                      // 避免复用旧 surface 尺寸导致花屏/灰屏.
                      key: ValueKey('hero-${channel?.id}'),
                      controller: _controller!,
                      fit: BoxFit.cover,
                      aspectRatio: 16 / 9,
                    ),
                  )
                else
                  // 兜底: libmpv 不可用 / 取流失败 / 加载中 — 不显示台标, 只给通用图标.
                  _HeroBackdrop(
                    channel: channel,
                    isLoading: widget.isLoading,
                  ),
                // 首帧未到前显示加载圈 (盖在 Video 上); 一旦 _previewReady 即消失.
                if (showVideo && !_previewReady)
                  const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                const Positioned(left: 16, top: 16, child: _Badge(label: '直播中', color: Color(0xFFE53935))),
                Positioned(
                  right: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      channel?.displayName ?? '视界直播',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0x80000000),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '正在直播',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          channel?.displayName ?? '精彩节目直播中',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero 静态兜底背景 — libmpv 不可用 / 取流失败 / 加载中时显示.
/// 直播预览就绪后, 视频层会盖在它上面 (BoxFit.cover 铺满), 此处内容不可见.
/// 注意：预览场景不显示频道台标, 避免遮挡/干扰真实视频画面.
class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.channel, required this.isLoading});

  final Channel? channel;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0E12), Color(0xFF101418), Color(0xFF1A1015)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -30,
            bottom: -30,
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE53935).withValues(alpha: 0.32),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLoading ? Icons.hourglass_empty_rounded : Icons.live_tv_rounded,
                  color: Colors.white70,
                  size: 46,
                ),
                const SizedBox(height: 14),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 横向滚动的频道分类 chips (全部/央视/卫视/体育/地方/影视), 点选跳转对应分类页.
class _ChannelChips extends StatelessWidget {
  const _ChannelChips();

  static const List<_Chip> _chips = [
    _Chip('全部直播', Icons.live_tv_rounded, '/category/live'),
    _Chip('央视', Icons.tv_rounded, '/category/cctv'),
    _Chip('卫视', Icons.satellite_rounded, '/category/satellite'),
    _Chip('体育', Icons.sports_soccer_rounded, '/category/体育'),
    _Chip('地方', Icons.location_on_rounded, '/category/local'),
    _Chip('影视', Icons.movie_creation_rounded, '/category/影视'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = _chips[i];
          return GestureDetector(
            onTap: () => context.go(c.route),
            child: LiquidGlassContainer(
              variant: LiquidGlassVariant.light,
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(c.icon, color: context.fgAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(c.label, style: TextStyle(color: context.fgMain, fontSize: 13, fontWeight: FontWeight.w700, height: 1)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chip {
  const _Chip(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

/// 一行可横向滚动的频道卡片墙 (标题 + LIVE 卡片).
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.title, required this.channels});

  final String title;
  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(color: context.fgMain, fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _ChannelCard(channel: channels[i]),
          ),
        ),
      ],
    );
  }
}

/// 单个频道卡片: 台标 + LIVE 徽标 + 频道名.
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    // 浅色 parchment 背景上卡片用 light 玻璃; 中间白色台标直接浮在玻璃上,
    // 由 ChannelLogo(shadow:true) 用形状投影把 logo 托出, 不再套深色底牌.
    return GestureDetector(
      onTap: () => context.go('/player/${channel.id}'),
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.light,
        borderRadius: 20,
        width: 150,
        padding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Center(
              child: ChannelLogo(
                channel: channel,
                size: 48,
                shadow: true,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'LIVE',
                    style: TextStyle(color: Color(0xFFE53935), fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Text(
                channel.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.fgMain, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBanner extends StatefulWidget {
  const _HeroBanner();

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  late final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_PosterItem> _posters = const [
    _PosterItem(
      gradientColors: const [Color(0xFF4B1F1D), Color(0xFF151515), Color(0xFF2C1A12)],
      circleColor: const Color(0xFFE8A449),
      badge: '独播',
      badgeColor: const Color(0xFFE53935),
      title: '庆余年 第二季',
      subtitle: '余年有幸  与君再相逢',
      enTitle: 'QING YU NIAN',
    ),
    _PosterItem(
      gradientColors: const [Color(0xFF0D2137), Color(0xFF151515), Color(0xFF1A2A3A)],
      circleColor: const Color(0xFF4FC3F7),
      badge: '科幻',
      badgeColor: const Color(0xFF1565C0),
      title: '三体',
      subtitle: '人类文明的至暗时刻',
      enTitle: 'THE THREE-BODY PROBLEM',
    ),
    _PosterItem(
      gradientColors: const [Color(0xFF2A0D1A), Color(0xFF151515), Color(0xFF2A1515)],
      circleColor: const Color(0xFFE040FB),
      badge: '悬疑',
      badgeColor: const Color(0xFF7B1FA2),
      title: '漫长的季节',
      subtitle: '往前看，别回头',
      enTitle: 'THE LONG SEASON',
    ),
    _PosterItem(
      gradientColors: const [Color(0xFF1A3A1A), Color(0xFF151515), Color(0xFF1A2A1A)],
      circleColor: const Color(0xFF66BB6A),
      badge: '动作',
      badgeColor: const Color(0xFF2E7D32),
      title: '狂飙',
      subtitle: '正义与罪恶的较量',
      enTitle: 'THE KNOCKOUT',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 178,
          child: Stack(
            children: [
              PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: _posters.map((p) => _PosterSlide(item: p)).toList(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_posters.length, (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _currentPage == i ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? context.fgMain
                              : context.fgMain.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterItem {
  final List<Color> gradientColors;
  final Color circleColor;
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final String enTitle;

  const _PosterItem({
    required this.gradientColors,
    required this.circleColor,
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.enTitle,
  });
}

class _PosterSlide extends StatelessWidget {
  final _PosterItem item;
  const _PosterSlide({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: item.gradientColors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -28,
            top: -18,
            bottom: -12,
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    item.circleColor.withValues(alpha: 0.45),
                    item.circleColor.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 18,
            child: _Badge(label: item.badge, color: item.badgeColor),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.go('/search'),
                splashColor: Colors.white.withValues(alpha: 0.06),
                highlightColor: Colors.white.withValues(alpha: 0.03),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: 8),
                Text(item.subtitle, style: const TextStyle(color: Color(0xFFD5D5D5), fontSize: 13)),
                const SizedBox(height: 12),
                Text(item.enTitle, style: const TextStyle(color: Color(0x55FFFFFF), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryShortcutBar extends StatelessWidget {
  const _CategoryShortcutBar();

  @override
  Widget build(BuildContext context) {
    const shortcuts = [
      _Shortcut('电视直播', Icons.live_tv_rounded, const Color(0xFFE53935), '/category/live'),
      _Shortcut('电影', Icons.movie_creation_rounded, const Color(0xFF8E44AD), '/vod-category?cat=movie'),
      _Shortcut('电视剧', Icons.tv_rounded, const Color(0xFF3D7CFF), '/vod-category?cat=series'),
      _Shortcut('综艺', Icons.star_rounded, const Color(0xFF35B36B), '/vod-category?cat=variety'),
      _Shortcut('动漫', Icons.face_retouching_natural_rounded, const Color(0xFFF0B429), '/vod-category?cat=anime'),
      _Shortcut('纪录片', Icons.public_rounded, const Color(0xFF42A5F5), '/vod-category?cat=documentary'),
      _Shortcut('体育', Icons.sports_soccer_rounded, const Color(0xFF43A047), '/vod-category?cat=sports'),
      _Shortcut('海外剧场', Icons.language_rounded, const Color(0xFF00BCD4), '/vod-category?cat=overseas'),
    ];

    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: shortcuts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = shortcuts[index];
          return GestureDetector(
            onTap: item.route == null ? null : () => context.go(item.route!),
            child: SizedBox(
              width: 58,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LiquidGlassContainer(
                    variant: LiquidGlassVariant.light,
                    borderRadius: 18,
                    width: 52,
                    height: 52,
                    child: Center(child: Icon(item.icon, color: item.color, size: 27)),
                  ),
                  const SizedBox(height: 7),
                  Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgMain, fontSize: 12, fontWeight: FontWeight.w500, height: 1)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LiveTvModule extends StatelessWidget {
  const _LiveTvModule({required this.isLoading, required this.channels, this.error});

  final bool isLoading;
  final List<Channel> channels;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final textColor = context.fgMain;

    // 优选热门: Hero 主推第 1 个, 右侧「正在直播」列表接后 3 个.
    // 原来直接取全量 channels 前 4 个, 冷门地方台常年霸屏.
    final hot = ChannelFilter.hot(channels, limit: 4);
    final primary = hot.isNotEmpty ? hot.first : null;
    final rest = hot.skip(1).take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LiquidGlassContainer(
          variant: LiquidGlassVariant.light,
          borderRadius: 22,
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 116,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左: 直播预览 (logo + 播放按钮居中成视觉重心, 顶部标/底部节目条贴边, 黑框不再空旷)
              Expanded(
                flex: 5,
                child: GestureDetector(
                  onTap: primary == null ? null : () => context.go('/player/${primary.id}'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        children: [
                          // 视觉重心: logo + 半透明播放按钮 整体居中, 填充黑框中部
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                isLoading
                                    ? Icon(Icons.hourglass_empty_rounded, color: context.fgSub, size: 34)
                                    : ChannelLogo(channel: primary, size: 54),
                                const SizedBox(height: 9),
                                ClipOval(
                                  child: LiquidGlassContainer(
                                    variant: LiquidGlassVariant.dark,
                                    borderRadius: 19,
                                    width: 38,
                                    height: 38,
                                    child: const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Positioned(left: 8, top: 8, child: _Badge(label: '直播中', color: Color(0xFFE53935))),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(primary?.displayName ?? '视界', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          ),
                          // 底部节目条
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: const BoxDecoration(
                                color: Color(0x73000000),
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                              child: Text(
                                '正在直播 · ${primary?.displayName ?? "精彩节目"}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 右: 正在直播频道列表 (紧凑排列 + 细分隔线边界感, 填满整列不留白)
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('正在直播', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => context.go('/category/live'),
                          child: Text('全部', style: TextStyle(color: context.fgAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: isLoading
                          ? const Center(child: _LiveListText(title: '加载中', subtitle: '读取频道库'))
                          : rest.isEmpty
                              ? const Center(child: _LiveListText(title: '暂无频道', subtitle: '请检查数据'))
                              : ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: rest.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 10,
                                    thickness: 1,
                                    color: context.fgBorder.withValues(alpha: 0.7),
                                  ),
                                  itemBuilder: (context, index) {
                                    final ch = rest[index];
                                    return GestureDetector(
                                      onTap: () => context.go('/player/${ch.id}'),
                                      behavior: HitTestBehavior.opaque,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Container(width: 6, height: 6, decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(3))),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(ch.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgMain, fontSize: 12, fontWeight: FontWeight.w700)),
                                                  const SizedBox(height: 2),
                                                  Text('即将播出 · 精彩节目', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgSub, fontSize: 10)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
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
}

class _LiveListText extends StatelessWidget {
  const _LiveListText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgMain, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(subtitle.isEmpty ? '精彩节目直播中' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgSub, fontSize: 11)),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.content, required this.badge});

  final Content content;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final badgeColor = badge == 'VIP'
        ? const Color(0xFFF0B429)
        : badge == 'HOT'
            ? const Color(0xFFE53935)
            : const Color(0xFF8E44AD);

    return GestureDetector(
      onTap: () {
        if (content.sourceUrls.isNotEmpty &&
            !content.sourceUrls.first.contains('example.com')) {
          context.go('/player/vod?url=${Uri.encodeComponent(content.sourceUrls.first)}&title=${Uri.encodeComponent(content.title)}');
        } else {
          context.go('/search');
        }
      },
      child: SizedBox(
        width: 104,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 142,
              width: 104,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF343434), badgeColor.withValues(alpha: 0.32), const Color(0xFF171717)],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        content.title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.15),
                      ),
                    ),
                  ),
                  Positioned(right: 7, top: 7, child: _Badge(label: badge, color: badgeColor)),
                  if (content.rating != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF0B429), size: 14),
                          const SizedBox(width: 2),
                          Text(content.displayRating, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(content.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgMain, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(content.subtitle ?? '${content.year ?? '热播'} · ${content.genres.take(2).join(' ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fgSub, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.icon, this.color, this.route);

  final String label;
  final IconData icon;
  final Color color;
  final String? route;
}

class _VodSection extends ConsumerWidget {
  const _VodSection({required this.title, required this.provider, required this.badges});

  final String title;
  final FutureProvider<List<Content>> provider;
  final List<String> badges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(title, style: TextStyle(color: context.fgMain, fontSize: 20, fontWeight: FontWeight.w900)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/search'),
                child: Row(
                  children: [
                    Text('更多', style: TextStyle(color: context.fgSub, fontSize: 13)),
                    Icon(Icons.chevron_right_rounded, color: context.fgSub, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 194,
          child: async.when(
            loading: () => Center(child: CircularProgressIndicator(color: context.fgSub, strokeWidth: 2)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败: ${e.toString().split("\n").first}', style: TextStyle(color: context.fgSub, fontSize: 13)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Center(child: Text('暂无内容', style: TextStyle(color: context.fgSub)));
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _PosterCard(content: items[index], badge: badges[index % badges.length]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 热播剧集 / 热播电影 — 带分类筛选标签的 VOD 横滚区.
/// 参考图: 标题行下方是「全部 / 古装 / 都市 / 悬疑 / 爱情」筛选标签,
/// 选中态红色描边 + 浅红底, 未选中灰字灰边.
class _VodSectionWithTabs extends ConsumerStatefulWidget {
  const _VodSectionWithTabs({
    required this.title,
    required this.provider,
    required this.badges,
    required this.tabs,
  });

  final String title;
  final FutureProvider<List<Content>> provider;
  final List<String> badges;
  final List<String> tabs;

  @override
  ConsumerState<_VodSectionWithTabs> createState() =>
      _VodSectionWithTabsState();
}

class _VodSectionWithTabsState extends ConsumerState<_VodSectionWithTabs> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(widget.provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          color: context.fgMain,
                          fontSize: 20,
                          fontWeight: FontWeight.w900)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.go('/search'),
                    child: Row(
                      children: [
                        Text('更多', style: TextStyle(color: context.fgSub, fontSize: 13)),
                        Icon(Icons.chevron_right_rounded,
                            color: context.fgSub, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: widget.tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isSelected = _selectedTab == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTab = index),
                      child: LiquidGlassContainer(
                        variant: LiquidGlassVariant.light,
                        borderRadius: 14,
                        tint: isSelected ? context.fgAccent : null,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Text(
                          widget.tabs[index],
                          style: TextStyle(
                            color: isSelected ? context.fgAccent : context.fgSub,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 194,
          child: async.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.fgSub, strokeWidth: 2)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败: ${e.toString().split("\n").first}',
                    style: TextStyle(color: context.fgSub, fontSize: 13)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Center(
                    child: Text('暂无内容', style: TextStyle(color: context.fgSub)));
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _PosterCard(
                  content: items[index],
                  badge: widget.badges[index % widget.badges.length],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
