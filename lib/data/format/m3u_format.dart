/// M3U / M3U8 播放列表解析器.
///
/// 支持标准 #EXTM3U 结构:
///   #EXTM3U
///   #EXTINF:-1 tvg-id="CCTV1" tvg-logo="http://x/y.png" group-title="央视",CCTV-1
///   http://example.com/cctv1.m3u8
///
/// 属性映射:
///   tvg-id      → Channel.id 前缀 (缺失则用 name 兜底, 保证可寻址且去重)
///   tvg-logo    → Channel.logoUrl
///   group-title → Channel.categories (按 ';' 拆分)
///   #EXTGRP:    → 当条 group 兜底 (出现在 #EXTINF 之前)
///   ',' 之后    → 显示名 (取最后一个逗号, 兼容名字里含逗号)
///
/// 健壮性: 空行 / 未知 # 指令 (#EXTVLCOPT 等) 跳过; 非 # 非空行视为上一
/// 条 #EXTINF 的 URL.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/channel.dart';
import 'channel_format.dart';

class M3uFormat implements ChannelFormat {
  const M3uFormat();

  @override
  String get id => 'm3u';

  @override
  String get label => 'M3U / M3U8';

  @override
  bool canParse(String content) {
    final t = content.trimLeft();
    // 大小写不敏感 (#extm3u 也认), 容忍 BOM / 前导空白.
    return t.toLowerCase().startsWith('#extm3u');
  }

  @override
  List<Channel> parse(String content) {
    final channels = <Channel>[];
    final seenIds = <String>{};

    String? pendingName;
    String? pendingTvgId;
    String? pendingLogo;
    List<String>? pendingGroups;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTM3U')) continue;

      if (line.startsWith('#EXTINF')) {
        final commaIdx = line.lastIndexOf(',');
        final name = commaIdx >= 0 ? line.substring(commaIdx + 1).trim() : '';
        final attrPart = commaIdx > 0 ? line.substring(0, commaIdx) : line;
        final attrs = _parseAttrs(attrPart);
        pendingName = name;
        pendingTvgId = attrs['tvg-id'];
        pendingLogo = attrs['tvg-logo'];
        final grp = attrs['group-title'];
        pendingGroups = grp == null
            ? null
            : grp
                .split(';')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
        continue;
      }

      if (line.startsWith('#')) {
        // #EXTGRP: 给紧随其后的 #EXTINF 设 group (老式 m3u 写法).
        if (line.startsWith('#EXTGRP:')) {
          final g = line.substring('#EXTGRP:'.length).trim();
          if (g.isNotEmpty) pendingGroups = [g];
        }
        continue;
      }

      // 非注释非空行 = 上一 #EXTINF 的 URL.
      if (pendingName == null) continue;
      final url = line;
      final id = _makeId(
        pendingTvgId,
        pendingName,
        seenIds,
      );
      channels.add(
        Channel(
          id: id,
          name: pendingName,
          country: '',
          categories: pendingGroups ?? const ['未分类'],
          altNames: const [],
          logoUrl:
              (pendingLogo != null && pendingLogo.isNotEmpty) ? pendingLogo : null,
          sources: [url],
        ),
      );
      pendingName = null;
      pendingTvgId = null;
      pendingLogo = null;
      pendingGroups = null;
    }

    if (channels.isEmpty) {
      debugPrint('M3uFormat.parse: 未解析出任何频道 (内容可能不含 #EXTINF+URL)');
    }
    return List.unmodifiable(channels);
  }

  /// tvg-id 存在且非空 → 原样用作 id (假设 playlist 内唯一).
  /// 否则用 name 兜底, 并对重名追加 #n 保证唯一.
  String _makeId(String? tvgId, String name, Set<String> seen) {
    final base = (tvgId != null && tvgId.isNotEmpty) ? 'm3u:$tvgId' : 'm3u:$name';
    var id = base;
    var n = 1;
    while (!seen.add(id)) {
      id = '$base#$n';
      n++;
    }
    return id;
  }

  /// 解析 `#EXTINF:-1 key="val" key2="val2"` 里的属性, key 转小写.
  Map<String, String> _parseAttrs(String part) {
    final attrs = <String, String>{};
    final re = RegExp(r'(\w[\w-]*)="([^"]*)"');
    for (final m in re.allMatches(part)) {
      attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
    }
    return attrs;
  }
}
