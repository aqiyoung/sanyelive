import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class IPv4CacheManager extends CacheManager with ImageCacheManager {
  static const key = 'ipv4CachedImage';

  static IPv4CacheManager? _instance;

  factory IPv4CacheManager() {
    _instance ??= IPv4CacheManager._();
    return _instance!;
  }

  IPv4CacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 200,
            httpGetter: _Ipv4HttpGetter(),
          ),
        );
}

class _Ipv4HttpGetter extends HttpGetter {
  @override
  Future<http.StreamedResponse> get(http.BaseRequest request) {
    final prev = HttpOverrides.current;
    HttpOverrides.global = null;
    HttpClient client;
    try {
      client = HttpClient();
      client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
        if (proxyHost == null || proxyHost.isEmpty) {
          final addrs = await InternetAddress.lookup(
            uri.host,
            type: InternetAddressType.IPv4,
          );
          if (addrs.isEmpty) {
            throw SocketException('No IPv4 address for ${uri.host}');
          }
          return ConnectionTask.fromSocket(
            Socket.connect(addrs.first, uri.port),
            () {},
          );
        }
        return ConnectionTask.fromSocket(
          Future<Socket>.error(
              const SocketException('Proxy not supported, use system')),
          () {},
        );
      };
    } finally {
      HttpOverrides.global = prev;
    }

    final ioClient = IOClient(client);
    return ioClient.send(request).timeout(const Duration(seconds: 15));
  }
}
