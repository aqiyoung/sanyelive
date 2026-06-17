// 卡 6 验证: PlayerService.play 对空 sources 立即报 error, 不让 player 卡死
import 'package:flutter_test/flutter_test.dart';
import 'package:threelive/data/models/channel.dart';
import 'package:threelive/services/player_service.dart';
import 'package:threelive/services/source_failover.dart';

void main() {
  group('PlayerService.play 空 sources', () {
    test('sources 为空 → 立即 set error, 不调 opener', () async {
      final fakeOpener = _CountingOpener();
      final svc = PlayerService(opener: fakeOpener);

      const ch = Channel(
        id: 'NoSources.cn',
        name: 'NoSources',
        country: 'CN',
        categories: <String>['news'],
        // sources 默认 const []
      );

      await svc.play(ch);

      expect(svc.state.status, PlayerStatus.error);
      expect(svc.state.error, '该频道无可用播放源');
      expect(svc.state.channel?.id, 'NoSources.cn');
      expect(fakeOpener.callCount, 0, reason: '空 sources 不应触发 player 加载');
    });

    test('sources 不空但调用失败 → state.error 反映错误', () async {
      final fakeOpener = _CountingOpener(shouldFail: true);
      final svc = PlayerService(opener: fakeOpener);

      const ch = Channel(
        id: 'Bad.cn',
        name: 'Bad',
        country: 'CN',
        categories: <String>['news'],
        sources: <String>['http://nonexistent.example/1.m3u8'],
      );

      await svc.play(ch);

      expect(svc.state.status, PlayerStatus.error);
      expect(svc.state.channel?.id, 'Bad.cn');
    });
  });

  // 6/17 v0.2.3 P0-4: 错误 overlay 「换源」按钮调 playSingleSource
  group('PlayerService.playSingleSource', () {
    test('opener 成功 → state.status = playing, currentSource = url', () async {
      final opener = _CountingOpener();
      final svc = PlayerService(opener: opener);

      const ch = Channel(
        id: 'Good.cn',
        name: 'Good',
        country: 'CN',
        categories: <String>['news'],
        sources: <String>['http://primary', 'http://backup'],
      );
      await svc.playSingleSource('http://backup', channel: ch);

      expect(svc.state.status, PlayerStatus.playing);
      expect(svc.state.currentSource, 'http://backup');
      expect(svc.state.channel?.id, 'Good.cn');
    });

    test('opener 失败 → state.status = error, currentSource 仍为 url', () async {
      final opener = _CountingOpener(shouldFail: true);
      final svc = PlayerService(opener: opener);

      const ch = Channel(
        id: 'Bad.cn',
        name: 'Bad',
        country: 'CN',
        categories: <String>['news'],
        sources: <String>['http://primary', 'http://backup'],
      );
      await svc.playSingleSource('http://backup', channel: ch);

      expect(svc.state.status, PlayerStatus.error);
      expect(svc.state.currentSource, 'http://backup');
      expect(svc.state.error, contains('该源无法打开'));
    });
  });
}

class _CountingOpener implements StreamOpener {
  _CountingOpener({this.shouldFail = false});
  final bool shouldFail;
  int callCount = 0;

  @override
  Future<bool> open(String url, {required Duration timeout}) async {
    callCount++;
    return !shouldFail;
  }
}
