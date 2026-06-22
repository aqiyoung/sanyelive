import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/ipv4_client.dart';
import '../models/epg.dart';

/// 51zmt XMLTV 数据源 (http://epg.51zmt.top:8000/e.xml.gz).
///
/// v0.3.10 (6/23): 真实 EPG 数据, ~1MB, 102 频道, 当天 00:00 → 后天 02:00
/// (北京时间, 时区后缀 `+0800`).
///
/// 历史上有人用 gzip 拉, 但 51zmt 的 CDN (s.102031.xyz) 现在直接返
/// plain XML. 本实现兼容两种: 首字节 `1f 8b` (gzip magic) 才 gunzip,
/// 否则当纯文本. 老板 6/23 反馈 "不应该拉真实的实时数据吗" 之前 +
/// 93 占位 EPG 永远不准, 现在换成 51zmt 真实数据.
///
/// Channel.id 映射:
///   - iptv-app 的 channel.id 是 iptv-org 字符串 (`CCTV1.cn`, `CCTV16.cn`)
///   - 51zmt 用数字字符串 (`1`, `16`)
///   - 见 [XmltvEpgSource.mapChannelIdToEpg].
class XmltvEpgSource {
  XmltvEpgSource({http.Client? client, this.endpoint = _defaultEndpoint})
      : _client = client ?? IPv4Client();

  static const String _defaultEndpoint = 'http://epg.51zmt.top:8000/e.xml.gz';

  final http.Client _client;
  final String endpoint;

  /// 拉取 XMLTV. 30s 超时.
  /// CDN 现在返 plain XML; 历史上返 gzip. 本方法兼容两种.
  Future<String> fetchXml() async {
    final resp = await _client.get(
      Uri.parse(endpoint),
      headers: const {'Accept-Encoding': 'gzip'},
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} from $endpoint');
    }
    final bodyBytes = resp.bodyBytes;
    if (bodyBytes.length >= 2 &&
        bodyBytes[0] == 0x1f &&
        bodyBytes[1] == 0x8b) {
      // gzip magic number — 解压
      return gzip.decode(bodyBytes);
    }
    // plain XML
    return utf8.decode(bodyBytes, allowMalformed: true);
  }

  /// 解析 XMLTV, 按 channel.id 分组 EpgEntry 列表.
  ///
  /// 格式:
  /// ```xml
  /// <programme start="20260623060000 +0800" stop="20260623083600 +0800" channel="1">
  ///   <title>朝闻天下</title>
  /// </programme>
  /// ```
  ///
  /// 时间解析: YYYYMMDDHHMMSS +0800 → 减时区偏移到 UTC → toLocal(),
  /// 跟 `now_next_program.dart` 的 `DateTime.now()` (local) 对齐.
  Future<Map<String, List<EpgEntry>>> parseXml(String xml) async {
    final entries = <String, List<EpgEntry>>{};

    // <programme start="..." stop="..." channel="..."><title...>...</title>
    // 注意: 51zmt 的 <title> 没 lang 属性, 但允许 lang="zh" 也匹配 (用 [^>]*).
    final progRegex = RegExp(
      r'<programme\s+start="(\d{14})\s*([+-]\d{4})"\s+'
      r'stop="(\d{14})\s*([+-]\d{4})"\s+'
      r'channel="([^"]+)"[^>]*>\s*'
      r'<title[^>]*>([^<]+)</title>',
      multiLine: true,
    );

    for (final m in progRegex.allMatches(xml)) {
      try {
        final start = _parseXmltvTime(m.group(1)!, m.group(2)!);
        final end = _parseXmltvTime(m.group(3)!, m.group(4)!);
        final chId = m.group(5)!;
        final title = _decodeEntities(m.group(6)!.trim());
        if (title.isEmpty) continue;
        // 防呆: start >= end 跳过
        if (!end.isAfter(start)) continue;
        entries.putIfAbsent(chId, () => []).add(EpgEntry(
          channelId: chId,
          title: title,
          start: start,
          end: end,
        ));
      } catch (_) {
        // skip invalid entry — 不让一条脏数据炸整次解析
      }
    }

    // 按 start 排序 (51zmt 已按频道 + 时间排, 但安全起见)
    for (final list in entries.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return entries;
  }

  /// XMLTV 时间格式 `YYYYMMDDHHMMSS +0800` → DateTime (LOCAL).
  ///
  /// 算法: 构造 UTC 时间, 减时区偏移得到真实 UTC, 再 `.toLocal()` 转本地.
  /// 这跟 v0.3.9+3 修过的占位 EPG (`DateTime.now()` local) 一致, 也跟
  /// `now_next_program.dart` 的 `DateTime.now().toUtc()` 比较逻辑一致
  /// (entries 是 local, 比较前 .toUtc() 等价).
  DateTime _parseXmltvTime(String ts, String tz) {
    final y = int.parse(ts.substring(0, 4));
    final mo = int.parse(ts.substring(4, 6));
    final d = int.parse(ts.substring(6, 8));
    final h = int.parse(ts.substring(8, 10));
    final mi = int.parse(ts.substring(10, 12));
    final s = int.parse(ts.substring(12, 14));
    final tzH = int.parse(tz.substring(1, 3));
    final tzM = int.parse(tz.substring(3, 5));
    final sign = tz.startsWith('+') ? 1 : -1;
    // 减掉时区偏移得到 UTC, 再 toLocal
    final utc = DateTime.utc(y, mo, d, h, mi, s)
        .subtract(Duration(hours: sign * tzH, minutes: sign * tzM));
    return utc.toLocal();
  }

  /// 反转义 XML 实体 (`&amp;` → `&`, `&lt;` → `<`, etc).
  String _decodeEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  /// 把 iptv-org channel.id 映射到 51zmt 的 channel.id.
  ///
  /// - `CCTV1.cn` → `1`
  /// - `CCTV5Plus.cn` → `5` (51zmt 没 `+`, 取前缀数字)
  /// - `CCTV16.cn` → `16` (CCTV-16 奥林匹克 4K)
  /// - `HunanTV.cn` → `HunanTV` (剥 `.cn`, 51zmt 也用同名 id)
  /// - 失败返 `null` (caller 用占位 fallback).
  static String? mapChannelIdToEpg(String iptvOrgId) {
    final m = RegExp(r'CCTV(\d+)').firstMatch(iptvOrgId);
    if (m != null) return m.group(1);
    if (iptvOrgId.endsWith('.cn')) {
      return iptvOrgId.substring(0, iptvOrgId.length - 3);
    }
    return null;
  }

  void close() => _client.close();
}