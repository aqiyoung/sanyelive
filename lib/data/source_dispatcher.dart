///
///   频道的选源逻辑 (cctvSource 优先) 集中在这里, 避免散在多处.
///
/// 之前的逻辑 ([PlayerService.play] in lib/services/player_service.dart):
///   - 直接传 `channel.sources` 给 `SourceFailover.play`
///   - 不会区分 CCTV / 非 CCTV
///   - CCTV 死了就报错, 不会降级到 cctvSource
///
///   - [dispatch] 拿到 channel, 决定走 [CctvSourcePicker.pickSources] 还是
///     直接 channel.sources
///   - CCTV 主频道: cctvSource (按健康分) → sources (iptv-org) → known_sources
///   - CCTV 数字频道: sources 字段照旧 (cctvSource 字段空数组, 等价于老逻辑)
///   - 其他 channel: sources 字段照旧
///
/// 用法 (替换 player_service.dart 里的 channel.sources):
///   ```dart
///   final sources = SourceDispatcher.dispatch(
///     channel,
///     knownSources: known,
///   );
///   final source = await _failover.play(sources, ...);
///   ```
///
library;

// 重新导出放在文件最前 (Dart 要求所有 directive 在 declarations 之前)
export 'cctv_source.dart' show CctvSourcePicker, CctvSource, CctvSourceRegistry;

import 'package:flutter/foundation.dart';

import 'cctv_source.dart';
import 'models/channel.dart';

/// 播放源调度器 (单例, 纯函数)
class SourceDispatcher {
  const SourceDispatcher._();

  /// 给定 channel, 返回按优先级排序的播放源 URL 列表.
  ///
  ///   1. CCTV 主频道 (CCTV-1~17, 5+): [CctvSourcePicker.pickSources]
  ///      内部 cctvSource[0] > sources[0] > known_sources[0]
  ///   2. 其他 channel: 老逻辑 — sources + known_sources (repository 已经合并过)
  ///
  /// 返回 immutable list, 不修改 channel.
  static List<String> dispatch(
    Channel channel, {
    Map<String, List<String>> knownSources = const <String, List<String>>{},
  }) {
    if (CctvSourcePicker.isCctvMainChannel(channel)) {
      return CctvSourcePicker.pickSources(
        channel,
        knownSources: knownSources,
      );
    }
    // 非 CCTV 主频道: channel.sources 已经被 repository 合并过
    return List<String>.unmodifiable(channel.sources);
  }

  /// 调试用: 拿 channel 选源过程的完整 trace.
  /// UI 可以拿这个展示 "正在用 cctvSource[0] (Tencent Cloud), 备用 sources[0] (iptv-org)"
  @visibleForTesting
  static DispatchTrace traceDispatch(
    Channel channel, {
    Map<String, List<String>> knownSources = const <String, List<String>>{},
  }) {
    if (!CctvSourcePicker.isCctvMainChannel(channel)) {
      return DispatchTrace(
        channelId: channel.id,
        strategy: 'pass_through',
        cctvSourcesUsed: 0,
        legacySourcesUsed: channel.sources.length,
        pickedSource: channel.sources.isNotEmpty ? channel.sources.first : null,
        strategyDetail: '非 CCTV 主频道, 直接用 channel.sources (老逻辑)',
      );
    }

    final cctv = channel.cctvSource;
    final sources = channel.sources;
    final known = knownSources[channel.id] ?? const <String>[];
    final picked = CctvSourcePicker.pickSources(
      channel,
      knownSources: knownSources,
    );

    String pickedMethod;
    if (cctv.isNotEmpty && picked.isNotEmpty && picked.first == cctv.first) {
      pickedMethod = 'cctvSource[0]';
    } else if (sources.isNotEmpty &&
        picked.isNotEmpty &&
        picked.first == sources.first) {
      pickedMethod = 'sources[0] (iptv-org)';
    } else if (known.isNotEmpty) {
      pickedMethod = 'known_sources[0]';
    } else {
      pickedMethod = 'NONE (no source)';
    }

    return DispatchTrace(
      channelId: channel.id,
      strategy: 'cctv_priority',
      cctvSourcesUsed: cctv.length,
      legacySourcesUsed: sources.length + known.length,
      pickedSource: picked.isNotEmpty ? picked.first : null,
      strategyDetail: '$pickedMethod → 兜底 ${picked.length} 源',
    );
  }
}

/// 选源 trace (debug UI 用)
@immutable
class DispatchTrace {
  const DispatchTrace({
    required this.channelId,
    required this.strategy,
    required this.cctvSourcesUsed,
    required this.legacySourcesUsed,
    required this.pickedSource,
    required this.strategyDetail,
  });

  final String channelId;
  final String strategy; // "cctv_priority" | "pass_through"
  final int cctvSourcesUsed;
  final int legacySourcesUsed;
  final String? pickedSource;
  final String strategyDetail;

  @override
  String toString() =>
      'DispatchTrace($channelId, $strategy, picked: $pickedSource)';
}
