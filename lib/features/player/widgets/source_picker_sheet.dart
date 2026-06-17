import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/channel.dart';

/// 6/17 v0.2.3 P0-4: 错误时给用户「换源」入口 — 弹底部 sheet,
/// 列出 channel 的所有 source URL,  选完返回该 URL (null = 取消).
Future<String?> pickSourceUrl(BuildContext context, Channel channel) async {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: IptvColors.bgElevated,
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
    final sources = channel.sources;
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
                  color: IptvColors.dividerWarm,
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
                    '${channel.displayName} · ${sources.length} 个候选源',
                    style: IptvTypography.caption,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
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
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: IptvColors.accentTerracotta
                                .withOpacity(0.12),
                            foregroundColor: IptvColors.accentTerracotta,
                            child: Text('${i + 1}'),
                          ),
                          title: Text(
                            url,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: IptvTypography.caption.copyWith(
                              fontSize: 12,
                              color: IptvColors.textPrimary,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.play_arrow_rounded,
                            color: IptvColors.accentTerracotta,
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
