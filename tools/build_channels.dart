// Generate assets/data/channels_cn.json from iptv-org API.
//
// Usage:
//   dart run tools/build_channels.dart
//
// Reads:  https://iptv-org.github.io/api/channels.json
//         https://iptv-org.github.io/api/streams.json
// Writes: assets/data/channels_cn.json
//
// iptv-org has 39,000+ channels. We filter to CN-region mainstream
// categories and rank by priority to keep under 500 channels.
//
// Streams (m3u8 URLs) are joined from streams.json by `channel` id.
// For each channel, the first URL is the highest-quality feed. We also
// cap sources at 5 per channel to keep asset size manageable.
//
// 卡 6 补充：回填到国内的硬编码兜底 (BeijingTV/HunanTV 等 iptv-org 没覆盖的)
// 在已知表 assets/data/known_sources.json 中维护, build 时 merge 进去.
import 'dart:convert';
import 'dart:io';

const String _channelsEndpoint = 'https://iptv-org.github.io/api/channels.json';
const String _streamsEndpoint = 'https://iptv-org.github.io/api/streams.json';
const String _knownSourcesPath = 'assets/data/known_sources.json';
const String _outPath = 'assets/data/channels_cn.json';

const Set<String> _wantedCats = <String>{
  'general',
  'news',
  'sports',
  'music',
  'movies',
  'kids',
  'entertainment',
  'documentary',
  'education',
  'animation',
  'culture',
};

const Map<String, int> _catPriority = <String, int>{
  'news': 100,
  'general': 90,
  'entertainment': 80,
  'sports': 70,
  'movies': 60,
  'music': 50,
  'kids': 40,
  'documentary': 35,
  'education': 30,
  'animation': 25,
  'culture': 20,
};

final RegExp _chineseRe = RegExp(r'[\u4e00-\u9fff]');

int scoreChannel(Map<String, dynamic> c) {
  var s = 0;
  final cats = (c['categories'] as List? ?? const <String>[]).cast<String>();
  for (final cat in cats) {
    s += _catPriority[cat] ?? 0;
  }
  if (c['logo'] != null) s += 5;
  if (c['website'] != null) s += 2;
  if (_chineseRe.hasMatch(c['name'] as String? ?? '')) s += 10;
  return s;
}

bool isChinese(Map<String, dynamic> c) => c['country'] == 'CN';

Map<String, dynamic> toChannel(Map<String, dynamic> c) {
  return <String, dynamic>{
    'id': c['id'],
    'name': c['name'],
    'country': c['country'] ?? '',
    'categories': c['categories'] ?? const <String>[],
    'alt_names': c['alt_names'] ?? const <String>[],
    'website': c['website'],
    'logo': c['logo'],
    'is_nsfw': false,
  };
}

/// 把 iptv-org streams 数组压成每个 channel 一组 url 列表, 顺序: 1080p 优先, 再 720p, 再 SD.
/// 'Geo-blocked' / 'Not 24/7' 等 label 的先排除, 避免黑名单地区 (CN) 用上导致打不开.
Map<String, List<String>> indexStreamsByChannel(List<dynamic> streams) {
  // 排除已知不稳定或地域限制的标签
  const badLabels = <String>{
    'Geo-blocked',
    'Not 24/7',
    'Unstable',
  };
  const qPriority = <String, int>{
    '2160p': 500,
    '1080p': 400,
    '720p': 300,
    '576p': 200,
    '480p': 100,
  };
  final byChannel = <String, List<Map<String, dynamic>>>{};
  for (final s in streams.cast<Map<String, dynamic>>()) {
    final cid = s['channel'] as String?;
    final url = s['url'] as String?;
    if (cid == null || url == null) continue;
    final label = s['label'] as String?;
    if (label != null && badLabels.contains(label)) continue;
    byChannel.putIfAbsent(cid, () => <Map<String, dynamic>>[]).add(s);
  }
  final result = <String, List<String>>{};
  for (final entry in byChannel.entries) {
    final list = entry.value;
    list.sort((a, b) {
      final qa = qPriority[a['quality'] as String? ?? ''] ?? 0;
      final qb = qPriority[b['quality'] as String? ?? ''] ?? 0;
      if (qa != qb) return qb.compareTo(qa); // 高的在前
      // feed 优先 HD
      final fa = (a['feed'] == 'HD') ? 1 : 0;
      final fb = (b['feed'] == 'HD') ? 1 : 0;
      if (fa != fb) return fb.compareTo(fa);
      return 0;
    });
    result[entry.key] =
        list.take(5).map((m) => m['url'] as String).toList(growable: false);
  }
  return result;
}

