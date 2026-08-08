//
// 当前省份 — 支持"定位当前省份, 把该省卫视频道排到最前".
//
// 设计:
//   - ProvinceNotifier 继承 Notifier<String?>, 用 SharedPreferences 存
//     'location_province' (省份简称, 如 '浙江'); null = 未设置 (按默认顺序).
//   - setProvince(): 手动选择 / 清除.
//   - autoDetect(): 通过 IP 地理定位 (best-effort) 推断省份, 失败返回 null,
//     不抛异常. 定位 API 走网络, 可能因运营商/代理失败, 失败时回退手动选择.
//   - 排序逻辑见 lib/data/province_util.dart (sortSatelliteByProvince).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/province_util.dart' show kProvinces;
import 'theme_provider.dart' show sharedPreferencesProvider;

/// 当前省份 (null = 未设置). 持久化到 SharedPreferences 'location_province'.
final provinceProvider =
    NotifierProvider<ProvinceNotifier, String?>(ProvinceNotifier.new);

class ProvinceNotifier extends Notifier<String?> {
  static const kLocationProvinceKey = 'location_province';

  @override
  String? build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(kLocationProvinceKey);
    // 空字符串也视为未设置.
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// 设置当前省份 (null = 清除, 恢复默认顺序).
  Future<void> setProvince(String? province) async {
    state = province;
    final prefs = ref.read(sharedPreferencesProvider);
    if (province == null || province.isEmpty) {
      await prefs.remove(kLocationProvinceKey);
    } else {
      await prefs.setString(kLocationProvinceKey, province);
    }
  }

  /// 通过 IP 地理定位 (best-effort) 推断当前省份.
  ///
  /// 依次尝试多个国内 IP 库, 解析出省份简称后写入设置并返回;
  /// 全部失败 (网络/被墙/无字段) 返回 null, 由调用方回退手动选择.
  /// 不抛异常.
  Future<String?> autoDetect() async {
    const endpoints = <String>[
      // {"code":200,"province":"广东省","city":"深圳市",...}
      'https://ip.useragentinfo.com/json',
      // {"ret":"ok","data":{"ip":"..","location":["中国","广东","深圳","","电信"]}}
      'https://myip.ipip.net/json',
      // {"rs":1,"code":0,"address":"中国 广东省 深圳市 电信",...}
      'https://www.ip.cn/api/index?ip=&type=0',
    ];
    for (final url in endpoints) {
      try {
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;
        final province = _parseProvince(resp.body);
        if (province != null) {
          await setProvince(province);
          return province;
        }
      } catch (_) {
        // 试下一个源
      }
    }
    return null;
  }
}

/// 从 IP 库响应体解析省份简称, 兼容三种真实返回格式:
///   - ip.useragentinfo.com: {"province":"广东省","city":"深圳市",...}
///   - myip.ipip.net/json:   {"data":{"location":["中国","广东","深圳","","电信"]}}
///   - www.ip.cn:            {"address":"中国 广东省 深圳市 电信",...}
///
/// 结果必须能归一化成 [kProvinces] 中的简称才返回, 否则 null —— 避免把
/// "深圳市"/"中国" 这类匹配不上的字符串存进设置, 导致排序静默失效.
String? _parseProvince(String body) {
  final candidates = <String>[];
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      // 1) 顶层 province 字段.
      final p = decoded['province'];
      if (p is String) candidates.add(p);

      // 2) ipip 的 data.location 数组: [国家, 省, 市, 区, 运营商].
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        final loc = data['location'];
        if (loc is List) {
          candidates.addAll(loc.whereType<String>());
        }
        final dp = data['province'];
        if (dp is String) candidates.add(dp);
      }

      // 3) ip.cn 的 address: "中国 广东省 深圳市 电信".
      final addr = decoded['address'];
      if (addr is String) candidates.addAll(addr.split(RegExp(r'\s+')));
    }
  } catch (_) {
    // 非 JSON, 退化为正则抓 province 字段.
    final m = RegExp(r'"province"\s*:\s*"([^"]+)"').firstMatch(body);
    if (m != null) candidates.add(m.group(1)!);
  }

  for (final raw in candidates) {
    final p = _normalizeProvince(raw);
    if (p != null) return p;
  }
  return null;
}

/// "广东省"/"新疆维吾尔自治区"/"北京市" → "广东"/"新疆"/"北京".
/// 归一化后不在 [kProvinces] 里 (如 "中国"/"深圳市"/"电信") 返回 null.
String? _normalizeProvince(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final cleaned = trimmed.replaceFirst(
    RegExp(r'(维吾尔自治区|壮族自治区|回族自治区|特别行政区|自治区|省|市)$'),
    '',
  );
  return kProvinces.contains(cleaned) ? cleaned : null;
}
