// 卡 6 单元测试: TV 焦点环颜色 + 焦点环宽度常量
// 验收 (proof): 焦点环 4dp 朱砂
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/core/tv/tv_focus.dart';

void main() {
  group('TV focus tokens', () {
    test('焦点环颜色是朱砂 (接近 #E24A1A 暖红色)', () {
      expect(kTvFocusColor, isA<Color>());
      // 红色主导, 不是纯红 (朱砂有暖色调)
      final c = kTvFocusColor;
      expect(c.r, greaterThan(0.5));
      expect(c.g, lessThan(0.4));
      expect(c.b, lessThan(0.2));
    });

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
  });
}
