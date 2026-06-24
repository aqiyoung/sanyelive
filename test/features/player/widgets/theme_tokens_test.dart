// v0.3.7+50 主题 token 真修: 5 个 player widget 文件用 grep 自查
//
// 验证方式: 静态扫描 5 个文件, 确认除 import 外没有任何
// `IptvColors.` 直接引用.  这是真修的最后一道保险 —
// 如果以后有人又写回 IptvColors.xxx, 这测试 fail.
//
// 范围严格按 task spec: 只 grep 这 5 个文件:
//   - now_next_program.dart
//   - next_channels_strip.dart
//   - source_picker_sheet.dart
//   - player_top_bar.dart
//   - video_area.dart
//
// 不跑 widget pump — 静态扫描够用, 不依赖 widget tree context.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v0.3.7+50 player widgets 主题 token 真修 (5 个文件 grep 自查)', () {
    const widgetsDir = 'lib/features/player/widgets';
    const files = <String>[
      'now_next_program.dart',
      'next_channels_strip.dart',
      'source_picker_sheet.dart',
      'player_top_bar.dart',
      'video_area.dart',
    ];

    for (final f in files) {
      test('$f — 0 处硬编码 IptvColors. (除 import)', () {
        final path = '$widgetsDir/$f';
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: '$path should exist (widget file in player)');
        final lines = file.readAsLinesSync();
        // 找到 import '...colors.dart' 块, 记录行号区间
        final importLineIndices = <int>[];
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('theme/colors.dart') ||
              lines[i].contains('colors.dart')) {
            importLineIndices.add(i);
          }
        }
        // 跳除 import 区: 任何含 `IptvColors.` 且行号 != import 行 都算残留
        var hits = 0;
        final hitLines = <String>[];
        for (var i = 0; i < lines.length; i++) {
          if (importLineIndices.contains(i)) continue;
          if (lines[i].contains('IptvColors.')) {
            hits++;
            hitLines.add('L${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(hits, equals(0),
            reason:
                '$f 还有 $hits 处硬编码 IptvColors. (需要改成 Theme.of(context).colorScheme.xxx):\n${hitLines.join('\n')}');
      });
    }
  });
}
