import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'poster_wall_page.dart';

/// 三页影视 主页 — 海报墙 (三屏: 推荐/直播/点播)
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const PosterWallPage();
  }
}
