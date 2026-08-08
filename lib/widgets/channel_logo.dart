import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/http/ipv4_cache_manager.dart';
import '../data/models/channel.dart';
import '../data/tv_logo_manifest.dart';

/// 频道台标组件
///
/// - 优先读取仓库打包的离线台标 `assets/logos/<channel_id>.png`
/// - 未命中时尝试 `channel.logoUrl` 网络台标
/// - 都失败时显示频道名首字兜底
///
/// [shadow] = true 时给白色透明台标叠加一层模糊黑色"形状投影"，
/// 让它能直接浮在浅色液态玻璃上而无需深色底牌（iOS 26 轻盈感）。
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    this.size = 48,
    this.shadow = false,
  });

  final Channel? channel;
  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final local = tvLogoManifest[channel?.id];
    if (local != null && local.isNotEmpty) {
      Widget buildImg() => Image.asset(
            'assets/logos/$local',
            fit: BoxFit.contain,
            height: size,
            errorBuilder: (_, __, ___) => _fallback(context),
          );
      return shadow ? _logoWithShadow(buildImg) : buildImg();
    }
    final logo = channel?.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      Widget buildImg() => CachedNetworkImage(
            imageUrl: logo,
            cacheManager: IPv4CacheManager(),
            fit: BoxFit.contain,
            height: size,
            placeholder: (_, __) => SizedBox(height: size),
            errorWidget: (_, __, ___) => _fallback(context),
          );
      return shadow ? _logoWithShadow(buildImg) : buildImg();
    }
    return _fallback(context);
  }

  /// 兜底: 无台标时生成一枚台标徽章 (配色 + 频道缩写), 保证每个频道都有"台标感".
  /// 离线、零网络, 不依赖远端拉取. 缩写规则:
  ///   - 含中文: 取首 1~2 个汉字 (如 "黑龙江电视台" -> "黑龙", "浙江卫视" -> "浙江").
  ///   - 纯英文: 取前两个单词首字母 / 单词前两位 (如 "Liaoning TV" -> "LT",
  ///     "CCTV-4" -> "CC", "HenanTVSatellite" -> "HT").
  Widget _fallback(BuildContext context) {
    final name = (channel?.displayName ?? '').trim();
    final abbr = _abbreviate(name);
    final double fs = abbr.length >= 2 ? size * 0.36 : size * 0.46;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorFor(name),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Center(
        child: Text(
          abbr,
          style: TextStyle(
            color: Colors.white,
            fontSize: fs,
            fontWeight: FontWeight.w900,
            letterSpacing: abbr.length >= 2 ? 0.5 : 0,
          ),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}

/// 给白色透明台标加一层"形状投影": 背后叠一个模糊的黑色剪影, 让 logo 在
/// 浅色玻璃上也能看清轮廓, 而无需实体深色底牌. 深色背景下投影不可见 (无害),
/// 故仅 shadow=true 的浅色卡片场景启用. 用 buildImage 闭包各建两份实例,
/// 避免同一 widget 对象在 Stack 里复用.
Widget _logoWithShadow(Widget Function() buildImage) {
  final shadowImg = buildImage();
  final frontImg = buildImage();
  return Stack(
    alignment: Alignment.center,
    children: <Widget>[
      Transform.translate(
        offset: const Offset(0, 2.5),
        child: Opacity(
          opacity: 0.5,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 4),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
              child: shadowImg,
            ),
          ),
        ),
      ),
      frontImg,
    ],
  );
}

/// 频道名 -> 缩写 (1~2 字符), 用于生成式台标徽章.
String _abbreviate(String name) {
  if (name.isEmpty) return '?';
  // 中文: 取前 1~2 个汉字.
  final cjk = name.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
  if (cjk.isNotEmpty) {
    return cjk.length >= 2 ? cjk.substring(0, 2) : cjk;
  }
  // 英文/拼音: 按空白分词, 取前两词首字母; 单词则取前两位.
  final tokens = name
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return name.substring(0, 1).toUpperCase();
  if (tokens.length >= 2) {
    return (tokens[0][0] + tokens[1][0]).toUpperCase();
  }
  final w = tokens[0].replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (w.length >= 2) return w.substring(0, 2).toUpperCase();
  return w.toUpperCase();
}

/// 频道名 -> 稳定配色 (FNV-1a 哈希到色相). 同频道颜色恒定, 不同频道尽量区分.
Color _colorFor(String name) {
  var h = 0x811c9dc5; // FNV offset basis
  for (final r in name.runes) {
    h ^= r;
    h = (h * 0x01000193) & 0xffffffff; // FNV prime
  }
  final hue = (h % 360).toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.60, 0.46).toColor();
}