/// 加载硬编码兜底源
Future<Map<String, List<String>>> loadKnownSources() async {
  final file = File(_knownSourcesPath);
  if (!file.existsSync()) {
    stderr.writeln('  no $_knownSourcesPath, skip fallback');
    return const <String, List<String>>{};
  }
  final raw = await file.readAsString();
  final map = json.decode(raw) as Map<String, dynamic>;
  return map.map(
    (k, v) => MapEntry(k, ((v as List).cast<String>()).toList(growable: false)),
  );
}

Future<void> main() async {
  final client = HttpClient();

  try {
    // 1. 拉 channels
    stdout.writeln('Fetching $_channelsEndpoint ...');
    final chReq = await client.getUrl(Uri.parse(_channelsEndpoint));
    final chResp = await chReq.close();
    if (chResp.statusCode != 200) {
      stderr.writeln('HTTP ${chResp.statusCode} on channels');
      exit(1);
    }
    final chBody = await chResp.transform(utf8.decoder).join();
    final all = json.decode(chBody) as List;
    stdout.writeln('Total iptv-org channels: ${all.length}');

    // 2. 拉 streams (用同样的 client, HTTPS keep-alive)
    stdout.writeln('Fetching $_streamsEndpoint ...');
    final stReq = await client.getUrl(Uri.parse(_streamsEndpoint));
    final stResp = await stReq.close();
    if (stResp.statusCode != 200) {
      stderr.writeln('HTTP ${stResp.statusCode} on streams');
      exit(1);
    }
    final stBody = await stResp.transform(utf8.decoder).join();
    final allStreams = json.decode(stBody) as List;
    stdout.writeln('Total iptv-org streams: ${allStreams.length}');
    final streamIndex = indexStreamsByChannel(allStreams);

    // 3. 加载硬编码兜底源
    final knownSources = await loadKnownSources();
    stdout.writeln(
        'Loaded known_sources fallback: ${knownSources.length} channels');

    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final c in all.cast<Map<String, dynamic>>()) {
      final id = c['id'] as String?;
      if (id == null || seen.contains(id)) continue;
      if (c['is_nsfw'] == true) continue;
      if (!isChinese(c)) continue;
      final cats =
          (c['categories'] as List? ?? const <String>[]).cast<String>();
      if (cats.isEmpty) continue;
      if (!cats.any(_wantedCats.contains)) continue;
      seen.add(id);
      final ch = toChannel(c);
      ch['_score'] = scoreChannel(c);

      // 拼装 sources: 优先 iptv-org 流的 url, 兜底用 known_sources 的
      // 去重但保留顺序
      final sources = <String>[];
      final added = <String>{};
      for (final url in streamIndex[id] ?? const <String>[]) {
        if (added.add(url)) sources.add(url);
      }
      for (final url in knownSources[id] ?? const <String>[]) {
        if (added.add(url)) sources.add(url);
      }
      ch['sources'] = sources.take(5).toList();

      out.add(ch);
    }

    out.sort(
      (a, b) => (b['_score'] as int).compareTo(a['_score'] as int),
    );
    final top = out
        .take(500)
        .map((m) => Map<String, dynamic>.from(m)..remove('_score'))
        .toList();
    top.sort((a, b) {
      final c = (a['country'] as String).compareTo(b['country'] as String);
      if (c != 0) return c;
      return (a['name'] as String).compareTo(b['name'] as String);
    });

    final withSources =
        top.where((m) => (m['sources'] as List).isNotEmpty).length;
    stdout.writeln(
      'Coverage: $withSources/${top.length} channels have ≥1 source '
      '(${(withSources / top.length * 100).toStringAsFixed(1)}%)',
    );

    final encoded = json.encode(top);
    final file = File(_outPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(encoded);

    stdout.writeln(
      'Wrote ${top.length} channels, ${encoded.length} bytes '
      '(${(encoded.length / 1024).toStringAsFixed(1)} KB) -> $_outPath',
    );

    if (top.length > 500) {
      stderr.writeln('FAIL: ${top.length} > 500');
      exit(2);
    }
    if (encoded.length > 200 * 1024) {
      stderr.writeln('FAIL: ${encoded.length} bytes > 200KB');
      exit(2);
    }
    if (withSources < 50) {
      stderr.writeln('FAIL: only $withSources channels have sources (min 50)');
      exit(2);
    }
    stdout.writeln('OK: under 500 channels and 200KB, with ≥50 sources');
  } finally {
    client.close(force: true);
  }
}
