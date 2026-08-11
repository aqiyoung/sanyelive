/// CCTV 源模块入口。
///
/// 内部拆分为:
///   - [cctv_source_model.dart]   模型 (CctvSource / CctvSourceStats)
///   - [cctv_source_registry.dart] 从 cctv_sources.json 加载并缓存
///   - [cctv_source_picker.dart]  选源 + 运营商分类 + 健康分
export 'cctv_source_model.dart';
export 'cctv_source_registry.dart';
export 'cctv_source_picker.dart';
