import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 强制 IPv4 的 http.Client, 修复 wifi 路由器只支持 IPv4 时连不上的问题.
///
/// Dart 默认 `http.Client()` 用 happy-eyeballs (IPv6 优先 + IPv4 fallback):
/// - 移动数据 (4G/5G): 双栈, 看起来工作
/// - wifi 路由器 (IPv4-only): 解析到 IPv6 地址卡死, 用户"必须连手机流量"
///
/// 通过给 [HttpClient.connectionFactory] 装一个 IPv4-only 的 [ConnectionTask]
/// (先把域名解析成 IPv4 地址, 再用 Socket.connect), 强制走 IPv4.
///
/// ## v0.3.7+50 (6/19) — 默认开
///
/// 之前 IPv4Client 是 opt-in (各 source 自己 new IPv4Client()), 容易漏改.
/// 现在 [defaultEnabled] 恒为 true, [Ipv4HttpOverrides] 可装到
/// `HttpOverrides.global` 一键全 APP 生效.  理由 (老板 6/19 "加载有点慢"
/// 反馈 + 6/18 卡 6 实测):
///   - 国内 wifi / 4G IPv6 路由策略不统一,  DNS AAAA 经常返回 IPv6 但
///     实际连不上 (TCP RST / timeout),  happy-eyeballs 要等 1-5s 才
///     降级到 IPv4, 用户体感是"切频道卡 1-2 秒".
///   - 强制 IPv4 → 切频道到首帧的"硬延迟"砍半 (1-2s → 0.3-0.8s).
class IPv4Client extends http.BaseClient {
  IPv4Client({Duration? timeout})
      : _timeout = timeout ?? const Duration(seconds: 30) {
    _httpClient = _createHttpClient();
    _ioClient = IOClient(_httpClient);
  }

  /// v0.3.7+50 (6/19): 是否默认用 IPv4 — 恒为 true, 保留 const 字段是
  /// 给 main.dart / tests 留个"明确意图"接口, 方便 grep + 日志.
  static const bool defaultEnabled = true;

  final Duration _timeout;
  late final HttpClient _httpClient;
  late final IOClient _ioClient;

  /// 构造一个内部 HttpClient, [connectionFactory] 强制只走 IPv4.
  ///
  /// 共享给 [Ipv4HttpOverrides.createHttpClient], 避免重复实现.
  ///
  /// v0.3.8+178 (6/23): 加 try/finally 包 HttpOverrides, 避免 Ipv4HttpOverrides
  /// 内部递归 → 启动栈溢出 (Stack Overflow at HttpOverrides.current, 25 层+).
  /// 根因: Ipv4HttpOverrides.createHttpClient 调本方法, 本方法内部 `HttpClient()`
  /// 又被刚装的 HttpOverrides 拦截 → 无限递归.  构造前临时清掉 global,
  /// finally 恢复.
  static HttpClient createForcedIpv4HttpClient() {
    final prev = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      final client = HttpClient();
      client.connectionFactory = _ipv4ConnectionFactory;
      return client;
    } finally {
      HttpOverrides.global = prev;
    }
  }

  static HttpClient _createHttpClient() {
    return createForcedIpv4HttpClient();
  }

  /// IPv4-only connection factory: 先解析 IPv4 地址, 再 Socket.connect.
  ///
  /// 返回类型 `Future<ConnectionTask<Socket>>` (跟 HttpClient.connectionFactory
  /// 签名对齐), 用 ConnectionTask.fromSocket 包 Socket.connect 异步结果.
  /// 走代理时返回 null, 让 HttpClient 用默认行为 (Dart 会 fallback 到代理).
  static Future<ConnectionTask<Socket>> Function(
      Uri uri, String? proxyHost, int? proxyPort) get _ipv4ConnectionFactory {
    return (Uri uri, String? proxyHost, int? proxyPort) async {
      if (proxyHost == null || proxyHost.isEmpty) {
        final addrs = await InternetAddress.lookup(uri.host,
            type: InternetAddressType.IPv4);
        if (addrs.isEmpty) {
          throw SocketException('No IPv4 address for ${uri.host}');
        }
        return ConnectionTask.fromSocket(
          Socket.connect(addrs.first, uri.port),
          () {},
        );
      }
      // 走代理时返回一个已失败的 ConnectionTask, 让 HttpClient 走系统代理.
      // 强制返回正常 ConnectionTask 会跳过代理, 跟 dart:io 设计冲突.
      return ConnectionTask.fromSocket(
        Future<Socket>.error(
            SocketException('Proxy not supported, use system')),
        () {},
      );
    };
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _ioClient.send(request).timeout(_timeout);
  }

  @override
  void close() {
    _ioClient.close();
    super.close();
  }
}

/// v0.3.7+50 (6/19) — 全局 IPv4 强制 (HttpOverrides).
///
/// 装到 `HttpOverrides.global = Ipv4HttpOverrides()` 后, **任何用 dart:io
/// HttpClient 的代码** (包括 http.Client(), dart:io 直连, package:http 默认
/// 实现, package:dio 默认实现) 都自动走 IPv4.  不需要每个 source 单独
/// 传 IPv4Client.
///
/// 装法 (lib/main.dart):
/// ```dart
/// if (IPv4Client.defaultEnabled) {
///   HttpOverrides.global = Ipv4HttpOverrides();
/// }
/// ```
///
/// 实现:  override [createHttpClient] 返回 [IPv4Client.createForcedIpv4HttpClient]
/// 构造的 HttpClient, dart:io 框架自动用 [HttpClient.connectionFactory]
/// 处理每个 socket.
///
/// 注意: [IOClient] / [IPv4Client] 这类"已经自己 new HttpClient"的 wrapper
/// 不会走 HttpOverrides (他们直接用自己持有的 HttpClient),  所以
/// `new IPv4Client()` 跟 `HttpOverrides.global` 是互补的,  不是冲突的.
class Ipv4HttpOverrides extends HttpOverrides {
  // HttpOverrides 父类没有 const 构造, 所以这里不能 const.
  Ipv4HttpOverrides();

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return IPv4Client.createForcedIpv4HttpClient();
  }
}
