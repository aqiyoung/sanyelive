// �?6 单元测试: FavoritesService �?InMemoryFavoritesStore (�?sqflite)
// 验证 toggle / isFavorite / getAll 契约
import 'package:flutter_test/flutter_test.dart';
import 'package:threelive/features/favorites/favorites_service.dart';

void main() {
  group('FavoritesService (InMemoryFavoritesStore)', () {
    test('初始: getAll �? isFavorite 全部 false', () async {
      final svc = FavoritesService(store: InMemoryFavoritesStore());
      expect(await svc.getAll(), isEmpty);
      expect(await svc.isFavorite('CCTV1.cn'), isFalse);
    });

    test('toggle 一�? false �?true, 持久化到 store', () async {
      final store = InMemoryFavoritesStore();
      final svc = FavoritesService(store: store);
      final isFav = await svc.toggle('CCTV1.cn', 'CCTV-1');
      expect(isFav, isTrue);
      expect(await svc.isFavorite('CCTV1.cn'), isTrue);
      expect(await store.getAll(), ['CCTV1.cn']);
    });

    test('toggle 第二�? true �?false', () async {
      final store = InMemoryFavoritesStore();
      final svc = FavoritesService(store: store);
      await svc.toggle('CCTV1.cn', 'CCTV-1');
      final isFav = await svc.toggle('CCTV1.cn', 'CCTV-1');
      expect(isFav, isFalse);
      expect(await svc.isFavorite('CCTV1.cn'), isFalse);
      expect(await store.getAll(), isEmpty);
    });

    test('收藏 5 个频�? 全部持久�? getAll 全部包含', () async {
      final store = InMemoryFavoritesStore();
      final svc = FavoritesService(store: store);
      // 验收 (proof): 收藏 5 个频�? 重启 APP 仍在
      await svc.toggle('CCTV1.cn', 'CCTV-1');
      await svc.toggle('CCTV2.cn', 'CCTV-2');
      await svc.toggle('CCTV3.cn', 'CCTV-3');
      await svc.toggle('HunanTV.cn', 'Hunan TV');
      await svc.toggle('BeijingTV.cn', 'Beijing TV');

      final all = await svc.getAll();
      expect(all.length, 5);
      expect(all.toSet(), {
        'CCTV1.cn',
        'CCTV2.cn',
        'CCTV3.cn',
        'HunanTV.cn',
        'BeijingTV.cn',
      });
    });

    test('remove 单个频道: 剩余保持', () async {
      final store = InMemoryFavoritesStore();
      final svc = FavoritesService(store: store);
      await svc.toggle('A.cn', 'A');
      await svc.toggle('B.cn', 'B');
      await svc.remove('A.cn');
      expect(await svc.getAll(), ['B.cn']);
    });

    test('getAll 按添加时间倒序', () async {
      final store = InMemoryFavoritesStore();
      final svc = FavoritesService(store: store);
      await svc.toggle('First.cn', 'First');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await svc.toggle('Second.cn', 'Second');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await svc.toggle('Third.cn', 'Third');
      final all = await svc.getAll();
      expect(all, ['Third.cn', 'Second.cn', 'First.cn']);
    });
  });
}
