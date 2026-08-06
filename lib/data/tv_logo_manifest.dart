import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 离线台标清单: channelId -> 文件名(assets/logos 目录下).
///
/// 由 [loadTvLogoManifest] 在 main() 启动时预加载到内存.
/// 显示层 [_ChannelLogo] 优先用它离线渲染台标 (AssetImage),
/// 命中不到再回退运行时的 logoUrl (CachedNetworkImage) / 文字台标.
///
/// 清单由 scripts/fetch_tv_logos.py 在 CI 构建前生成:
///   - 数据源: channels_cn.json 自带 logo (Gitee 直链, 主要 CCTV)
///             + fanmingming/live/tv 扁平 PNG (GitHub, 全量含卫视/地方)
///             + Gitee mytv-android/myTVlogo (补充)
///   - 输出: assets/logos/<channel_id>.png + assets/logos/manifest.json
Map<String, String> tvLogoManifest = const {};

/// 启动期预加载离线台标清单. 失败 (如本地开发未跑脚本) 静默降级为空表,
/// 显示层自动回退到运行时 logoUrl / 文字台标, 不阻塞启动.
Future<void> loadTvLogoManifest() async {
  try {
    final str = await rootBundle.loadString('assets/logos/manifest.json');
    final Map<String, dynamic> m = jsonDecode(str);
    tvLogoManifest = m.map((k, v) => MapEntry(k, v as String));
  } catch (_) {
    tvLogoManifest = const {};
  }
}
