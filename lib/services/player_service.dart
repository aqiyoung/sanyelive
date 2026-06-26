import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models/channel.dart';
import '../data/source_dispatcher.dart';
import '../utils/crash_logger.dart';
import 'smart_source_router.dart';
import 'source_failover.dart';

/// 播放状态
enum PlayerStatus {
  /// 初始, 尚未开始
  idle,

  /// 正在尝试源 (含多源切换)
  loading,

  /// 正在播放
  playing,

  /// 出错 (所有源都失败)
  error,
}

/// 不可变的播放状态快照
@immutable
class PlayerState {
  const PlayerState({
    required this.status,
    this.channel,
    this.currentSource,
    this.error,
    this.attempt,
  });

  final PlayerStatus status;
  final Channel? channel;
  final String? currentSource;
  final String? error;

  /// 当前正在尝试的源 (用于 UI 展示 "尝试源 2/3")
  final SourceAttemptEvent? attempt;

  const PlayerState.idle() : this(status: PlayerStatus.idle);

  PlayerState copyWith({
    PlayerStatus? status,
    Channel? channel,
    String? currentSource,
    String? error,
    SourceAttemptEvent? attempt,
    bool clearError = false,
    bool clearAttempt = false,
  }) {
    return PlayerState(
      status: status ?? this.status,
      channel: channel ?? this.channel,
      currentSource: currentSource ?? this.currentSource,
      error: clearError ? null : (error ?? this.error),
      attempt: clearAttempt ? null : (attempt ?? this.attempt),
    );
  }
}

/// media_kit 实现的 [StreamOpener] — 把 URL 真正打开到 player
class MediaKitStreamOpener implements StreamOpener {
  MediaKitStreamOpener(this._player);

  final Player _player;

  @override
  Future<void> cancel(String url) async {
    // v0.3.8+169: 超时/失败时清理, 防止 libmpv 资源泄漏.
    // player 可能已经在 open 中, 尝试 stop 让它立即停止.
    try {
      unawaited(_player.stop());
    } catch (_) {}
  }

  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    try {
      // media_kit 的 open 是异步但很快 (通常 < 100ms),
      // 真正的"起播"通过 [Player.stream.playing] 监听, 此处只检查 open 成功与否
      final completer = Completer<bool>();
      // v0.3.8+169: sub 和 timer 互相引用, 必须用 late final 解决声明顺序.
      late final StreamSubscription<dynamic> sub;
      late final Timer timer;
      sub = _player.stream.playing.listen((playing) {
        if (!completer.isCompleted) {
          sub.cancel();
          timer.cancel();
          completer.complete(true);
        }
      });
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          sub.cancel();
          completer.complete(false);
        }
      });

      await _player.open(Media(url));
      return await completer.future;
    } catch (e) {
      debugPrint('MediaKitStreamOpener.open failed: $e');
      return false;
    }
  }
}

/// PlayerService — 全局单例
///   - 持有唯一的 [Player] 实例 (避免每个页面都创建 native player)
///   - 调用 [SourceFailover] 选源
///   - 暴露 [state] 给 UI 监听
///
/// v0.3.10.11 (6/23 老板反馈 腾讯极光盒子 6 闪退): libmpv.so 加载失败时不
/// 闪退, 改用 [FallbackMediaPlayer] 占位 (通过 platform channel; 若 native
/// 端未注册,  也是 silently fail — 视频不出图但 APP 不崩).  libmpv 加载失败
/// 90% 是 Amlogic S905X3 等 TV box 的 dlopen 问题.
class PlayerService extends ChangeNotifier {
  PlayerService({
    required StreamOpener opener,
    SourceFailover? failover,
    Player? player,
    FallbackMediaPlayer? fallbackPlayer,
    SmartSourceRouter? router,
  })  : _router = router ?? SmartSourceRouter(),
        _player = player,
        _failover = failover ??
            SmartSourceFailover(
              opener: opener,
              router: router ?? SmartSourceRouter(),
            ),
        _fallbackPlayer =
            fallbackPlayer ?? (player == null ? FallbackMediaPlayer() : null);

