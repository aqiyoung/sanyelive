import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models/channel.dart';
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
  Future<bool> open(String url, {required Duration timeout}) async {
    try {
      // media_kit 的 open 是异步但很快 (通常 < 100ms),
      // 真正的"起播"通过 [Player.stream.playing] 监听, 此处只检查 open 成功与否
      final completer = Completer<bool>();
      late final StreamSubscription<dynamic> sub;
      sub = _player.stream.playing.listen((playing) {
        // 收到任何 playing 状态变化 (true or false) → 视为 open 完成
        if (!completer.isCompleted) {
          sub.cancel();
          completer.complete(true);
        }
      });
      // 兜底: 如果 stream 一直没事件, 在 timeout 后算 open 完成
      Timer(timeout, () {
        if (!completer.isCompleted) {
          sub.cancel();
          // 超时前没收到任何 playing 事件, 视作失败
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
class PlayerService extends ChangeNotifier {
  PlayerService({
    required StreamOpener opener,
    SourceFailover? failover,
    Player? player,
  })  : _player = player,
        _failover = failover ?? SourceFailover(opener: opener);

  /// media_kit 的 native player. 测试环境不传 (== null), 跳过 stop/dispose.
  final Player? _player;
  final SourceFailover _failover;
  bool _disposed = false;

  PlayerState _state = const PlayerState.idle();
  PlayerState get state => _state;

  /// 切到 [channel]; 已在播放则先 stop
  Future<void> play(Channel channel) async {
    if (_disposed) return;
    if (channel.sources.isEmpty) {
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

    // 6/17 修声音残留: media_kit 的 Player.open() 不会自动停掉旧流,
    // 切频道时上一路音频会跟着新流一起响.  这里先 stop() 旧 player,
    // await (不 fire-and-forget):  stop 本身是 libmpv 命令,  < 50ms
    // 返回.  必须在 open() 之前完成,  否则上一路 audio track 还在推 PCM.
    if (_player != null) {
      await _player.stop();
    }

    _set(
      _state.copyWith(
        status: PlayerStatus.loading,
        channel: channel,
        clearError: true,
        clearAttempt: true,
      ),
    );

    try {
      final source = await _failover.play(
        channel.sources,
        onAttempt: (event) {
          if (_disposed) return;
          _set(_state.copyWith(attempt: event));
        },
      );
      if (_disposed) return;
      _set(
        _state.copyWith(
          status: PlayerStatus.playing,
          currentSource: source,
          clearAttempt: true,
        ),
      );
    } on AllSourcesFailedException catch (e) {
      if (_disposed) return;
      _set(
        _state.copyWith(
          status: PlayerStatus.error,
          error: e.toString(),
          clearAttempt: true,
        ),
      );
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

    // 6/17 修声音残留: 跟 [play] 一样, 先 stop 旧 player 避免双声
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
      if (ok) {
        _set(
          _state.copyWith(
            status: PlayerStatus.playing,
            currentSource: url,
            clearAttempt: true,
          ),
        );
      } else {
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
    if (_player != null) {
      await _player.pause();
    }
    // 不改 _state.status: 业务层觉得还在 "playing",  只是底层暂停
    // 推流.  UI 显示可以靠 AppLifecycle 自己处理.
  }

  /// 停止播放
  Future<void> stop() async {
    if (_disposed) return;
    // 6/17: 同步停掉 native player, 不只是改 UI 状态
    if (_player != null) {
      await _player.stop();
    }
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

/// 共享的 [Player] 实例 (整个 APP 一个 native player)
///
/// 6/17 修复合并到 main.dart: 之前 v0.2.0 启动崩
/// 'MediaKit.ensureInitialized must be called', 现在 main 里 await
/// ensureInitialized 同步完成才 runApp, 这里 Player() 不会报这个错.
///
/// 6/17 修声音残留: native player 的 dispose 由 [playerServiceProvider]
/// 间接处理 (PlayerService.dispose() 调 _player.dispose()).  这里
/// 只管创建,  不重复释放.
final mediaKitPlayerProvider = Provider<Player>((ref) {
  return Player();
});

/// media_kit 的 video controller (用于 Video widget)
final mediaKitVideoControllerProvider = Provider<VideoController>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  return VideoController(player);
});

/// [StreamOpener] — 默认走 media_kit 真实实现
final streamOpenerProvider = Provider<StreamOpener>((ref) {
  final player = ref.watch(mediaKitPlayerProvider);
  return MediaKitStreamOpener(player);
});

/// [PlayerService] — 全局单例
final playerServiceProvider = ChangeNotifierProvider<PlayerService>((ref) {
  final opener = ref.watch(streamOpenerProvider);
  final player = ref.watch(mediaKitPlayerProvider);
  // 6/17 fix: 之前 ref.onDispose(svc.dispose) 跟 ChangeNotifierProvider
  // auto-dispose 重复,  ProviderContainer 销毁时 svc.dispose() 被调两次,
  // 第二次 super.dispose() 触发 "ChangeNotifier used after being disposed".
  // ChangeNotifierProvider 会自动调 notifier.dispose(),  这里只创建.
  // PlayerService.dispose() 仍然会跑, 负责释放 native player (libmpv 实例).
  return PlayerService(opener: opener, player: player);
});

/// 当前播放状态
final currentPlayerStateProvider = Provider<PlayerState>((ref) {
  final service = ref.watch(playerServiceProvider);
  return service.state;
});
