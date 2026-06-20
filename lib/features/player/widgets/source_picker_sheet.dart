import 'package:flutter/material.dart';

import '../../../core/theme/typography.dart';
import '../../../data/models/channel.dart';
import '../../../data/source_dispatcher.dart';

/// 6/17 v0.2.3 P0-4: 错误时给用户「换源」入口 — 弹底部 sheet,
/// 列出 channel 的所有 source URL,  选完返回该 URL (null = 取消).
///
/// v0.3.5.3 (6/18) 改: 用 [SourceDispatcher.dispatch] 拿排序后的 sources,
/// 跟播放器用的顺序一致 (CCTV 频道 cctvSource 排前).  另外 UI 上把
/// cctvSource 用 🇨🇳 标签突出, iptv-org/known_sources 用普通标签.
Future<String?> pickSourceUrl(BuildContext context, Channel channel) async {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SourcePickerContent(channel: channel),
  );
}

class _SourcePickerContent extends StatelessWidget {
  const _SourcePickerContent({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    // v0.3.5.3: 用 dispatcher 拿排序后的 sources (CCTV 频道 cctvSource 优先)
    final sources = SourceDispatcher.dispatch(channel);
    final isCctv = CctvSourcePicker.isCctvMainChannel(channel);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择播放源', style: IptvTypography.serifTitle),
                  const SizedBox(height: 4),
                  Text(
                    '${channel.displayName} · ${sources.length} 个候选源'
                    '${isCctv ? ' (CCTV 优先)' : ''}',
                    style: IptvTypography.caption,
                  ),
                ],
              ),
            ),
            // v0.3.8+99 (6/20 14:03 老板反馈): 删 divider, 用 SizedBox 16 代替.
            const SizedBox(height: 16),
            Flexible(
              child: sources.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('该频道暂无播放源')),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: sources.length,
                      itemBuilder: (context, i) {
                        final url = sources[i];
                        // v0.3.5.3: cctvSource 加标签
                        final isCctvSrc = channel.cctvSource.contains(url);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.12),
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                            child: Text('${i + 1}'),
                          ),
                          title: Text(
                            url,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: IptvTypography.caption.copyWith(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: isCctvSrc
                              ? Text(
                                  'CCTV 源 · 健康分 ${(CctvSourcePicker.healthScore(url) * 100).round()}%',
                                  style: IptvTypography.caption.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 10,
                                  ),
                                )
                              : null,
                          trailing: Icon(
                            Icons.play_arrow_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onTap: () => Navigator.of(context).pop(url),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
