import 'package:flutter/material.dart';

/// 新中式字体 — 衬线标题 + 系统无衬线正文
/// 衬线：Georgia (iOS/Android 自带，无须打包字体)
class IptvTypography {
  IptvTypography._();

  static const String serifFamily = 'Georgia';
  static const String sansFamily = 'Roboto'; // Android 默认无衬线

  /// / Theme.of(context).textTheme 自动适配浅色 + 暗色.  之前 const TextStyle
  /// 写死 color: IptvColors.textPrimary (深棕),  暗色主题下也是深棕 → 暗背景上看不清.
  /// 是不要在这里指定 color,  让 MaterialApp 的 textTheme.apply(bodyColor:)
  /// 接管.  浅色主题 textTheme.bodyMedium.color 默认 = textPrimary (深棕),  暗色
  /// 主题 = darkTextPrimary (米白).  都对.

  /// 衬线大标题 — 用于 Section 标题
  static const TextStyle serifHeadline = TextStyle(
    fontFamily: serifFamily,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// 衬线中标题
  static const TextStyle serifTitle = TextStyle(
    fontFamily: serifFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// 无衬线小标题
  static const TextStyle sansTitle = TextStyle(
    fontFamily: sansFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// 正文
  static const TextStyle body = TextStyle(
    fontFamily: sansFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// 副文字
  static const TextStyle caption = TextStyle(
    fontFamily: sansFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
}
