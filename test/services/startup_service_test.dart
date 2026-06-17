// �?6 单元测试: StartupService �?InMemorySharedPreferences (�?SharedPreferences mockup �?
// 因为 test env 没装 shared_preferences_android platform channel, �?try/catch 路径
// 这里用真 SharedPreferences (setMockInitialValues) 验证持久化契�?

import 'package:flutter_test/flutter_test.dart';
import 'package:threelive/services/startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('StartupService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('首次启动 �?loadLastChannel 返回 null', () async {
      final svc = StartupService();
      expect(await svc.loadLastChannel(), isNull);
    });

    test('saveLastChannel �?loadLastChannel 读到相同�?, () async {
      final svc = StartupService();
      await svc.saveLastChannel('CCTV1.cn');
      expect(await svc.loadLastChannel(), 'CCTV1.cn');
    });

    test('saveLastChannel 多次 �?保留最后一�?, () async {
      final svc = StartupService();
      await svc.saveLastChannel('A.cn');
      await svc.saveLastChannel('B.cn');
      expect(await svc.loadLastChannel(), 'B.cn');
    });

    test('clearLastChannel �?回到 null', () async {
      final svc = StartupService();
      await svc.saveLastChannel('X.cn');
      await svc.clearLastChannel();
      expect(await svc.loadLastChannel(), isNull);
    });

    test('SharedPreferences 抛错�? �?try/catch 返回 null (优雅降级)', () async {
      // 构造一个会抛错�?loader 模拟 shared_preferences 不可�?
      final svc = StartupService(
        prefsLoader: () => Future.error(Exception('not available')),
      );
      // loadLastChannel 不应抛错
      expect(await svc.loadLastChannel(), isNull);
      // saveLastChannel 也不应抛�?
      await svc.saveLastChannel('Y.cn');
      // clearLastChannel 也不应抛�?
      await svc.clearLastChannel();
    });
  });
}
