import 'package:http/http.dart' as http;

import '../models/epg.dart';

class EpgSource {
  EpgSource({http.Client? client, this.endpoint = _defaultEndpoint})
      : _client = client ?? http.Client();

  static const String _defaultEndpoint =
      'https://iptv-org.github.io/epg/guides/ar.xml.gz';

  final http.Client _client;
  final String endpoint;

  Future<List<EpgEntry>> fetchCountry(String cc) async {
    // TODO(card 5): 实现 XMLTV 解析
    throw UnimplementedError('EPG parsing deferred to card 5');
  }

  void close() => _client.close();
}
