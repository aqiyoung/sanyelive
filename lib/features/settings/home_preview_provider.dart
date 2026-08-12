import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart' show sharedPreferencesProvider;

/// 「首页 Hero 直播预览」开关持久化键 (默认开启).
const String kHomePreviewKey = 'home.live_preview_enabled';

/// 首页 Hero 直播预览开关 —— 默认开启.
///
/// - 开启: 首页顶部 Hero 区会尝试静音播放 CCTV-1 实时直播预览.
/// - 关闭: 首页 Hero 区只显示静态卡片 (台标 + 播放键), 不再请求视频流,
///   可解决部分设备 media_kit 小窗预览花屏/灰屏的问题.
class HomePreviewNotifier extends Notifier<bool> {
  late final SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _prefs.getBool(kHomePreviewKey) ?? true;
  }

  Future<void> set(bool value) async {
    await _prefs.setBool(kHomePreviewKey, value);
    state = value;
  }
}

final homePreviewProvider =
    NotifierProvider<HomePreviewNotifier, bool>(HomePreviewNotifier.new);
