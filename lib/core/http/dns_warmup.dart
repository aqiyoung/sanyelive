import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// v0.3.7+50 (6/19) — DNS + TCP 预热, 砍首切频道 "硬延迟".
///
/// ## 问题
///
/// 用户首次点频道时, 播放栈要按顺序:
///   1. DNS lookup (AAAA + A, happy-eyeballs)         ~100-300ms
///   2. TCP handshake (3 次握手)                        ~50-200ms (国内 RTT)
///   3. TLS handshake (HTTPS 源)                        ~100-300ms
///   4. GET .m3u8                                       ~100-500ms
///   5. parse .m3u8 + GET 第一个 .ts                    ~200-1000ms
///
/// 1-3 是 "硬延迟" — 跟用户网络强相关, 没法业务层优化.  但可以 **在用户
/// 还在看 home_page 时**提前跑一遍, 让 DNS + TCP 缓存命中 OS 内核的
/// socket table, 真正切频道时这步直接跳过.
///
/// ## 实现
///
/// [warmup] 接受一组 hostnames,  对每个开一个 `Socket.connect(host, 80)`
/// 测试连通性.  成功 → 立即关掉 socket (只保留 TCP 状态缓存).  失败 /
/// 超时 → 吞掉, 不影响主流程.
///
/// ## 怎么用
///
/// ```dart
/// // main.dart 启动时
/// unawaited(DnsWarmup.warmup(['ldncctvwbcdtxy.liveplay.myqcloud.com', ...]));
/// ```
///
/// 用 `unawaited()` 是因为这是 fire-and-forget 优化,  不阻塞首屏.
/// 即便失败也不影响功能 — 用户切频道时还会走正常路径, 慢但能工作.
class DnsWarmup {
  DnsWarmup._();

  /// 单 host 预热超时.  太长反而拖垮冷启动,  太短又预热不到位.
  /// 6/19 实测国内热 host DNS + TCP 一般 < 500ms,  1.5s 留 3x 缓冲.
  static const Duration _perHostTimeout = Duration(milliseconds: 1500);

  /// 全部 host 预热整体超时 (防止某 host 一直 pending 拖累 memory).
  /// 5s 之内必须全部结束,  否则放弃等结果.
  static const Duration _overallTimeout = Duration(seconds: 5);

  /// 预热一组 host 的 DNS + TCP 链路.  不会抛异常, 不会阻塞.
  ///
  /// [hostnames] 允许包含重复 / 非法 host — 内部会 dedup + 用 Uri.tryParse
  /// 过滤.  返回 [WarmupReport] 含成功 / 失败列表, 给日志分析用.
  static Future<WarmupReport> warmup(List<String> hostnames) async {
    final stopwatch = Stopwatch()..start();
    // 1) dedup + filter
    final unique = <String>{
      for (final h in hostnames)
        if (h.trim().isNotEmpty) h.trim().toLowerCase(),
    };
    if (unique.isEmpty) {
      return const WarmupReport(success: [], failed: [], skipped: 0);
    }

    // 2) 整体超时: 用 .timeout() 包住, 超时后 fire-and-forget 关闭 socket.
    //    不能用 Completer — 要保持 warmup() 返回值可被 await.
    final futures = unique.map(_warmupOne).toList(growable: false);
    final results = await Future.wait(futures).timeout(
      _overallTimeout,
      onTimeout: () {
        // 超时 → 把没完成的视作失败 (但 socket 还在 background 关).
        return unique
            .map((h) => WarmupResult(
                  host: h,
                  ok: false,
                  error: 'overall timeout after ${_overallTimeout.inSeconds}s',
                ))
            .toList(growable: false);
      },
    );

    final success = <String>[];
    final failed = <({String host, String error})>[];
    for (final r in results) {
      if (r.ok) {
        success.add(r.host);
      } else {
        failed.add((host: r.host, error: r.error ?? 'unknown'));
      }
    }
    stopwatch.stop();
    final report = WarmupReport(
      success: success,
      failed: failed,
      skipped: hostnames.length - unique.length,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    // dev 模式打印,  生产 release 不污染 logcat.
    if (kDebugMode) {
      debugPrint('DnsWarmup: ${success.length} ok, '
          '${failed.length} fail, ${report.skipped} skipped, '
          '${report.elapsedMs}ms');
      for (final f in failed) {
        debugPrint('  - ${f.host}: ${f.error}');
      }
    }
    return report;
  }

  /// 单 host 预热: Socket.connect + 立刻 close.  任何异常吞掉, 返回 ok=false.
  static Future<WarmupResult> _warmupOne(String host) async {
    try {
      final socket = await Socket.connect(host, 80).timeout(_perHostTimeout);
      // 立刻关闭: 目的只是让 OS 把 DNS + TCP 状态缓存下来, 不真传数据.
      // v0.3.8+169: catch close 异常, 避免 unhandled exception.
      try {
        await socket.close();
      } catch (_) {}
      return WarmupResult(host: host, ok: true);
    } on SocketException catch (e) {
      return WarmupResult(host: host, ok: false, error: 'SocketException: $e');
    } on TimeoutException {
      return WarmupResult(
          host: host,
          ok: false,
          error: 'timeout ${_perHostTimeout.inMilliseconds}ms');
    } catch (e) {
      return WarmupResult(host: host, ok: false, error: e.toString());
    }
  }
}

/// 单 host 预热结果.  @visibleForTesting 是因为只给 [warmup] 内部聚合用.
@immutable
class WarmupResult {
  const WarmupResult({required this.host, required this.ok, this.error});
  final String host;
  final bool ok;
  final String? error;
}

/// 一次 [DnsWarmup.warmup] 调用的聚合报告.
@immutable
class WarmupReport {
  const WarmupReport({
    required this.success,
    required this.failed,
    required this.skipped,
    this.elapsedMs = 0,
  });

  final List<String> success;
  final List<({String host, String error})> failed;
  final int skipped;
  final int elapsedMs;

  int get total => success.length + failed.length;

  bool get allOk => failed.isEmpty;

  @override
  String toString() => 'WarmupReport(${success.length}/${total} ok, '
      '${failed.length} fail, ${skipped} skipped, ${elapsedMs}ms)';
}
