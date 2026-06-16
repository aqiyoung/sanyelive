import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/epg.dart';
import '../../../data/repositories/epg_repository.dart';

/// "现在播什么 + 接下来" 节目卡
///
/// 数据来源: [epgForChannelProvider]
/// - 有 EPG 数据: 显示当前节目 (title + 进度条 + 剩余时间) + 下一档
/// - 无 EPG 数据: 退化为 "LIVE · 节目时间" 占位 (卡 6 完整 EPG)
class NowNextProgram extends ConsumerWidget {
  const NowNextProgram({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEpg = ref.watch(epgForChannelProvider(channel.id));

    return asyncEpg.when(
      loading: () => _EmptyState(channel: channel, isLoading: true),
      error: (_, __) => _EmptyState(channel: channel, isLoading: false),
      data: (entries) {
        if (entries.isEmpty) {
          return _EmptyState(channel: channel, isLoading: false);
        }
        final now = DateTime.now().toUtc();
        final current = _findCurrent(entries, now);
        final next = _findNext(entries, now);
        return _ProgramCard(
          current: current,
          next: next,
          now: now,
        );
      },
    );
  }

  EpgEntry? _findCurrent(List<EpgEntry> entries, DateTime now) {
    for (final e in entries) {
      if (!e.start.isAfter(now) && e.end.isAfter(now)) return e;
    }
    return null;
  }

  EpgEntry? _findNext(List<EpgEntry> entries, DateTime now) {
    EpgEntry? best;
    for (final e in entries) {
      if (e.start.isAfter(now)) {
        if (best == null || e.start.isBefore(best.start)) best = e;
      }
    }
    return best;
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({
    required this.current,
    required this.next,
    required this.now,
  });

  final EpgEntry? current;
  final EpgEntry? next;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IptvColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(text: '正在直播', accent: IptvColors.accentTerracotta),
          const SizedBox(height: 6),
          Text(
            current?.title ?? '暂无节目信息',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: IptvTypography.serifTitle.copyWith(fontSize: 18),
          ),
          if (current != null) ...[
            const SizedBox(height: 8),
            _ProgressBar(
              start: current!.start,
              end: current!.end,
              now: now,
            ),
            const SizedBox(height: 4),
            Text(
              '${_fmt(current!.start.toLocal())} – ${_fmt(current!.end.toLocal())}  '
              '·  剩余 ${_remaining(current!.end, now)}',
              style: IptvTypography.caption
                  .copyWith(color: IptvColors.textSecondary),
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: 12),
            _SectionLabel(
              text: '即将播出',
              accent: IptvColors.accentClay,
            ),
            const SizedBox(height: 4),
            Text(
              next!.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  IptvTypography.body.copyWith(color: IptvColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              '${_fmt(next!.start.toLocal())} – ${_fmt(next!.end.toLocal())}',
              style: IptvTypography.caption
                  .copyWith(color: IptvColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _remaining(DateTime end, DateTime now) {
    final diff = end.difference(now);
    if (diff.isNegative) return '已结束';
    if (diff.inHours > 0) {
      return '${diff.inHours} 小时 ${diff.inMinutes.remainder(60)} 分';
    }
    return '${diff.inMinutes} 分';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: IptvTypography.caption.copyWith(
            color: IptvColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar(
      {required this.start, required this.end, required this.now});
  final DateTime start;
  final DateTime end;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final total = end.difference(start).inMilliseconds;
    final done = now.difference(start).inMilliseconds.clamp(0, total);
    final pct = total == 0 ? 0.0 : done / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: pct,
        minHeight: 3,
        backgroundColor: IptvColors.dividerWarm,
        valueColor:
            const AlwaysStoppedAnimation<Color>(IptvColors.accentTerracotta),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.channel, required this.isLoading});
  final Channel channel;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IptvColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.live_tv,
            size: 18,
            color: IptvColors.accentTerracotta,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLoading ? '节目单加载中…' : '${channel.name} · 实时直播 (节目单待接入)',
              style:
                  IptvTypography.body.copyWith(color: IptvColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
