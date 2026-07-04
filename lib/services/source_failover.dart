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

/// 抽象的"打开一个流"接口
/// - 真实实现: [MediaKitStreamOpener] 调用 media_kit
/// - 测试实现: 注入 mock, 返回 `true` (成功) / `false` (失败) / `Future.error(...)`
abstract class StreamOpener {
  /// 尝试打开 [url], 返回是否成功
  ///
  /// 抛出:
  ///   - [TimeoutException] 表示超时
  ///   - 其他异常表示协议/网络层错误
  Future<bool> open(String url, {required Duration timeout});

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
    this.perSourceTimeout = const Duration(milliseconds: 1500),
  }) : _opener = opener;

  final StreamOpener _opener;
  final Duration perSourceTimeout;

  /// v0.3.10.17: 暴露 opener 给子类 (SmartSourceFailover)
  StreamOpener get opener => _opener;

  /// 尝试打开 [sources] 中的源, 按顺序, 每个最多 [perSourceTimeout]
  ///
  /// 返回第一个成功的源 URL; 全部失败抛 [AllSourcesFailedException]
  ///
  /// [onAttempt] 在每次开始尝试新源时同步触发, 用于 UI 反馈
  Future<String> play(
    List<String> sources, {
    void Function(SourceAttemptEvent event)? onAttempt,
  }) async {
    if (sources.isEmpty) {
      throw const AllSourcesFailedException([]);
    }

    final attempts = <_SourceAttempt>[];

    for (var i = 0; i < sources.length; i++) {
      final url = sources[i];
      onAttempt?.call(
        SourceAttemptEvent(index: i + 1, total: sources.length, url: url),
      );
      try {
        final ok = await _opener.open(url, timeout: perSourceTimeout);
        if (ok) return url;
        attempts.add(
          _SourceAttempt(
              index: i + 1, url: url, error: 'opener returned false'),
        );
      } on TimeoutException {
        await _opener.cancel(url); // v0.3.8+169: 超时后清理资源
        attempts.add(
          _SourceAttempt(
            index: i + 1,
            url: url,
            error: 'timeout after ${perSourceTimeout.inMilliseconds}ms',
          ),
        );
      } catch (e) {
        await _opener.cancel(url); // v0.3.8+169: 失败后清理资源
        attempts.add(
          _SourceAttempt(
            index: i + 1,
            url: url,
            error: e.toString(),
          ),
        );
      }
    }

    throw AllSourcesFailedException(
      attempts.map((a) => (url: a.url, error: a.error)).toList(growable: false),
    );
  }

  /// 6/17 v0.2.3 P0-4: 手动指定单源播放,  不走自动切换
  ///
  /// 返回是否成功.  成功条件跟 [play] 一致: opener 返回 true.
  Future<bool> playSingle(String url) async {
    try {
      return await _opener.open(url, timeout: perSourceTimeout);
    } catch (_) {
      return false;
    }
  }
}
