/// 频道格式注册表 — 按内容嗅探并选择解析器.
///
/// 用法:
///   final channels = ChannelFormatRegistry.instance.parse(rawText); // 自动选 m3u / json
///   final channels = ChannelFormatRegistry.instance.parseWith('m3u', rawText); // 指定格式
///
/// 默认注册顺序: [M3uFormat] 在前 (canParse 最具体, 精准命中 #EXTM3U),
/// 之后 [IptvOrgJsonFormat] (宽松匹配 JSON). 顺序即优先级.
library;

import 'channel_format.dart';
import 'iptv_org_json_format.dart';
import 'm3u_format.dart';

class ChannelFormatRegistry {
  ChannelFormatRegistry([List<ChannelFormat>? formats])
      : _formats = List.unmodifiable(formats ?? _defaultFormats);

  static const List<ChannelFormat> _defaultFormats = [
    M3uFormat(),
    IptvOrgJsonFormat(),
  ];

  /// 进程内单例, 默认带全部内置格式. 给自定义格式可传 [formats] 构造新实例.
  static final ChannelFormatRegistry instance = ChannelFormatRegistry();

  final List<ChannelFormat> _formats;

  /// 嗅探内容并解析, 命中第一个 [ChannelFormat.canParse] 即返回.
  /// 无格式可解析 → 抛 [FormatException].
  List<Channel> parse(String content) {
    for (final f in _formats) {
      if (f.canParse(content)) return f.parse(content);
    }
    throw FormatException(
      'ChannelFormatRegistry: 无可用格式解析该内容 (已试: '
      '${_formats.map((e) => e.id).join(', ')})',
    );
  }

  /// 显式指定格式 id 解析 (绕过嗅探). 未知 id → 抛 [ArgumentError].
  List<Channel> parseWith(String id, String content) {
    ChannelFormat? matched;
    for (final f in _formats) {
      if (f.id == id) {
        matched = f;
        break;
      }
    }
    if (matched == null) {
      throw ArgumentError('ChannelFormatRegistry: 未知格式 id: $id');
    }
    return matched.parse(content);
  }

  List<ChannelFormat> get formats => _formats;
}
