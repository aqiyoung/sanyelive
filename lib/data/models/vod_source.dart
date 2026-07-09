// v0.3.13.0 (7/9 老板要求整合外部 TVBox 影视源): VOD 源模型.
//
// 设计:  单活跃源模式 — 用户一次选一个 MacCMS JSON API 源浏览,  在源列表
// 切换.  每个源 = 一个 baseUrl + 显示名 + 分类→typeId 映射.
//
// MacCMS 协议 (bfzyapi.com 同族):
//   - 列表: {baseUrl}?ac=list&t={typeId}&pg={page}&pagesize={n}
//   - 详情: {baseUrl}?ac=detail&ids={id1,id2,...}
//   - 分类表: {baseUrl}?ac=list&t=1 (返回 class[].type_id/type_name)
//
// typeId 方案因源而异:
//   - bfzyapi 系:  movie=20, series=30, variety=45, anime=39, documentary=46,
//                  sports=33
//   - 标准 MacCMS:  movie=1, series=2, variety=3, anime=4  (部分源还有
//                  documentary=5, sports=6, 但非统一)
// 提供两个预设方案,  用户添加源时二选一.

/// 分类键 → 友好名 (UI 显示 + 反查).
const Map<String, String> vodCategoryLabels = {
  'movie': '电影',
  'series': '电视剧',
  'variety': '综艺',
  'anime': '动漫',
  'documentary': '纪录片',
  'sports': '体育',
  'overseas': '海外剧场',
};

/// bfzyapi 系 typeId (默认源 bfzyapi.com / ikunzyapi.com 等).
const Map<String, int> bfzyapiTypeIds = {
  'movie': 20,
  'series': 30,
  'variety': 45,
  'anime': 39,
  'documentary': 46,
  'sports': 33,
  'overseas': 26, // IKun 系用 26 (欧美剧); bfzyapi 系用 32 — 参见 bfzyapiOverseasTypeIds.
};

/// bfzyapi.com 默认源的海外剧 typeId 跟其他 bfzyapi 采集器不同 (32 vs 26),
/// 所以单独列一档.  bfzyapiDefaultSource() 用这个.
const Map<String, int> bfzyapiDefaultTypeIds = {
  'movie': 20,
  'series': 30,
  'variety': 45,
  'anime': 39,
  'documentary': 46,
  'sports': 33,
  'overseas': 32, // bfzyapi.com 欧美剧 = 32 (实测 6322 部, 317 页).
};

/// 标准 MacCMS typeId (1/2/3/4).
const Map<String, int> standardMaccmsTypeIds = {
  'movie': 1,
  'series': 2,
  'variety': 3,
  'anime': 4,
  'documentary': 5,
  'sports': 6,
  'overseas': 26,
};

/// typeId 方案名 — UI 单选用.
enum VodTypeIdScheme {
  bfzyapi('bfzyapi', '暴风系 (20/30/45)'),
  standard('standard', '标准 MacCMS (1/2/3)');

  const VodTypeIdScheme(this.id, this.label);
  final String id;
  final String label;

  Map<String, int> get typeIds => this == VodTypeIdScheme.bfzyapi
      ? bfzyapiTypeIds
      : standardMaccmsTypeIds;

  static VodTypeIdScheme fromId(String? id) => id == 'standard'
      ? VodTypeIdScheme.standard
      : VodTypeIdScheme.bfzyapi;
}

class VodSource {
  const VodSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.typeIds = bfzyapiTypeIds,
    this.builtIn = false,
  });

  /// 唯一标识 (host + index 自动生成,  或用户定义).
  final String id;

  /// 显示名 (如 "暴风资源", "量子资源").
  final String name;

  /// MacCMS JSON API 基础 URL (如 "https://bfzyapi.com/api.php/provide/vod").
  final String baseUrl;

  /// 分类→typeId 映射.
  final Map<String, int> typeIds;

  /// 默认内置源 (bfzyapi) = true → 不可删除.
  final bool builtIn;

  /// 从 URL 自动提取 host 当 display fallback.
  String get host {
    try {
      return Uri.parse(baseUrl).host;
    } catch (_) {
      return baseUrl;
    }
  }

  /// TVBox sites[].name 常带 emoji (🐯┃量子┃采集),  去掉 emoji + 分隔符
  /// 让 UI chip 更紧凑.
  static String cleanName(String raw) {
    // 去掉常见 emoji + ┃/┃/│/丨 分隔符 + 首尾空白.
    final cleaned = raw
        .replaceAll(
          RegExp(
            r'[\u{1F000}-\u{1FFFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}\u{1F300}-\u{1F9FF}]',
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'[┃│丨]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? raw.trim() : cleaned;
  }

  VodSource copyWith({
    String? id,
    String? name,
    String? baseUrl,
    Map<String, int>? typeIds,
    bool? builtIn,
  }) {
    return VodSource(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      typeIds: typeIds ?? this.typeIds,
      builtIn: builtIn ?? this.builtIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'typeIds': typeIds.map((k, v) => MapEntry(k, v)),
        'builtIn': builtIn,
      };

  factory VodSource.fromJson(Map<String, dynamic> json) => VodSource(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
        typeIds: (json['typeIds'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            bfzyapiTypeIds,
        builtIn: json['builtIn'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is VodSource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VodSource($id, $name)';
}