  /// media_kit 的 native player. libmpv.so 加载失败时为 null (v0.3.10.11).
  final Player? _player;
  final SourceFailover _failover;
  final SmartSourceRouter _router;
  // v0.3.10.11: libmpv init 失败时启用,  通过 platform channel 走 Android
  // MediaPlayer (如果 native 端没注册实现,  静默失败).  null = 用 libmpv 正常路径.
  final FallbackMediaPlayer? _fallbackPlayer;
  bool _disposed = false;
  bool _playing = false; // v0.3.8+169: 防并发 play() 覆盖状态.

  /// v0.3.10.11: libmpv 是否被 fallback 替换. true = 视频放不出来,
  /// UI 端拿到的 controller 也是 null (Video widget 不渲染),  老板看 error.
  bool get useFallbackPlayer => _player == null && _fallbackPlayer != null;

  PlayerState _state = const PlayerState.idle();
  PlayerState get state => _state;

  /// v0.3.8+109 (6/20 老板反馈 "点频道 半天进不去 必须点第二下"):
  /// 立即让 state 进入 loading — 不等 addPostFrameCallback 也不等 channelsProvider.
  /// PlayerPage.initState 调用后第一帧就看到 "正在打开…" loading.
  /// 避免老板看到 idle UI + TopBar 空态 → 以为没响应 → 再点一次.
  /// 状态从 idle/error → loading.  已是 playing/loading 跳过 (避免重置 attempt 计数器).
  void primeLoadingState() {
    if (_disposed) return;
    if (_state.status == PlayerStatus.idle ||
        _state.status == PlayerStatus.error) {
      _set(_state.copyWith(
        status: PlayerStatus.loading,
        clearError: true,
        clearAttempt: true,
      ));
    }
  }

  /// 切到 [channel]; 已在播放则先 stop
  /// v0.3.8+123 (6/21 老板反馈 "启动慢 白屏 第一次进不去 需要等几秒 点第二次"):
  /// 之前 play() 串行 await:
  ///   await _player.stop() (50-200ms, libmpv 命令)
  ///   _set(loading) (触发 UI 重建)
  ///   await _failover.play(sources, ...) (1-3s 真打开流)
  /// 总耗时 1.5-3.5s, 但 _set(loading) 要等 stop 完成才发,  UI 第一帧看到
  /// 还是 "旧频道的 playing 状态",  老板看到白屏 + 以为没响应 + 点第二次.
  /// 修法:  不再 await _player.stop() — fire-and-forget 后台 stop,
  ///  _set(loading) 同步发出去让 UI 第一帧看到 "正在打开…" +  attempt 计数器.
  ///  _failover.play 依然 await (后续状态变化都依赖它).  视觉:
  ///   - 点频道 → 立即 "正在打开… 尝试源 1/N"
  ///   - 背景 stop + open 并行跑
  ///   - open 成功 → "尝试源 1/1" → 变 playing
  ///   - open 失败 → "尝试源 2/N" → 切下一个源,  状态保持 loading
  Future<void> play(Channel channel) async {
    if (_disposed) return;
    if (_playing) return; // v0.3.8+169: 防并发 play() 覆盖状态

    _playing = true;

    // v0.3.5.3 (6/18): 用 SourceDispatcher 选源 — CCTV 频道优先走 cctvSource,
    // 非 CCTV 走老逻辑 channel.sources (repository 已合并 known_sources).
    final sources = SourceDispatcher.dispatch(channel);
    if (sources.isEmpty) {
      _set(
        _state.copyWith(
          status: PlayerStatus.error,
          channel: channel,
          error: '该频道无可用播放源',
          clearAttempt: true,
        ),
      );
      return;
    }

    // v0.3.8+123: 先 set loading 让 UI 第一帧看到 “正在打开…”,  再后台 stop.
    //  顺序很重要:  set loading 必须在 stop 之前,  这样 stop 在 background
    //  跑 50-200ms 时 UI 已经重建成 loading overlay.
    _set(
      _state.copyWith(
        status: PlayerStatus.loading,
        channel: channel,
        clearError: true,
        clearAttempt: true,
      ),
    );

    // v0.3.8+169: 序列化 stop → open, 避免 libmpv 竞态.
    //  v0.3.8+123 改成 fire-and-forget 是为了 UI 立即显示 loading,  但
    //  stop/open 在 libmpv 内部可能交错执行 (stop 未完成就 open 新流).
    //  折中:  await stop (50-200ms),  但 set loading 在 stop 之前已经发出,
    //  UI 不会白屏.  stop 完成后立即 open,  不引入额外延迟.
    if (_player != null) {
      await _player.stop();
    }

    try {
      final source = await _failover.play(
        sources,
        onAttempt: (event) {
          if (_disposed) return;
          _set(_state.copyWith(attempt: event));
        },
      );
      if (_disposed) return;
      // v0.3.6+42: health_score 动态恢复 — 成功后加分
      unawaited(CctvSourcePicker.recordSuccess(source));
      _set(
        _state.copyWith(
          status: PlayerStatus.playing,
          currentSource: source,
          clearAttempt: true,
        ),
      );
    } on AllSourcesFailedException catch (e) {
      if (_disposed) {
        _playing = false;
        return;
      }
      // v0.3.6+42: health_score 动态恢复 — 所有源失败时, 给每个失败源扣分
      for (final attempt in e.attempts) {
        unawaited(CctvSourcePicker.recordFailure(attempt.url));
      }
      // v0.3.6+49: CCTV 频道全部失败时, 明确告知公开网络缺稳定明文源.
      final isCctvChannel = channel.id.startsWith('CCTV') &&
          CctvSourcePicker.isCctvMainChannel(channel);
      final errorMsg = isCctvChannel
          ? 'CCTV 频道在公开网络上很少有长期稳定的明文流。\n'
              '建议：跳到卫视频道观看（点下方返回 / 换台），或联系作者自建源。'
          : e.toString();
      _set(
        _state.copyWith(
          status: PlayerStatus.error,
          error: errorMsg,
          clearAttempt: true,
        ),
      );
    } finally {
      _playing = false;
    }
  }

