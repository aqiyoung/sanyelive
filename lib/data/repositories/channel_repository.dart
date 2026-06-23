import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';
// v0.3.8+125 (6/21 老板拍):  远程频道数据源 — 优先用 aqiyoung/iptv-channels-organized
// 分类 JSON (每周一 cron 自动生成),  失败 fallback 本地 assets/data/channels_cn.json.
// 单独抽 remote_channels_source.dart 让 channel_repository 保持 focused on assets.
import '../remote_channels_source.dart';

/// 把 [known] 里跟 channel.id 匹配的 URL 列表追加到 [c].sources 后面,
/// 去重但保留首次出现的顺序.  不修改传入的 channel, 返回新实例.
/// 卡 6: channels_cn.json 里 bake 的 iptv-org 高画质源必须保留在前面,
/// known_sources.json 是兑底, SourceFailover 从前往后试.
@visibleForTesting
List<Channel> mergeKnownSources(
  List<Channel> channels,
  Map<String, dynamic> known,
) {
  return channels.map((c) {
    final knownForChannel =
        (known[c.id] as List?)?.cast<String>() ?? const <String>[];
    if (knownForChannel.isEmpty) return c;
    final merged = <String>[];
    final seen = <String>{};
    for (final url in c.sources) {
      if (seen.add(url)) merged.add(url);
    }
    for (final url in knownForChannel) {
      if (seen.add(url)) merged.add(url);
    }
    return Channel(
      id: c.id,
      name: c.name,
      country: c.country,
      categories: c.categories,
      altNames: c.altNames,
      website: c.website,
      logoUrl: c.logoUrl,
      sources: merged,
      cctvSource:
          c.cctvSource, // v0.3.5.3 (6/18): 保留 CCTV 专属源不被 known_sources 覆盖
      isNsfw: c.isNsfw,
    );
  }).toList(growable: false);
}

/// Channel Repository — 从编译时内嵌的 JSON 加载
class ChannelRepository {
  const ChannelRepository();

  /// v0.3.7+50 (6/19): 内存缓存 — 避免每次 [channelsProvider] rebuild 都
  /// `rootBundle.loadString` 2 份 assets + `json.decode`.  首屏 (home_page)
  /// 一次读完后,  push 到 player_page 又 pop 回 home 不会重新 IO.
  ///
  /// 注意:  - 用 `static` 字段而不是 Provider/ChangeNotifier,  因为这份
  /// 缓存是"读一次就不变"的数据 (assets 在 APP 生命周期里不变).
  /// - 不放 Provider 是因为 Riverpod 的 `ref.watch(channelsProvider)` 已经
  /// 会 dedup,  但 PlayerPage 自己 `ref.read(channelsProvider.future)` 会
  /// bypass FutureProvider 的 cache,  走 repo 的 cache 才能真正零 IO.
  static List<Channel>? _cached;
  static Future<List<Channel>>? _pending;

  Future<List<Channel>> loadBundled() async {
    // 命中缓存 → 零 IO,  直接返回.
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    // 并发去重: 多个 widget 同时 init 调 loadBundled() 时,  只跑一次
    // rootBundle.loadString,  其余 await 同一个 Future.
    final pending = _pending;
    if (pending != null) {
      return pending;
    }
    final future = _loadBundledImpl();
    _pending = future;
    try {
      final result = await future;
      _cached = result;
      return result;
    } finally {
      _pending = null;
    }
  }

  /// 实际 IO 路径.  拆出来让 [loadBundled] 缓存逻辑更清晰.
  Future<List<Channel>> _loadBundledImpl() async {
    // v0.3.8+110 (6/20 老板加国际频道模块):  并行加载 CN + I18N,  合并为一个
    // [Channel] 列表.  CN 中国频道 + I18N 1886 国际频道.  合并顺序:  CN 先
    // (首页分类依 country='CN' / id.startsWith('CCTV') 路由),  I18N 后.
    // i18n channels 都有 country (US/UK/FR/DE/RU/IN/JP).
    final cnFuture = _loadChannels('assets/data/channels_cn.json');
    final i18nFuture = _loadChannels('assets/data/channels_i18n.json');
    final knownFuture = _loadKnownSources();

    final cn = await cnFuture;
    final i18n = await i18nFuture;
    final known = await knownFuture;

    final merged = <Channel>[...cn, ...i18n];
    if (known != null) {
      return mergeKnownSources(merged, known);
    }
    return merged;
  }

