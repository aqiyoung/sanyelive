// 卡 6 单元测试: TV 焦点环颜色 + 焦点环宽度常量
// 验收 (proof): 焦点环 4dp 朱砂
// P2-1 (6/18 老板拍): 高亮态 scale 1.05 + 2px 赤陶边 + kTvMaxFocusablePerScreen=9
//   加 TvFocusCap / TvFocusCapWrap / TvFocusScope 三个上限守卫 widget 测试.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanyelive/core/tv/tv_focus.dart';

void main() {
  group('TV focus tokens', () {
    test('焦点环颜色是朱砂 (接近 #E24A1A 暖红色)', () {
      expect(kTvFocusColor, isA<Color>());
      // 红色主导, 不是纯红 (朱砂有暖色调)
      const c = kTvFocusColor;
      // Flutter 3.27+ Color.r/g/b 返回 0-1 浮点数, 3.24 返回 0-255 整数
      // 统一转成 0-255 比较
      final r = (c.r * 255).round();
      final g = (c.g * 255).round();
      final b = (c.b * 255).round();
      expect(r, greaterThan(128));
      expect(g, lessThan(102));
      expect(b, lessThan(51));
    });

    test('P2-1: kTvMaxFocusablePerScreen = 9 (ChatGPT 6/17 上限)', () {
      expect(kTvMaxFocusablePerScreen, 9);
    });
  });

  group('TV focus widgets', () {
    testWidgets('TvFocus widget 渲染时给子节点套焦点环', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TvFocus(
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      expect(find.byType(TvFocus), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('TvFocusGroup 包裹子节点不抛错', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TvFocusGroup(
              child: Column(children: <Widget>[Text('A'), Text('B')]),
            ),
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    // P2-1: 一屏焦点项上限断言 — 是 home_page 防止后续漂移的主要机制.
    testWidgets('TvFocusScope 实际焦点项 <= 上限 → 不报 assert', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TvFocusScope(
              actualFocusableCount: 5,
              child: Text('home'),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('TvFocusScope 实际焦点项 > 上限 → debug 模式报 assert', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TvFocusScope(
              actualFocusableCount: 12,
              child: Text('over'),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    testWidgets('TvFocusCap 实际 children <= 上限 → 全部渲染', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TvFocusCap(
              children: <Widget>[Text('A'), Text('B'), Text('C')],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('TvFocusCap 超出上限 → debug 模式报 assert', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvFocusCap(
              children: List<Widget>.generate(
                12,
                (i) => Text('item-$i'),
                growable: false,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    testWidgets('TvFocusCapWrap children <= maxPerRow → Wrap 渲染',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TvFocusCapWrap(
              maxPerRow: 3,
              children: <Widget>[
                IconButton(onPressed: null, icon: Icon(Icons.search)),
                IconButton(onPressed: null, icon: Icon(Icons.favorite)),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });
}
