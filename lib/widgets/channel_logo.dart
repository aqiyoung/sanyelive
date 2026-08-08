import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/http/ipv4_cache_manager.dart';
import '../core/theme/colors.dart';
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
/// [bright] 控制兜底文字颜色：深色背景用白字，浅色背景用深色字。
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    this.size = 48,
    this.bright = false,
    this.shadow = false,
  });

  final Channel? channel;
  final double size;
  final bool bright;
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

  /// 兜底: 无台标时显示频道名首字.
  Widget _fallback(BuildContext context) {
    final name = (channel?.displayName ?? '').trim();
    final ch = name.isNotEmpty ? name[0] : '?';
    final Color fg = bright ? Colors.white : context.fgMain;
    return Center(
      child: Text(
        ch,
        style: TextStyle(
          color: fg,
          fontSize: size * 0.46,
          fontWeight: FontWeight.w900,
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
