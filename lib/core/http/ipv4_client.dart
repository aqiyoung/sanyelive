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
class IPv4Client extends http.BaseClient {
  IPv4Client({Duration? timeout})
      : _timeout = timeout ?? const Duration(seconds: 30) {
    _httpClient = _createHttpClient();
    _ioClient = IOClient(_httpClient);
  }

  final Duration _timeout;
  late final HttpClient _httpClient;
  late final IOClient _ioClient;

  static HttpClient _createHttpClient() {
    final client = HttpClient();
    // 关键: 用 connectionFactory 强制只走 IPv4
    // (HttpClient 没有 setAddresses, addresses 是 getter)
    client.connectionFactory =
        (Uri uri, String? proxyHost, int? proxyPort) async {
      // 直接 (不通过代理) 时, 用 IPv4 解析域名 + 连
      if (proxyHost == null || proxyHost.isEmpty) {
        // 先 IPv4 解析
        final addrs = await InternetAddress.lookup(uri.host,
            type: InternetAddressType.IPv4);
        if (addrs.isEmpty) {
          throw SocketException('No IPv4 address for ${uri.host}');
        }
        // 取第一个 IPv4 解析结果去 connect
        return Socket.connect(addrs.first, uri.port);
      }
      // 走代理时仍用默认行为 (返回 null = 用 HttpClient 默认连接逻辑)
      throw 'use default';
    };
    return client;
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