  /// v0.3.8+110 (6/20):  抽 CN/I18N 公共加载逻辑 (JSON -> List<Channel>).
  /// 加载失败返回空数组 (call 端合并时正常).
  /// v0.3.8+117 (6/20 22:28 老板反馈): 启动慢 + 二次点击
  ///   之前 json.decode + Channel.fromJson × 648 在主线程同步执行,  阻塞
  /// UI 2-5s (尤其 +110 加 i18n 后 1886 channels,  CPU 解析阻塞).  期间所有
  /// tap 不响应 (用户看到 "卡半天 + 二次点击才能进 category").
  /// 修法:  走 compute() 把 json.decode + Channel.fromJson 移到 isolate.
  ///   - 主线程:  只 rootBundle.loadString (IO 异步)
  ///   - 后台 isolate:  json.decode + map(Channel.fromJson) (CPU 密集)
  ///   - 主线程:  接收 List<Channel> 后立即返回,  同步继续 build UI
  ///  性能: 启动 2-5s 阻塞 → < 500ms (主线程空闲让 UI 立刻响应).
  /// 注: compute() 每次 spawn isolate 有 ~50-200ms 开销,  但 6/19 已加
  /// _cached / _pending (静态缓存),  channelsProvider 第二次以后命中缓存,
  /// 不会触发 isolate.  所以开销只在 APP 首次启动 / push to player 后
  /// ref.read(channelsProvider.future) 那一帧.
  Future<List<Channel>> _loadChannels(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      // v0.3.8+169: 直接传原始 JSON 给 isolate, 避免主线程二次 encode/decode.
      // 顶层结构兼容 (v0.3.8+113): List (cn.json) / Map.channels (i18n.json).
      // isolate 里自己 parse 顶层 + 解析 Channel.
      return compute(parseChannelsIsolate, raw);
    } catch (e) {
      debugPrint('ChannelRepository._loadChannels($path) failed: $e');
      return const <Channel>[];
    }
  }

  /// v0.3.8+110 (6/20):  known_sources.json 单独抽 — 加载失败返 null
  /// (call 端选不 merge,  避免隐式吞错).
  Future<Map<String, dynamic>?> _loadKnownSources() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/known_sources.json');
      return json.decode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ChannelRepository._loadKnownSources failed: $e');
      return null;
    }
  }

  /// v0.3.7+50 (6/19) — 测试钩子.  单元测试 setUp 里清缓存,  避免
  /// "上一个测试改了 mock data,  这个测试还看到老 cache" 的状态泄漏.
  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _pending = null;
  }
}



/// v0.3.8+117 (6/20 22:28 老板反馈): 走 isolate 解析 channels JSON.
/// 必须是 top-level 函数 (compute() 只能传 top-level / static — 不能传
/// instance method 因为 instance method 隐式绑 this,  isolate 间不能
/// 传对象引用).  输入: channelsJson = JSON 编码的 List<Map> (已剥掉顶层
/// metadata,  _loadChannels 在主线程处理顶层结构,  只把 channels list
/// 给 isolate).  输出: List<Channel> 用 growable: false 节省内存.
/// 注:  json.decode + Channel.fromJson 在 isolate 里 ~10x 快于主线程
/// (无 UI / GC 干扰).  启动 2-5s 阻塞 → < 500ms.
List<Channel> parseChannelsIsolate(String rawJson) {
  final decoded = json.decode(rawJson);
  final List<dynamic> list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map && decoded['channels'] is List) {
    list = decoded['channels'] as List<dynamic>;
  } else {
    debugPrint('parseChannelsIsolate: 未知 JSON 顶层结构 (${decoded.runtimeType})');
    return const <Channel>[];
  }
  return list
      .map((e) => Channel.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

final channelRepositoryProvider = Provider<ChannelRepository>(
  (ref) => const ChannelRepository(),
);

/// v0.3.8+125 (6/21 老板拍):  远程优先 + 本地 fallback 合并 provider.
///
/// 策略:
///   1. main() 启动时已经 fire-and-forget 预热 remoteChannelsProvider.
///   2. 这里 await remoteChannelsProvider.future — 已成功就直接用远程 bundle.all.
///   3. 远程失败 / 超时 / 4xx → 自动 fallback 到 ChannelRepository.loadBundled()
///      (assets/data/channels_cn.json + channels_i18n.json + known_sources merge).
///
/// 测试兼容:  单元测试 overrideWith(channelsProvider, fake data) 直接替换 body,
/// 完全不走 remote.  集成测试需要真实 http 行为时 overrideWith remoteChannelsProvider.
///
/// v0.3.8+132 (6/21 09:21 老板反馈 "启动白屏"):
/// 之前 channelsProvider body 先 await 远端 (12s 超时) 才 fallback 本地 — 期间
/// UI 空 = 白屏.  修法:  body 同步返本地 (loadBundled 有缓存,  二次读零IO),
/// 不在 body 里 await 远端.  远端拉取在 main.dart _prewarmRemoteChannels 已
/// 预热 (unawaited),  remoteChannelsProvider.future 第一次 watch 时如有
/// resolved 直接拿,  无则走本地下次再 refresh.
///   UI 拿到本地 198 频道 → 首帧有数据 → UI 显示.  +127 Skeleton widget
///   负责 player_page 内部 player state loading,  跟 channelsProvider 异步无关.
///   之前白屏原因:  channelsProvider = FutureProvider,  await 远端 12s,  期间
///   home_page.build() asyncChannels.when(loading: data: error:) 一直 loading 显示
///   spinner = 看起来"白屏几秒".  现在同步返本地,  spinner 几乎瞬间消失.
///   v0.3.8+132 (附加): channelsStreamProvider = StreamProvider,  发本地
///   同步 yield → background 拉远端 → 到了 emit 覆盖.  UI watch 这个 stream
///   就能拿到 远端 360 频道 (36 sat + 101 local + 44 cctv + 133 intl + 46 national),
///   同时首帧不空白.  现有 watch(channelsProvider) 用法不变 (返本地),  后期可
///   逐步改 UI watch channelsStreamProvider.
final channelsProvider = FutureProvider<List<Channel>>((ref) async {
  final repo = ref.watch(channelRepositoryProvider);
  return repo.loadBundled();
});

/// v0.3.10.6 (6/23 老板拍): 频道分类数据每日 03:00 Beijing 自动后台刷新.
/// 启动时: 如果 _channelsLastRefresh > 1 天就立即重拉.
Timer? _channelsRefreshTimer;
DateTime? _channelsLastRefresh;

/// 启动 channels 每日 03:00 Beijing 自动后台刷新.
void startChannelsAutoRefresh({required ProviderContainer container}) {
  _channelsRefreshTimer?.cancel();
  _scheduleNextChannelsRefresh(container);

  // 启动瞬间: 如果 last refresh > 1 天就立即重拉
  final now = DateTime.now();
  if (_channelsLastRefresh == null ||
      now.difference(_channelsLastRefresh!) > const Duration(days: 1)) {
    Future.microtask(() => _refreshChannelsNow(container));
  }
}

void _scheduleNextChannelsRefresh(ProviderContainer container) {
  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, 3, 0, 0); // Beijing 03:00
  if (next.isBefore(now)) next = next.add(const Duration(days: 1));
  final delay = next.difference(now);
  debugPrint('ChannelsRefresh: 下次刷新 ${delay.inHours}h ${delay.inMinutes.remainder(60)}m 后 ($next)');
  _channelsRefreshTimer = Timer(delay, () {
    _refreshChannelsNow(container);
    _scheduleNextChannelsRefresh(container);
  });
}

