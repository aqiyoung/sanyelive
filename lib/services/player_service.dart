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
    } catch (_) {
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
  }) : _failover = failover ?? SourceFailover(opener: opener);

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

  /// 停止播放
  void stop() {
    if (_disposed) return;
    _set(const PlayerState.idle());
  }

  @override
  void dispose() {
    _disposed = true;
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
final mediaKitPlayerProvider = Provider<Player>((ref) {
  final player = Player();
  ref.onDispose(player.dispose);
  return player;
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
///
/// 注意: [ChangeNotifierProvider] 会自动 dispose ChangeNotifier,
/// 不要重复加 [ref.onDispose] 否则会 double dispose
final playerServiceProvider = ChangeNotifierProvider<PlayerService>((ref) {
  final opener = ref.watch(streamOpenerProvider);
  return PlayerService(opener: opener);
});

/// 当前播放状态 (从 [PlayerService.state] 读)
///
/// 注意: 直接 `ref.watch(playerServiceProvider)` 会自动 rebuild
/// 因为 [ChangeNotifierProvider] 监听 ChangeNotifier 的变化
final currentPlayerStateProvider = Provider<PlayerState>((ref) {
  final service = ref.watch(playerServiceProvider);
  return service.state;
});
