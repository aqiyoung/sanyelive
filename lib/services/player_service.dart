import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../data/cctv_source.dart';
import '../data/models/channel.dart';
import '../data/source_dispatcher.dart';
import '../services/platform/fallback_player.dart';
import 'smart_source_router.dart';
import 'source_failover.dart';

/// 播放状态。
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

/// 不可变的播放状态快照。
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

/// 全局播放服务单例: 持有唯一 [Player], 调用 [SourceFailover] 选源, 暴露
/// [state] 给 UI 监听。播放内核的创建/装配在 [player_providers.dart]。
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
              perSourceTimeout: const Duration(milliseconds: 800),
            ),
        _fallbackPlayer =
            fallbackPlayer ?? (player == null ? FallbackMediaPlayer() : null);

  final Player? _player;
  final SourceFailover _failover;
  final SmartSourceRouter _router;
  final FallbackMediaPlayer? _fallbackPlayer;
  bool _disposed = false;

  /// 每次 [play] 自增; 仅"最新一代"的播放结果会写入状态, 旧切换被覆盖.
  int _playGeneration = 0;

  bool get useFallbackPlayer => _player == null && _fallbackPlayer != null;

  PlayerState _state = const PlayerState.idle();
  PlayerState get state => _state;

  String? get currentUrl => _state.currentSource;

  /// 立即进入 loading, 不等 channelsProvider / addPostFrameCallback,
  /// 让 PlayerPage 第一帧就显示 "正在打开…"。
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

  /// 切到 [channel]。采用"后到覆盖"策略: 切换进行中又切了一次, 旧的
  /// 结果会被丢弃 ([_playGeneration] 比对), 不再用 `_playing` 直接丢弃新请求
  /// (那样会导致"点了没反应 / 卡在转圈")。
  ///
  /// loading 状态在 open 之前同步发出, UI 立即进入 loading overlay。
  Future<void> play(Channel channel) async {
    if (_disposed) return;
    final myGen = ++_playGeneration;

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

    _set(
      _state.copyWith(
        status: PlayerStatus.loading,
        channel: channel,
        clearError: true,
        clearAttempt: true,
      ),
    );

    // 进播放页必须恢复音量 (首页 Hero 预览可能静音)。
    // 不显式 stop(): player.open(newUrl) 会替换当前流, 避免多余往返;
    // 也让新切换能直接接管, 不被旧 stop 误杀当前正在起播的流。
    if (_player != null) {
      await _player.setVolume(100);
    }

    try {
      final source = await _failover.play(
        sources,
        onAttempt: (event) {
          if (_disposed || myGen != _playGeneration) return;
          _set(_state.copyWith(attempt: event));
        },
        shouldAbort: () => myGen != _playGeneration,
      );
      if (myGen != _playGeneration) return; // 已被更新的切换覆盖
      if (_disposed) return;
      unawaited(CctvSourcePicker.recordSuccess(source));
      _set(
        _state.copyWith(
          status: PlayerStatus.playing,
          currentSource: source,
          clearAttempt: true,
        ),
      );
    } on SourcePlayAbortedException {
      return; // 被新切换打断, 不更新状态
    } on AllSourcesFailedException catch (e) {
      if (myGen != _playGeneration) return; // 已被更新的切换覆盖
      if (_disposed) return;
      for (final attempt in e.attempts) {
        unawaited(CctvSourcePicker.recordFailure(attempt.url));
      }
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
    }
  }

  /// 手动指定单源播放, 用于央视源抽风时换源。
  Future<void> playSingleSource(String url, {Channel? channel}) async {
    if (_disposed) return;
    final ch = channel ?? _state.channel;
    if (ch == null) {
      _set(
        _state.copyWith(
          status: PlayerStatus.error,
          error: 'playSingleSource: 无频道上下文',
          clearAttempt: true,
        ),
      );
      return;
    }

    if (_player != null) {
      await _player.setVolume(100);
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
      await _router.recordResult(url, ok);
      if (ok) {
        unawaited(CctvSourcePicker.recordSuccess(url));
        _set(
          _state.copyWith(
            status: PlayerStatus.playing,
            currentSource: url,
            clearAttempt: true,
          ),
        );
      } else {
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

  /// 切后台/多窗口/来电时暂停推流; 不改 _state.status, 业务层仍认为在 playing。
  Future<void> pause() async {
    if (_disposed) return;
    if (_player == null) {
      _fallbackPlayer?.pause();
      return;
    }
    await _player.pause();
  }

  /// 停止播放并释放 libmpv 推流。
  Future<void> stop() async {
    if (_disposed) return;
    if (_player == null) {
      _fallbackPlayer?.stop();
      _set(const PlayerState.idle());
      return;
    }
    await _player.stop();
    _set(const PlayerState.idle());
  }

  @override
  void dispose() {
    _disposed = true;
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