  /// 6/17 v0.2.3 P0-4: 错误时给用户「换源」入口 — 直接播放指定 URL, 不走
  /// SourceFailover 自动选源.  适用: 央视源抽风时手动指定备份源.
  ///
  /// 当前 channel 用 [channel] 表示; 如果没传, 保持原 channel (例如切到
  /// 同一频道的另一路源,  channel 不变).
  Future<void> playSingleSource(String url, {Channel? channel}) async {
    if (_disposed) return;
    final ch = channel ?? _state.channel;
    if (ch == null) {
      // 没有 channel 上下文, 只能假定这是个 raw URL,  跳过错 channel 的检查
      _set(
        _state.copyWith(
          status: PlayerStatus.error,
          error: 'playSingleSource: 无频道上下文',
          clearAttempt: true,
        ),
      );
      return;
    }

    // 6/17 修声音残留: 跟 [play] 一样,  先 stop 旧 player 避免双声
    if (_player != null) {
      await _player.stop();
    }

    _set(
      _state.copyWith(
        status: PlayerStatus.loading,
        channel: ch,
        clearError: true,
        clearAttempt: true,
      ),
    );

    try {
      final ok = await _failover.playSingle(url);
      if (_disposed) return;
      // v0.3.10.17: 记录单源结果, 更新评分
      await _router.recordResult(url, ok);
      if (ok) {
        // v0.3.6+42: health_score 动态恢复 — 单源成功后加分
        unawaited(CctvSourcePicker.recordSuccess(url));
        _set(
          _state.copyWith(
            status: PlayerStatus.playing,
            currentSource: url,
            clearAttempt: true,
          ),
        );
      } else {
        // v0.3.6+42: health_score 动态恢复 — 单源失败扣分
        unawaited(CctvSourcePicker.recordFailure(url));
        _set(
          _state.copyWith(
            status: PlayerStatus.error,
            error: '该源无法打开: $url',
            currentSource: url,
            clearAttempt: true,
          ),
        );
      }
    } catch (e) {
      if (_disposed) return;
      _set(
        _state.copyWith(
          status: PlayerStatus.error,
          error: '单源播放失败: $e',
          currentSource: url,
          clearAttempt: true,
        ),
      );
    }
  }

  /// 暂停 (切后台 / 多窗口 / 来电时调)
  /// 6/18 P3-1: AppLifecycleState.paused/inactive/hidden 都调这个.
  /// 媒体 native 端只 stop 推 PCM, 不释放 libmpv 实例,  速度快 ( < 50ms),
  /// 回到前台调 play() 即可恢复.
  Future<void> pause() async {
    if (_disposed) return;
    // v0.3.10.11: fallback / 无 native player 都 noop.
    if (_player == null) {
      _fallbackPlayer?.pause();
      return;
    }
    await _player.pause();
    // 不改 _state.status: 业务层觉得还在 "playing",  只是底层暂停
    // 推流.  UI 显示可以靠 AppLifecycle 自己处理.
  }

