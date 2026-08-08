import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 优先 IPv4、IPv4 不可达时回退 IPv6 的 http.Client, 兼顾两类网络:
///   - 纯 IPv4-only 老路由器 (AAAA 假地址会卡死)
///   - 移动宽带等 IPv6 环境 (部分 CDN 无 A 记录, 硬强制 IPv4 会全站加载失败)
///
/// Dart 默认 `http.Client()` 用 happy-eyeballs (IPv6 优先 + IPv4 fallback):
/// - 移动数据 (4G/5G): 双栈, 看起来工作
/// - wifi 路由器 (IPv4-only): 解析到 IPv6 地址卡死, 用户"必须连手机流量"
///
/// 通过给 [HttpClient.connectionFactory] 装一个连接工厂 (先解析 IPv4/IPv6,
/// 优先连 IPv4, IPv4 失败再连 IPv6), 兼顾 IPv4-only 路由器与 IPv6 环境.
///
///
/// 之前 IPv4Client 是 opt-in (各 source 自己 new IPv4Client()), 容易漏改.
/// 现在 [defaultEnabled] 恒为 true, [Ipv4HttpOverrides] 可装到
///   - 国内 wifi / 4G IPv6 路由策略不统一,  DNS AAAA 经常返回 IPv6 但
///     实际连不上 (TCP RST / timeout),  happy-eyeballs 要等 1-5s 才
///   - 优先 IPv4 → 切频道到首帧的"硬延迟"砍半 (1-2s → 0.3-0.8s).
class IPv4Client extends http.BaseClient {
  IPv4Client({Duration? timeout})
      : _timeout = timeout ?? const Duration(seconds: 30) {
    _httpClient = _createHttpClient();
    _ioClient = IOClient(_httpClient);
  }

  /// 给 main.dart / tests 留个"明确意图"接口, 方便 grep + 日志.
  static const bool defaultEnabled = true;

  final Duration _timeout;
  late final HttpClient _httpClient;
  late final IOClient _ioClient;

  /// 构造一个内部 HttpClient, [connectionFactory] 强制只走 IPv4.
  ///
  /// 共享给 [Ipv4HttpOverrides.createHttpClient], 避免重复实现.
  ///
  /// 内部递归 → 启动栈溢出 (Stack Overflow at HttpOverrides.current, 25 层+).
  /// 根因: Ipv4HttpOverrides.createHttpClient 调本方法, 本方法内部 `HttpClient()`
  /// 又被刚装的 HttpOverrides 拦截 → 无限递归.  构造前临时清掉 global,
  /// finally 恢复.
  static HttpClient createForcedIpv4HttpClient() {
    final prev = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      final client = HttpClient();
      client.connectionFactory = preferIpv4ConnectionFactory;
      return client;
    } finally {
      HttpOverrides.global = prev;
    }
  }

  static HttpClient _createHttpClient() {
    return createForcedIpv4HttpClient();
  }

  /// 优先 IPv4, IPv4 不可用 (无 A 记录 / 连接失败 / 超时) 再回退 IPv6.
  ///
  /// 这是两类网络的最佳折中:
  ///   - **纯 IPv4-only 老路由器**: AAAA 返回假 IPv6 地址, happy-eyeballs
  ///     先试 IPv6 会卡死; 这里 IPv4 优先, 直接连上, 不踩 IPv6 黑洞.
  ///   - **移动宽带等 IPv6 环境**: 部分 CDN 只给 AAAA / A 记录缺失,
  ///     硬强制 IPv4 会抛 "No IPv4 address" 导致全站加载失败; 这里 IPv4
  ///     失败后自动回退 IPv6, 源能正常加载.
  ///
  /// 单地址 connect 超时 4s, 失败才试下一个, 避免无谓等待.
  static Future<ConnectionTask<Socket>> Function(
      Uri uri, String? proxyHost, int? proxyPort) get preferIpv4ConnectionFactory {
    return (Uri uri, String? proxyHost, int? proxyPort) async {
      if (proxyHost != null && proxyHost.isNotEmpty) {
        return ConnectionTask.fromSocket(
          Future<Socket>.error(
              const SocketException('Proxy not supported, use system')),
          () {},
        );
      }
      final addrs =
          await InternetAddress.lookup(uri.host, type: InternetAddressType.any);
      final v4 =
          addrs.where((a) => a.type == InternetAddressType.IPv4).toList();
      final v6 =
          addrs.where((a) => a.type == InternetAddressType.IPv6).toList();
      for (final list in <List<InternetAddress>>[v4, v6]) {
        for (final addr in list) {
          final pending = Socket.connect(addr, uri.port);
          try {
            final socket = await pending.timeout(const Duration(seconds: 4));
            // fromSocket 收的是 Future<Socket> 而非 Socket, 别直接传 await 结果.
            return ConnectionTask.fromSocket(
                Future<Socket>.value(socket), () {});
          } on SocketException {
            // 试下一个地址
          } on TimeoutException {
            // 超时后底层 connect 仍可能成功, 丢弃前必须 destroy, 否则泄漏 fd.
            unawaited(pending.then((s) => s.destroy(), onError: (_) {}));
          }
        }
      }
      throw SocketException('无法连接 ${uri.host}: 无可用 IPv4/IPv6 地址');
    };
  }

  /// 强制仅 IPv4 (老行为). 仅用于"设置 → 网络模式 → 强制 IPv4",
  /// 适配纯 IPv4-only 老路由器. 普通网络请用 [preferIpv4ConnectionFactory].
  static Future<ConnectionTask<Socket>> Function(
      Uri uri, String? proxyHost, int? proxyPort) get forceOnlyIpv4ConnectionFactory {
    return (Uri uri, String? proxyHost, int? proxyPort) async {
      if (proxyHost != null && proxyHost.isNotEmpty) {
        return ConnectionTask.fromSocket(
          Future<Socket>.error(
              const SocketException('Proxy not supported, use system')),
          () {},
        );
      }
      final addrs = await InternetAddress.lookup(uri.host,
          type: InternetAddressType.IPv4);
      if (addrs.isEmpty) {
        throw SocketException('No IPv4 address for ${uri.host}');
      }
      return ConnectionTask.fromSocket(
        Socket.connect(addrs.first, uri.port),
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

/// 强制仅 IPv4 的 HttpOverrides — 对应"设置 → 网络模式 → 强制 IPv4".
///
/// 仅用于纯 IPv4-only 老路由器 (happy-eyeballs 试 IPv6 会卡死) 的用户.
/// 普通网络请用 [Ipv4HttpOverrides] (优先 IPv4 + IPv6 兜底).
class ForceIpv4HttpOverrides extends HttpOverrides {
  ForceIpv4HttpOverrides();

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final prev = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      final client = HttpClient();
      client.connectionFactory = IPv4Client.forceOnlyIpv4ConnectionFactory;
      return client;
    } finally {
      HttpOverrides.global = prev;
    }
  }
}
