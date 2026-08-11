/// 频道列表格式抽象 — 把"外部 playlist 解析"与领域模型 [Channel]、加载方式彻底解耦.
///
/// 设计意图:
///   - 任何外部格式 (m3u / iptv-org json / 未来的 txt 直链 / xmltv …) 都只需实现
///     这一个接口, 产出统一的 [Channel] 列表.
///   - 新增格式 = 新增一个文件, 注册到 [ChannelFormatRegistry], 其余代码零改动.
///   - 解析层不依赖 flutter (可跑在 compute() isolate / 单测里).
///
/// 与 [Channel.fromJson] 的边界:
///   - [Channel.fromJson] / [Channel.toJson] 是 **领域模型的规范序列化** (磁盘缓存用).
///   - [ChannelFormat] 是 **外部 playlist 的导入解析** (用户/远端提供的源文件).
///   两者职责不同, 互不替代.
library;

import '../models/channel.dart';

/// 一种可解析的频道列表格式.
abstract class ChannelFormat {
  const ChannelFormat();

  /// 稳定 id, 全局唯一. 例: 'm3u' / 'iptv_org_json'.
  String get id;

  /// 人类可读标签 (调试 / 设置页展示).
  String get label;

  /// 快速嗅探内容是否属于本格式. 必须廉价且不抛异常
  /// (内部若需 decode 失败应 catch 后返 false, 不要冒泡).
  bool canParse(String content);

  /// 解析完整内容为频道列表. 内容不符合本格式 / 损坏时应抛 [FormatException],
  /// 由调用方 ([ChannelFormatRegistry]) 决定 fallback 或上报.
  List<Channel> parse(String content);
}
