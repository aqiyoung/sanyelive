// v0.3.7+59 (6/19): 播放页状态栏/导航栏 brightness 逻辑 — 纯函数, 给
// [PlayerPage] 用, 也给 test/ 调 (避免 pump 整页 widget tree).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 状态栏/导航栏图标亮度跟主题走 — 浅色主题深图标, 暗色主题白图标.
/// v0.3.7+59:  systemNavigationBarColor 不用 scheme.surfaceContainer (M3 API 在
/// ColorScheme.dark() 里可能未定义变 null,  底部导航栏会变成默认黑色扮眼).
/// 改成显式 IptvColors.bgParchment / darkBg,  跟 AppBarTheme 一致.
/// v0.3.8+112 (6/20 老板反馈 19:20 "全屏上白条"):
/// 之前 statusBarColor: Colors.transparent 在 Android 14+ edge-to-edge 强制
/// 透明, 状态栏背景 = theme scaffold bg = light 米白.  老板看到 status bar
/// 是米白 (245,245,237) 跟视频区黑色对不上 = "上白条".
/// 修法:  statusBarColor 改 Colors.black (跟视频区一体化) + systemNavigationBarColor
/// 也改黑 (跟播放页黑色背景一体).  图标亮度保留 (亮色主题深图标,  暗色主题白图标).
SystemUiOverlayStyle buildSystemUiOverlayForPlayer(
  ColorScheme scheme,
  Brightness brightness,
) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  );
}

/// 退出播放页时还原全 APP 默认 (跟 player 同逻辑).
SystemUiOverlayStyle buildSystemUiOverlayForApp(
  ColorScheme scheme,
  Brightness brightness,
) {
  return buildSystemUiOverlayForPlayer(scheme, brightness);
}
