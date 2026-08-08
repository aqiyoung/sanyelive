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
  ///
  /// 源优先级 (实测可达性 + 稳定性):
  ///   1. whois.pconline.com.cn/ipJson.jsp — 太平洋电脑网 IP 库, 常年稳定,
  ///      返回 IPCallBack({"pro":"陕西省",...}), 国内网络 100% 可达.
  ///   2. myip.ipip.net/json — ipip.net, 返回 {"data":{"location":[...]}}.
  ///   3. www.ip.cn/api/index — 备用, 偶发 302 跳转, 仅兜底.
  Future<String?> autoDetect() async {
    const endpoints = <String>[
      'https://whois.pconline.com.cn/ipJson.jsp',
      'https://myip.ipip.net/json',
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

/// 从 IP 库响应体解析省份简称, 兼容以下真实返回格式:
///   - whois.pconline.com.cn: IPCallBack({"pro":"陕西省","city":"西安市",...})
///       (注意: 整体不是 JSON, 而是 JS 函数调用包裹, 需先剥离外层)
///   - myip.ipip.net/json:     {"ret":"ok","data":{"location":["中国","陕西","西安","","联通"]}}
///   - www.ip.cn:              {"address":"中国 广东省 深圳市 电信",...}
///
/// 结果必须能归一化成 [kProvinces] 中的简称才返回, 否则 null —— 避免把
/// "深圳市"/"中国" 这类匹配不上的字符串存进设置, 导致排序静默失效.
String? _parseProvince(String body) {
  Map<String, dynamic>? decoded;
  try {
    // 纯 JSON (ipip.net / ip.cn).
    decoded = jsonDecode(body) as Map<String, dynamic>;
  } on FormatException {
    // 兼容 pconline 的 IPCallBack({...}) 包裹: 截取最外层 {...} 再解析.
    final s = body.indexOf('{');
    final e = body.lastIndexOf('}');
    if (s >= 0 && e > s) {
      try {
        decoded = jsonDecode(body.substring(s, e + 1)) as Map<String, dynamic>;
      } on FormatException {
        decoded = null;
      }
    }
  }

  final candidates = <String>[];
  if (decoded != null) {
    // 1) 顶层 province / pconline 的 pro 字段.
    final p = decoded['province'];
    if (p is String) candidates.add(p);
    final pro = decoded['pro'];
    if (pro is String) candidates.add(pro);

    // 2) ipip 的 data.location 数组: [国家, 省, 市, 区, 运营商].
    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      final loc = data['location'];
      if (loc is List) candidates.addAll(loc.whereType<String>());
      final dp = data['province'];
      if (dp is String) candidates.add(dp);
    }

    // 3) ip.cn 的 address: "中国 广东省 深圳市 电信".
    final addr = decoded['address'];
    if (addr is String) candidates.addAll(addr.split(RegExp(r'\s+')));
  }

  // 结构化候选优先.
  for (final raw in candidates) {
    final p = _normalizeProvince(raw);
    if (p != null) return p;
  }

  // 兜底: 在原始文本里找 "X省"/"X市"/"X自治区" 形式.
  // 必须紧跟 省/市/自治区, 避免 "青海省" 误命中 "海南" 等子串问题.
  final m = RegExp(
    r'(?:北京|天津|上海|重庆|河北|山西|辽宁|吉林|黑龙江|江苏|浙江|安徽|福建|'
    r'江西|山东|河南|湖北|湖南|广东|海南|四川|贵州|云南|陕西|甘肃|青海|台湾|'
    r'内蒙古|广西|西藏|宁夏|新疆|香港|澳门)'
    r'(?:省|市|自治区|特别行政区)',
  ).firstMatch(body);
  if (m != null) return _normalizeProvince(m.group(0)!);

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
