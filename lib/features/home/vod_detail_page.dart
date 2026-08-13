import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sanyelive/widgets/liquid_glass_container.dart';
import '../../../core/theme/colors.dart';
import '../../../data/models/content.dart';
import '../../../data/providers/vod_provider.dart';
import '../../../services/vod_source_registry.dart';
import '../../../services/vod_parse_service.dart';

/// 影视详情 / 选集页.
/// 路由: /vod-detail?id=<数字vodId>&title=<片名>
/// 从海报墙 / 分类浏览 / 搜索点进来, 展示海报 + 简介 + 全集网格,
/// 点选集 → 经 VodParseService 解析 (若源带 parseKey) 后跳内置播放器.
class VodDetailPage extends ConsumerWidget {
  const VodDetailPage({super.key, required this.vodId, this.title});

  final String vodId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vodDetailProvider(vodId));
    final source = ref.watch(vodSourceRegistryProvider).activeSource;

    return Scaffold(
      backgroundColor: context.bgBase,
      appBar: AppBar(
        backgroundColor: context.bgBase,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.fgMain),
          onPressed: () => context.pop(),
        ),
        title: Text(
          title ?? '详情',
          style: TextStyle(color: context.fgMain, fontSize: 18, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // 当前源提示 (点它回分类页切源).
          InkWell(
            onTap: () => context.pop(),
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.video_library_rounded, color: context.fgSub, size: 16),
                  const SizedBox(width: 4),
                  Text(source.name,
                      style: TextStyle(color: context.fgSub, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => Center(
            child: CircularProgressIndicator(color: context.fgSub, strokeWidth: 2)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('加载失败', style: TextStyle(color: context.fgSub, fontSize: 13)),
          ),
        ),
        data: (content) {
          if (content == null) {
            return Center(
                child: Text('未找到该内容', style: TextStyle(color: context.fgSub)));
          }
          final episodes = content.episodes;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // ─── 头部: 海报 + 元信息 ────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 海报
                    Container(
                      width: 110,
                      height: 156,
                      decoration: BoxDecoration(
                        color: context.bgCardHigh,
                        borderRadius: BorderRadius.circular(10),
                        image: content.hasPoster
                            ? DecorationImage(
                                image: NetworkImage(content.posterUrl!),
                                fit: BoxFit.cover,
                                onError: (_, __) {},
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(content.title,
                              style: TextStyle(
                                  color: context.fgMain,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          if (content.subtitle != null &&
                              content.subtitle!.isNotEmpty)
                            Text(content.subtitle!,
                                style: TextStyle(
                                    color: context.fgSub, fontSize: 12)),
                          if (content.year != null && content.year!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('${content.year}',
                                style: TextStyle(
                                    color: context.fgSub, fontSize: 12)),
                          ],
                          if (content.rating != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star_rounded,
                                    color: Colors.amber, size: 16),
                                const SizedBox(width: 3),
                                Text(content.displayRating,
                                    style: TextStyle(
                                        color: context.fgMain, fontSize: 13)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ─── 简介 ──────────────────────────────────────
              if (content.description != null &&
                  content.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    content.description!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.fgSub, fontSize: 13, height: 1.5),
                  ),
                ),
              // ─── 选集标题 ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  episodes.isEmpty ? '播放' : '选集 (${episodes.length})',
                  style: TextStyle(
                      color: context.fgMain,
                      fontSize: 15,
                      fontWeight: FontWeight.w900),
                ),
              ),
              // ─── 选集网格 / 单集直跳 ──────────────────────
              if (episodes.isEmpty)
                _SinglePlayButton(content: content)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.6,
                    ),
                    itemCount: episodes.length,
                    itemBuilder: (_, i) {
                      final ep = episodes[i];
                      return _EpisodeTile(episode: ep, vodId: vodId);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 单集按钮 — 点按解析(若有 parseKey)后跳播放器.
class _EpisodeTile extends ConsumerStatefulWidget {
  const _EpisodeTile({required this.episode, required this.vodId});
  final Episode episode;
  final String vodId;

  @override
  ConsumerState<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends ConsumerState<_EpisodeTile> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final source = ref.read(vodSourceRegistryProvider).activeSource;
      var url = widget.episode.url;
      if (source.parseKey != null) {
        final rule =
            ref.read(vodParseRegistryProvider).byName(source.parseKey);
        if (rule != null) {
          url = await ref
              .read(vodParseServiceProvider)
              .resolve(widget.episode.url, rule: rule);
        }
      }
      if (mounted) {
        context.go(
          '/player/vod?url=${Uri.encodeComponent(url)}'
          '&title=${Uri.encodeComponent(widget.episode.name)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _play,
      child: LiquidGlassContainer(
        variant: LiquidGlassVariant.light,
        borderRadius: 10,
        padding: EdgeInsets.zero,
        child: Center(
          child: _busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: context.fgSub),
                )
              : Text(
                  widget.episode.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.fgMain, fontSize: 12, fontWeight: FontWeight.w500),
                ),
        ),
      ),
    );
  }
}

/// 无分集 (单一直播/单文件) — 直接跳播放.
class _SinglePlayButton extends ConsumerWidget {
  const _SinglePlayButton({required this.content});
  final Content content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = content.sourceUrls.isNotEmpty
        ? content.sourceUrls.first
        : (content.episodes.isNotEmpty ? content.episodes.first.url : null);
    if (url == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text('暂无可用播放地址', style: TextStyle(color: context.fgSub)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () async {
          final source = ref.read(vodSourceRegistryProvider).activeSource;
          var finalUrl = url;
          if (source.parseKey != null) {
            final rule =
                ref.read(vodParseRegistryProvider).byName(source.parseKey);
            if (rule != null) {
              finalUrl = await ref
                  .read(vodParseServiceProvider)
                  .resolve(url, rule: rule);
            }
          }
          if (context.mounted) {
            context.go(
              '/player/vod?url=${Uri.encodeComponent(finalUrl)}'
              '&title=${Uri.encodeComponent(content.title)}',
            );
          }
        },
        child: LiquidGlassContainer(
          variant: LiquidGlassVariant.light,
          borderRadius: 14,
          tint: context.fgAccent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: const SizedBox(
            width: double.infinity,
            child: Center(
              child: Text('立即播放',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}
