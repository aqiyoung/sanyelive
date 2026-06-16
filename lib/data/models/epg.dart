import 'package:freezed_annotation/freezed_annotation.dart';

part 'epg.freezed.dart';
part 'epg.g.dart';

/// EPG (Electronic Program Guide) 单条节目单
@freezed
class EpgEntry with _$EpgEntry {
  const factory EpgEntry({
    /// 关联的 iptv-org channel id
    required String channelId,

    /// 节目名
    required String title,

    /// 开始时间 (UTC ISO 8601)
    required DateTime start,

    /// 结束时间 (UTC ISO 8601)
    required DateTime end,
  }) = _EpgEntry;

  factory EpgEntry.fromJson(Map<String, dynamic> json) =>
      _$EpgEntryFromJson(json);
}
