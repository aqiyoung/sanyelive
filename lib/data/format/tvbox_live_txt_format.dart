/// TVBox live.txt 直播源格式解析器.
///
/// TVBox 直播聚合 (lives[].url 指向的 .txt) 主流格式:
///   分组名,#genre#
///   频道名,http://a.m3u8
///   频道名2,http://b.m3u8#http://c.m3u8   (多源用 # 分隔)
///   #genre#
///   另一个分组,#genre#
///   频道名3$http://...                   (名$url 写法)
///
/// 与 [M3uFormat] (#EXTM3U) / [IptvOrgJsonFormat] ([{/) 区分:
/// 本格式不以这两种开头, 且含 #genre# 或形如 "名,http" 的行.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/channel.dart';
import 'channel_format.dart';

/// 频道名+URL 行嗅探: 形如 "...,http://" / "...$http://" 等.
final _channelLineRe =
    RegExp(r'[,$]\s*(https?://|proxy://|rtmp://|rtsp://)');

/// 单段 URL 合法性 (用于过滤多源 # 分隔后的片段).
bool _urlLike(String u) =>
    u.startsWith('http://') ||
    u.startsWith('https://') ||
    u.startsWith('proxy://') ||
    u.startsWith('rtmp://') ||
    u.startsWith('rtsp://');

class TvboxLiveTxtFormat implements ChannelFormat {
  const TvboxLiveTxtFormat();

  @override
  String get id => 'tvbox_live_txt';

  @override
  String get label => 'TVBox live.txt';

  @override
  bool canParse(String content) {
    final t = content.trimLeft();
    // 让位给已注册的 m3u / json 格式 (m3u 注册表顺序在前, 这里双保险).
    if (t.toLowerCase().startsWith('#extm3u')) return false;
    if (t.startsWith('[') || t.startsWith('{')) return false;
    if (t.contains('#genre#')) return true;
    // 退一步: 至少 2 行形如 "频道名,http..." 或 "频道名\$http...".
    var hits = 0;
    for (final line in t.split('\n')) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      if (_channelLineRe.hasMatch(l)) {
        hits++;
        if (hits >= 2) return true;
      }
    }
    return false;
  }

  @override
  List<Channel> parse(String content) {
    final channels = <Channel>[];
    final seenIds = <String>{};
    var currentGroup = '未分组';

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.toLowerCase().startsWith('#extm3u')) continue;
      if (line.startsWith('#')) {
        if (line.toLowerCase().contains('#genre#')) {
          final name =
              line.substring(0, line.toLowerCase().indexOf('#genre#')).trim();
          if (name.isNotEmpty) currentGroup = name;
        }
        continue;
      }

      // 频道行: "名,url" 或 "名\$url".
      final commaIdx = line.indexOf(',');
      final dollarIdx = line.indexOf('\$');
      String name;
      String rest;
      if (commaIdx >= 0 && (dollarIdx < 0 || commaIdx < dollarIdx)) {
        name = line.substring(0, commaIdx).trim();
        rest = line.substring(commaIdx + 1).trim();
      } else if (dollarIdx >= 0) {
        name = line.substring(0, dollarIdx).trim();
        rest = line.substring(dollarIdx + 1).trim();
      } else {
        continue;
      }
      if (name.isEmpty || rest.isEmpty) continue;

      // 多源用 # 分隔; 仅保留像 URL 的片段.
      final urls = rest
          .split('#')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && _urlLike(e))
          .toList();
      if (urls.isEmpty) continue;

      final id = _makeId(name, seenIds);
      channels.add(Channel(
        id: id,
        name: name,
        country: '',
        categories: [currentGroup],
        altNames: const [],
        logoUrl: null,
        sources: urls,
      ));
    }

    if (channels.isEmpty) {
      debugPrint('TvboxLiveTxtFormat.parse: 未解析出任何频道 (内容可能不是 '
          'TVBox live.txt 格式)');
    }
    return List.unmodifiable(channels);
  }

  /// 用 name 兜底生成唯一 id, 重名追加 #n.
  String _makeId(String name, Set<String> seen) {
    var id = 'tvboxlive:$name';
    var n = 1;
    while (!seen.add(id)) {
      id = 'tvboxlive:$name#$n';
      n++;
    }
    return id;
  }
}
