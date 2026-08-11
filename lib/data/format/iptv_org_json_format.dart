/// iptv-org JSON 格式解析器 — 把现有 [Channel.fromJson] 收敛成一种 [ChannelFormat] 实现.
///
/// 兼容两种顶层结构 (与 [parseChannelsIsolate] 历史行为一致):
///   - 顶层数组:  [ {id, name, ...}, ... ]
///   - 带包裹:    { "channels": [ ... ] }
///
/// 仅做"格式适配": 真正反序列化仍走 [Channel.fromJson] (领域模型规范解析).
library;

import 'dart:convert';

import '../models/channel.dart';
import 'channel_format.dart';

class IptvOrgJsonFormat implements ChannelFormat {
  const IptvOrgJsonFormat();

  @override
  String get id => 'iptv_org_json';

  @override
  String get label => 'iptv-org JSON';

  @override
  bool canParse(String content) {
    final t = content.trimLeft();
    // 注册表顺序里 m3u 先于本格式, 这里对 JSON 宽松嗅探即可.
    return t.startsWith('[') || t.startsWith('{');
  }

  @override
  List<Channel> parse(String content) {
    final decoded = json.decode(content);
    final List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded['channels'] is List) {
      list = decoded['channels'] as List<dynamic>;
    } else {
      throw const FormatException(
        'iptv_org_json: 顶层需为 List 或 {"channels": [...]}',
      );
    }
    return list
        .map((e) => Channel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}
