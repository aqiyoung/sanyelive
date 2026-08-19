/// SourceFailover — 多播放源自动切换
///
/// 设计目标:
/// 1. 接受一个频道的多个候选源 URL, 按顺序尝试
/// 2. 每个源设置超时 (默认 3s), 超过就切下一个
/// 3. 任意源 open 成功立即返回, 不再尝试后续
/// 4. 全部失败时抛出 [AllSourcesFailedException], 携带每个源的失败原因
///
/// **可测试性**:
///   - [StreamOpener] 抽象了"打开一个流"的行为, 测试时可注入 mock
///   - [SourceFailover] 本身不依赖 media_kit, 纯 Dart 逻辑
///   - 超时通过 `Future.any` + `Future.delayed` 实现, 支持 `fakeAsync`
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/crash_logger.dart';

/// 抽象的"打开一个流"接口
/// - 真实实现: [MediaKitStreamOpener] 调用 media_kit
/// - 测试实现: 注入 mock, 返回 `true` (成功) / `false` (失败) / `Future.error(...)`
abstract class StreamOpener {
  /// 尝试打开 [url], 返回是否成功
  ///
  /// 抛出:
  ///   - [TimeoutException] 表示超时
  ///   - 其他异常表示协议/网络层错误
  Future<bool> open(
    String url, {
    required Duration timeout,
    bool preferSoftwareDecode = false,
  });

  /// 取消正在进行的 open 操作 (清理资源, 不抛异常).
  /// 默认 no-op, 子类可 override.
  Future<void> cancel(String url) async {}
}

/// 所有源都失败的异常
@immutable
class AllSourcesFailedException implements Exception {
  const AllSourcesFailedException(this.attempts);

  /// 每个源的尝试结果: (url, errorMessage)
  final List<({String url, String error})> attempts;

  @override
  String toString() =>
      'AllSourcesFailedException: tried ${attempts.length} source(s) — '
      '${attempts.map((a) => "${a.url} → ${a.error}").join("; ")}';
}

/// 本次播放被更新的切换打断时抛出, 上层据此丢弃结果, 不污染状态。
@immutable
class SourcePlayAbortedException implements Exception {
  const SourcePlayAbortedException();

  @override
  String toString() =>
      'SourcePlayAbortedException: superseded by a newer channel switch';
}

/// 单个源的尝试结果 (内部用, 不导出)
@immutable
class _SourceAttempt {
  const _SourceAttempt({
    required this.index,
    required this.url,
    required this.error,
  });
  final int index;
  final String url;
  final String error;
}

/// 公开的尝试事件 (用于 UI 展示 "正在尝试源 2/3")
@immutable
class SourceAttemptEvent {
  const SourceAttemptEvent({
    required this.index,
    required this.total,
    required this.url,
  });

  /// 1-based index
  final int index;
  final int total;
  final String url;
}

/// SourceFailover 主类
class SourceFailover {
  SourceFailover({
    required StreamOpener opener,
    // 6s: 给视频首帧足够时间. 央视/txiptv 等慢源起播后视频帧可能延迟出现,
    // 过短(原 1.5s)会导致正常源被误判失败. 配合 MediaKitStreamOpener 的
    // "playing + videoDimensions>0" 双保险: 不出帧的源会在 6s 后判失败切下一源.
    this.perSourceTimeout = const Duration(milliseconds: 6000),
  }) : _opener = opener;

  final StreamOpener _opener;
  final Duration perSourceTimeout;

  StreamOpener get opener => _opener;

  /// 尝试打开 [sources] 中的源, 按顺序, 每个最多 [perSourceTimeout]
  ///
  /// 返回第一个成功的源 URL; 全部失败抛 [AllSourcesFailedException]
  ///
  /// [onAttempt] 在每次开始尝试新源时同步触发, 用于 UI 反馈
  ///
  /// [shouldAbort] 若返回 true, 立即抛出 [SourcePlayAbortedException] 中止,
  /// 用于"频道切换中又切了一次"的场景 — 放弃本次, 让新切换接管.
  Future<String> play(
    List<String> sources, {
    void Function(SourceAttemptEvent event)? onAttempt,
    bool Function()? shouldAbort,
    String? label,
    bool preferSoftwareDecode = false,
  }) async {
    final tag = label != null ? ' ($label)' : '';
    if (sources.isEmpty) {
      await CrashLogger.log('failover: play EMPTY sources$tag');
      throw const AllSourcesFailedException([]);
    }
    await CrashLogger.log('failover: play START ${sources.length} source(s)$tag');

    final attempts = <_SourceAttempt>[];

    for (var i = 0; i < sources.length; i++) {
      if (shouldAbort?.call() ?? false) {
        await CrashLogger.log('failover: ABORTED before src#${i + 1}$tag');
        throw const SourcePlayAbortedException();
      }
      final url = sources[i];
      onAttempt?.call(
        SourceAttemptEvent(index: i + 1, total: sources.length, url: url),
      );
      try {
        final ok = await _opener.open(
          url,
          timeout: perSourceTimeout,
          preferSoftwareDecode: preferSoftwareDecode,
        );
        if (ok) {
          await CrashLogger.log(
              'failover: src#${i + 1}/${sources.length} OK$tag url=$url');
          return url;
        }
        await CrashLogger.log(
            'failover: src#${i + 1}/${sources.length} FAILED(opener=false)$tag url=$url');
        attempts.add(
          _SourceAttempt(
              index: i + 1, url: url, error: 'opener returned false'),
        );
      } on TimeoutException {
        await _opener.cancel(url);
        await CrashLogger.log(
            'failover: src#${i + 1}/${sources.length} TIMEOUT(${perSourceTimeout.inMilliseconds}ms)$tag url=$url');
        attempts.add(
          _SourceAttempt(
            index: i + 1,
            url: url,
            error: 'timeout after ${perSourceTimeout.inMilliseconds}ms',
          ),
        );
      } catch (e) {
        await _opener.cancel(url);
        await CrashLogger.log(
            'failover: src#${i + 1}/${sources.length} ERROR: $e$tag url=$url');
        attempts.add(
          _SourceAttempt(
            index: i + 1,
            url: url,
            error: e.toString(),
          ),
        );
      }
    }

    await CrashLogger.log('failover: ALL ${sources.length} sources FAILED$tag');
    throw AllSourcesFailedException(
      attempts.map((a) => (url: a.url, error: a.error)).toList(growable: false),
    );
  }

  ///
  /// 返回是否成功.  成功条件跟 [play] 一致: opener 返回 true.
  Future<bool> playSingle(
    String url, {
    String? label,
    bool preferSoftwareDecode = false,
  }) async {
    final tag = label != null ? ' ($label)' : '';
    try {
      final ok = await _opener.open(
        url,
        timeout: perSourceTimeout,
        preferSoftwareDecode: preferSoftwareDecode,
      );
      await CrashLogger.log(
          'failover: playSingle ${ok ? 'OK' : 'FAILED'}$tag url=$url');
      return ok;
    } catch (e) {
      await CrashLogger.log('failover: playSingle ERROR: $e$tag url=$url');
      return false;
    }
  }
}
