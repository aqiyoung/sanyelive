import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'ipv4_client.dart';

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
            fileService: _Ipv4FileService(),
          ),
        );
}

class _Ipv4FileService extends HttpFileService {
  _Ipv4FileService() : super(httpClient: _createIpv4Client());

  static http.Client _createIpv4Client() {
    final prev = HttpOverrides.current;
    HttpOverrides.global = null;
    HttpClient client;
    try {
      client = HttpClient();
      // 复用 IPv4Client 的"优先 IPv4 + IPv6 兜底"连接工厂,
      // 与全局 HttpOverrides 行为一致 (修复移动宽带图片加载不出来).
      client.connectionFactory = IPv4Client.preferIpv4ConnectionFactory;
    } finally {
      HttpOverrides.global = prev;
    }
    return IOClient(client);
  }
}