  /// 停止播放
  Future<void> stop() async {
    if (_disposed) return;
    // v0.3.10.11: fallback / 无 native player 都 noop.
    if (_player == null) {
      _fallbackPlayer?.stop();
      _set(const PlayerState.idle());
      return;
    }
    // 6/17: 同步停掉 native player, 不只是改 UI 状态
    await _player.stop();
    _set(const PlayerState.idle());
  }

  @override
  void dispose() {
    _disposed = true;
    // 6/17: native player 必须显式 dispose 释放 libmpv 资源.
    // ChangeNotifier.dispose() 同步返回, 但 media_kit 的 Player.stop/dispose
    // 是 async — 这里 fire-and-forget,  native 端在 isolate 拆完 native
    // handle 后自动释放.  测试环境 PlayerService 创建时 player 传 null,
    // 这边不调.  实际使用 Player.stop() / dispose() 都是 libmpv 命令, < 50ms.
    if (_player != null) {
      unawaited(_player.stop());
      unawaited(_player.dispose());
    }
    super.dispose();
  }

  void _set(PlayerState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }
}

// ───────────────────────────── Riverpod ─────────────────────────────

/// v0.3.10.11 (6/23 老板反馈 腾讯极光盒子 6 v0.3.10.8 闪退):
/// libmpv.so 在某些 TV box (Amlogic S905X3 等) 加载失败时的 fallback 播放器.
///
/// 实现走 platform channel `com.threelive.iptv/fallback_player` —
/// native 端 (MainActivity.kt) 应该注册 MethodChannel handler,  用 Android
/// MediaPlayer API 打开 url.  当前 native 端可能还没注册,  所以 play() 会
/// 静默失败 — 但关键是 APP 不再闪退,  CrashLogger 会记 platform_error.
///
/// Channel 协议:
///   - play({url: String}) -> bool
///   - stop() -> void
///   - pause() -> void
///   - resume() -> void
class FallbackMediaPlayer {
  FallbackMediaPlayer();

  // 注意: channel name 跟 MainActivity 一致.  当前 MainActivity 没注册,
  // invokeMethod 会抛 MissingPluginException — 我们 catch 静默.
  static const _channel = MethodChannel('com.threelive.iptv/fallback_player');

  Future<bool> play(String url) async {
    try {
      final result = await _channel.invokeMethod<bool>('play', {'url': url});
      return result ?? false;
    } catch (e) {
      debugPrint('FallbackMediaPlayer.play failed: $e');
      await CrashLogger.log('FallbackMediaPlayer.play failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('FallbackMediaPlayer.stop failed: $e');
      // 不写 CrashLogger — 暂停/停止频繁调用, log 会爆.
    }
  }

  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (e) {
      debugPrint('FallbackMediaPlayer.pause failed: $e');
    }
  }

  Future<void> resume() async {
    try {
      await _channel.invokeMethod('resume');
    } catch (e) {
      debugPrint('FallbackMediaPlayer.resume failed: $e');
    }
  }
}

/// 共享的 [Player] 实例 (整个 APP 一个 native player)
///
/// v0.3.10.16: libmpv 可用性标志 — main() 里通过 MethodChannel 预检后写入.
/// true = 可以调 MediaKit.ensureInitialized(), false = 直接走 Fallback.
final libmpvAvailableProvider = Provider<bool>((ref) => true);

/// v0.3.10.14: MediaKit.ensureInitialized() + Player() 全部从 main() 移到这里.
/// main() 里调会触发 native SIGSEGV (libmpv.so dlopen 失败) 直接杀进程,
/// Dart try-catch 捕获不到.  移到这里后只在用户进播放页时才触发,
/// 首页/频道列表/设置页都不受影响.
/// v0.3.10.16: 先读 libmpvAvailableProvider, 不可用直接返 null (走 Fallback).
final mediaKitPlayerProvider = Provider<Player?>((ref) {
  final available = ref.read(libmpvAvailableProvider);
  if (!available) {
    debugPrint('mediaKitPlayerProvider: libmpv 不可用 (ARM 32-bit?), 走 Fallback');
    unawaited(CrashLogger.log('libmpv not available, using fallback player'));
    return null;
  }
  try {
    MediaKit.ensureInitialized();
    return Player();
  } catch (e, st) {
    debugPrint('mediaKitPlayerProvider: failed: $e\n$st');
    unawaited(CrashLogger.log('Player init failed: $e'));
    return null;
  }
});

