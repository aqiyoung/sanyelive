//
// 省份工具 — 支持"定位当前省份, 把该省卫视频道排到最前".
//
// - [kProvinces]: 34 个省级行政区简称列表 (设置页选择器 + 排序匹配用).
// - [satelliteProvince]: 从卫视频道派生其所属省份 (处理东方卫视/深圳卫视等特殊命名).
// - [sortSatelliteByProvince]: 把指定省份的卫视稳定地排到列表最前.

import 'models/channel.dart';

/// 34 个省级行政区 (直辖市 / 省 / 自治区 / 特别行政区) 简称.
/// 顺序大致按地理 + 常用度, 方便设置页滚动选择.
const List<String> kProvinces = <String>[
  '北京',
  '天津',
  '上海',
  '重庆',
  '河北',
  '山西',
  '辽宁',
  '吉林',
  '黑龙江',
  '江苏',
  '浙江',
  '安徽',
  '福建',
  '江西',
  '山东',
  '河南',
  '湖北',
  '湖南',
  '广东',
  '海南',
  '四川',
  '贵州',
  '云南',
  '陕西',
  '甘肃',
  '青海',
  '台湾',
  '内蒙古',
  '广西',
  '西藏',
  '宁夏',
  '新疆',
  '香港',
  '澳门',
];

/// 卫视 displayName → 省份简称. 返回 null 表示无法识别 (非卫视 / 特殊台).
///
/// 常规 "<省份>卫视" 直接去后缀; 少量非 "<省份>卫视" 命名的卫视用 [special] 映射.
String? satelliteProvince(Channel ch) {
  final name = ch.displayName;

  // 特殊命名卫视 → 省份.
  const special = <String, String>{
    '东方卫视': '上海',
    // 深圳/厦门是计划单列市, 归入所属省, 否则定位到"广东/福建"时匹配不上.
    '深圳卫视': '广东',
    '厦门卫视': '福建',
    '兵团卫视': '新疆',
    '海峡卫视': '福建',
    '三沙卫视': '海南',
    '延边卫视': '吉林',
    '康巴卫视': '四川',
    '东南卫视': '福建',
  };
  if (special.containsKey(name)) return special[name];

  // 常规 "<省份>卫视".
  if (name.endsWith('卫视')) {
    final p = name.substring(0, name.length - 2);
    if (kProvinces.contains(p)) return p;
  }
  return null;
}

/// 把 [province] 对应的卫视稳定地排到 [sats] 最前, 其余保持原顺序.
/// [province] 为 null / 空时原样返回.
List<Channel> sortSatelliteByProvince(List<Channel> sats, String? province) {
  if (province == null || province.isEmpty) return sats;
  final matched = <Channel>[];
  final rest = <Channel>[];
  for (final ch in sats) {
    if (satelliteProvince(ch) == province) {
      matched.add(ch);
    } else {
      rest.add(ch);
    }
  }
  return <Channel>[...matched, ...rest];
}
