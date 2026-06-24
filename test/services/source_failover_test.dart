// 卡 5: SourceFailover 单元测试
// 验证: 多源切换、超时、退避
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanyelive/data/models/channel.dart';
import 'package:sanyelive/services/player_service.dart';
import 'package:sanyelive/services/source_failover.dart';

void main() {
  // v0.3.7+55: 之前的测试会因为 CctvSourcePicker.recordFailure 调用
  // SharedPreferences.getInstance() 而报 "Binding has not yet been
  // initialized" — 因为 recordFailure 在失败时持久化 health_score.
  // PlayerService.play() 失败路径会触发这条.  加 setUp mock 一下.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SourceFailover.play', () {
    test('第一个源成功 → 立即返回第一个', () async {
      final opener = _ScriptedOpener([
        const _ScriptedResult.success(),
      ]);
      final failover = SourceFailover(
        opener: opener,
        perSourceTimeout: const Duration(milliseconds: 500),
      );

      final result = await failover.play(['http://a']);
      expect(result, 'http://a');
      expect(opener.calls, ['http://a']);
    });

    test('源 1 失败 → 切到源 2 成功', () async {
      final opener = _ScriptedOpener([
        const _ScriptedResult.failure(),
        const _ScriptedResult.success(),
      ]);
      final failover = SourceFailover(
        opener: opener,
        perSourceTimeout: const Duration(milliseconds: 500),
      );

      final result = await failover.play(['http://a', 'http://b']);
      expect(result, 'http://b');
      expect(opener.calls, ['http://a', 'http://b']);
    });

    test('源 1 超时 → 切到源 2 成功', () async {
      final opener = _ScriptedOpener([
        const _ScriptedResult.timeout(),
        const _ScriptedResult.success(),
      ]);
      final failover = SourceFailover(
        opener: opener,
        perSourceTimeout: const Duration(milliseconds: 50),
      );

      final result = await failover.play(['http://slow', 'http://fast']);
      expect(result, 'http://fast');
    });

    test('源 1 抛异常 → 切到源 2 成功 (不中断)', () async {
      final opener = _ScriptedOpener([
        _ScriptedResult.throwError(Exception('net error')),
        const _ScriptedResult.success(),
      ]);
      final failover = SourceFailover(
        opener: opener,
        perSourceTimeout: const Duration(milliseconds: 500),
      );

      final result = await failover.play(['http://a', 'http://b']);
      expect(result, 'http://b');
    });

    test('所有源都失败 → 抛 AllSourcesFailedException, 列出所有尝试', () async {
      final opener = _ScriptedOpener([
        const _ScriptedResult.failure(),
        const _ScriptedResult.timeout(),
        _ScriptedResult.throwError(Exception('oops')),
      ]);
      final failover = SourceFailover(
        opener: opener,
        perSourceTimeout: const Duration(milliseconds: 50),
      );

      try {
        await failover.play(['http://1', 'http://2', 'http://3']);
        fail('应抛 AllSourcesFailedException');
      } on AllSourcesFailedException catch (e) {
        expect(e.attempts.length, 3);
        expect(e.attempts[0].url, 'http://1');
        // opener 返回 false → 包装为 "opener returned false"
        expect(e.attempts[0].error, contains('opener returned false'));
        expect(e.attempts[1].url, 'http://2');
        // 超时
        expect(e.attempts[1].error, contains('timeout'));
        expect(e.attempts[2].url, 'http://3');
        // 异常透传
        expect(e.attempts[2].error, contains('oops'));
      }
    });

    test('空源列表 → 抛 AllSourcesFailedException', () async {
      final opener = _ScriptedOpener([]);
      final failover = SourceFailover(opener: opener);
      expect(
        () => failover.play([]),
        throwsA(isA<AllSourcesFailedException>()),
      );
    });

    test('onAttempt 回调: 每次切换前触发, 含 index/total/url', () async {
      final opener = _ScriptedOpener([
        const _ScriptedResult.failure(),
        const _ScriptedResult.failure(),
        const _ScriptedResult.success(),
      ]);
      final failover = SourceFailover(
        opener: opener,
        perSourceTimeout: const Duration(milliseconds: 200),
      );

      final events = <SourceAttemptEvent>[];
      final result = await failover.play(
        ['u1', 'u2', 'u3'],
        onAttempt: events.add,
      );
      expect(result, 'u3');
      expect(events.length, 3);
      expect(events[0].index, 1);
      expect(events[0].total, 3);
      expect(events[0].url, 'u1');
      expect(events[1].index, 2);
      expect(events[2].index, 3);
    });
  });

  group('PlayerService + SourceFailover 集成', () {
    test('空频道 → 直接 error 状态, 不调用 opener', () async {
      final opener = _ScriptedOpener([]);
      final service = PlayerService(opener: opener);
      final channel =
          _FakeChannel(id: 'Empty.cn', sources: const []).toChannel();
      await service.play(channel);
      expect(service.state.status, PlayerStatus.error);
      expect(opener.calls, isEmpty);
    });

    test('正常播放: 源 1 失败 → 源 2 成功 → playing 状态', () async {
      final opener = _ScriptedOpener([
        const _ScriptedResult.failure(),
        const _ScriptedResult.success(),
      ]);
      final service = PlayerService(opener: opener);
      final channel = _FakeChannel(
        id: 'Test.cn',
        sources: const ['http://1', 'http://2'],
      ).toChannel();

      await service.play(channel);
      expect(service.state.status, PlayerStatus.playing);
      expect(service.state.currentSource, 'http://2');
      expect(service.state.channel, isNotNull);
      expect(service.state.channel!.id, 'Test.cn');
    });

    test('所有源失败 → error 状态, error 信息包含尝试数', () async {
      final opener = _ScriptedOpener([
        const _ScriptedResult.failure(),
        const _ScriptedResult.failure(),
      ]);
      final service = PlayerService(opener: opener);
      final channel = _FakeChannel(
        id: 'AllFail.cn',
        sources: const ['http://a', 'http://b'],
      ).toChannel();

      await service.play(channel);
      expect(service.state.status, PlayerStatus.error);
      expect(service.state.error, contains('AllSourcesFailedException'));
      expect(service.state.error, contains('http://a'));
      expect(service.state.error, contains('http://b'));
    });
  });

  // 6/17 v0.2.3 P0-4: playSingle 为「换源」按钮提供单源播放能力
  group('SourceFailover.playSingle', () {
    test('单源成功 → 返回 true', () async {
      final opener = _ScriptedOpener([const _ScriptedResult.success()]);
      final failover = SourceFailover(
        opener: opener,
        perSourceTimeout: const Duration(milliseconds: 500),
      );
      expect(await failover.playSingle('http://x'), isTrue);
      expect(opener.calls, ['http://x']);
    });

    test('单源 opener 返回 false → 返回 false (不抛)', () async {
      final opener = _ScriptedOpener([const _ScriptedResult.failure()]);
      final failover = SourceFailover(opener: opener);
      expect(await failover.playSingle('http://x'), isFalse);
    });

    test('单源 opener 抛异常 → 返回 false (不向上传)', () async {
      final opener = _ScriptedOpener(
        [_ScriptedResult.throwError(Exception('http 500'))],
      );
      final failover = SourceFailover(opener: opener);
      expect(await failover.playSingle('http://x'), isFalse);
    });
  });
}