/// media_kit 的 video controller (用于 Video widget)
///
/// v0.3.10.11: libmpv 加载失败时 return null.  player_page.dart 检测到 null
/// controller 时不渲染 Video widget,  直接走 ErrorOverlay / 占位.
final mediaKitVideoControllerProvider = Provider<VideoController?>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  if (player == null) return null;
  // v0.3.7+65 (6/19): 显式 hwdec='mediacodec' 强制 Android 原生硬解.
  // 之前默认 'auto-safe' 在部分 Android 13+ 设备 (Pixel / 三星 / 小米新机) 会
  // 走 software fallback  →  H.264 High profile 4.1 1080p 解码慢/失败 → 绿屏.
  // 5G + 1000M 宽带 (老板 15:47 反馈)  速度不是问题,  是 decoder 不走硬件.
  // 'mediacodec' = Android MediaCodec API,  原生硬解,  H.264/H.265/AV1 都支持.
  try {
    // v0.3.10.13: hwdec 从 'mediacodec' 改为 'auto-safe'.
    // 'mediacodec' 在部分 TV box (Amlogic S905X3 / Rockchip 等) 的
    // MediaCodec 实现不完整,  创建 VideoController 或首帧渲染时触发
    // native crash (SIGSEGV).  'auto-safe' 让 libmpv 自动选择最安全的
    // 解码方式 — 优先硬解,  不支持时 fallback 软解,  不会崩.
    // v0.3.10.22: 平板/TV 兼容性 — 先尝试 'auto-safe',  如果
    // VideoController 创建成功但后续渲染异常 (有声音没画面),
    // 会在 VideoArea 层 fallback 到 cover fit.
    // 之前老板 6/26 反馈平板有声音没画面,
    // 根因是 BoxFit.contain 在某些平板 surface 尺寸=0,
    // 不是 hwdec 问题.  这里保留 'auto-safe' 不变.
    return VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-safe',
      ),
    );
  } catch (e, st) {
    debugPrint(
        'mediaKitVideoControllerProvider: VideoController() threw: $e\n$st');
    unawaited(CrashLogger.log('VideoController() construction failed: $e'));
    return null;
  }
});

/// [StreamOpener] — 默认走 media_kit 真实实现
///
/// v0.3.10.11: player == null (libmpv 加载失败) 时返回一个 noop opener,
/// SourceFailover 调它时直接 fail.  这样 play() 走到 _player==null 分支
/// 报 "本机播放器不可用" 错误, 不会尝试用 libmpv 打开流.
final streamOpenerProvider = Provider<StreamOpener>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  if (player == null) {
    return _NoopStreamOpener();
  }
  return MediaKitStreamOpener(player);
});

/// v0.3.10.11: libmpv 不可用时的 fallback opener — 所有 open 立即 fail.
class _NoopStreamOpener implements StreamOpener {
  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    await CrashLogger.log('_NoopStreamOpener.open($url) — libmpv unavailable');
    return false;
  }

  @override
  Future<void> cancel(String url) async {}
}

/// [PlayerService] — 全局单例
final playerServiceProvider = ChangeNotifierProvider<PlayerService>((ref) {
  final opener = ref.watch(streamOpenerProvider);
  final player = ref.watch(mediaKitPlayerProvider);
  // 6/17 fix: 之前 ref.onDispose(svc.dispose) 跟 ChangeNotifierProvider
  // auto-dispose 重复,  ProviderContainer 销毁时 svc.dispose() 被调两次,
  // 第二次 super.dispose() 触发 "ChangeNotifier used after being disposed".
  // ChangeNotifierProvider 会自动调 notifier.dispose(),  这里只创建.
  // PlayerService.dispose() 仍然会跑, 负责释放 native player (libmpv 实例).
  // v0.3.10.11: player==null 时 PlayerService 内部自动走 fallback.
  return PlayerService(opener: opener, player: player);
});

/// 当前播放状态
final currentPlayerStateProvider = Provider<PlayerState>((ref) {
  final service = ref.watch(playerServiceProvider);
  return service.state;
});