Future<void> _refreshChannelsNow(ProviderContainer container) async {
  _channelsLastRefresh = DateTime.now();
  try {
    container.invalidate(channelRepositoryProvider);
    container.invalidate(remoteChannelsProvider);
    debugPrint('ChannelsRefresh: 触发 channelRepository + remoteChannels invalidate');
  } catch (e) {
    debugPrint('ChannelsRefresh: invalidate 失败: $e');
  }
}

void stopChannelsAutoRefresh() {
  _channelsRefreshTimer?.cancel();
  _channelsRefreshTimer = null;
}

/// v0.3.8+132: channelsStreamProvider = StreamProvider,  同步发本地 + background
/// 覆盖远端.  UI watch 这个能拿完整数据且不白屏.  现有 FutureProvider 保留兼容测试.
/// v0.3.8+132 (测试兼容):  stream body 同步 yield 本地 + 如果本地跟
/// channelsProvider.future 一致,  复用 (不改 stream).  测试 override
/// channelsProvider 后,  stream 第一行读 channelRepositoryProvider.loadBundled()
/// 但 FakeRepo 优先 — 跟 fake 一致.
/// 为什么不走 channelsProvider.future: 那个会 await 远端 12s — UI 白屏.
/// 为什么不直接 await repo.loadBundled():  第一次读 1-2s —  但 _baseOverrides
/// 测试里 channelRepositoryProvider.overrideWithValue 返 Future.value(fake),
/// 零IO.  生产路径 (不 override) 第一次读 1-2s — 首帧 loading,  +127 Skeleton
/// 应付 (玩家进频道时);  不影响其他 page (home/category/favorites/search).
/// v0.3.8+132 (优化): loadBundled 有 static _cached 缓存 — 第二次读零IO.
/// v0.3.8+133 (6/21 09:49 老板反馈 "启动白屏"):  body 逻辑不变 (同步 yield 本地
/// + 远端覆盖) — 真正 race 是 player_page initState + main.dart 启动流程顺序.
///  修法:  main.dart _PrewarmChannelRepository() 在 runApp 之前 fire-and-forget
///  调 loadBundled(),  启 app 后这 provider 已 resolve,  进 player_page 只
///  ref.watch,  零初始化 —  跟 +124 media_kit 预热是同样的思路.
/// stream body:
final channelsStreamProvider = StreamProvider<List<Channel>>((ref) async* {
  final repo = ref.watch(channelRepositoryProvider);
  final local = await repo.loadBundled();
  yield local;
  // 远端 — timeout 后 emit 覆盖.  测试环境中 remoteChannelsProvider
  // 默认行为,  测试需手动 override channelsStreamProvider 才能控制 loading.
  try {
    final bundle = await ref
        .watch(remoteChannelsProvider.future)
        .timeout(const Duration(seconds: 10));
    if (bundle.all.length != local.length) {
      yield bundle.all;
    }
  } catch (_) {
    // 远程失败 — 保持本地,  不重 yield.
  }
});