// ───────────────────────────── Test doubles ─────────────────────────────

/// 一个 _ScriptedResult 表示: opener.open() 一次调用的预期行为
class _ScriptedResult {
  const _ScriptedResult.success()
      : _throwError = null,
        _timeout = false,
        _success = true;
  const _ScriptedResult.failure()
      : _throwError = null,
        _timeout = false,
        _success = false;
  const _ScriptedResult.timeout()
      : _throwError = null,
        _timeout = true,
        _success = true;
  const _ScriptedResult.throwError(Object error)
      : _throwError = error,
        _timeout = false,
        _success = true;

  final bool _success;
  final bool _timeout;
  final Object? _throwError;
}

/// 脚本化的 StreamOpener, 按顺序返回预设结果
class _ScriptedOpener implements StreamOpener {
  _ScriptedOpener(this._scripted);
  final List<_ScriptedResult> _scripted;
  int _idx = 0;
  final List<String> calls = [];

  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    calls.add(url);
    final i = _idx++;
    if (i >= _scripted.length) {
      throw StateError('No more scripted results for $url');
    }
    final r = _scripted[i];
    if (r._throwError != null) {
      // 等一个微小时间避免在 zero-ms timeout 下被超时掩盖
      await Future<void>.delayed(const Duration(milliseconds: 1));
      // ignore: only_throw_errors
      throw r._throwError;
    }
    if (r._timeout) {
      // 模拟 "超过 timeout 还没出来", 通过自己 await > timeout 实现
      await Future<void>.delayed(timeout + const Duration(milliseconds: 10));
      // 实际上 Future.delayed 完成了, 但我们要抛 TimeoutException
      // 模拟 opener 内部超时的行为
      throw TimeoutException('scripted timeout for $url');
    }
    // success / failure
    await Future<void>.delayed(const Duration(milliseconds: 1));
    return r._success;
  }

  @override
  Future<void> cancel(String url) async {}
}

/// 简化版 Channel, 用于测试 (用 freezed Channel 的 toJson 构造)
class _FakeChannel {
  _FakeChannel({required this.id, required this.sources});
  final String id;
  final List<String> sources;
  Channel toChannel() => Channel.fromJson(<String, dynamic>{
        'id': id,
        'name': id,
        'country': 'CN',
        'categories': ['general'],
        'sources': sources,
      });
}
