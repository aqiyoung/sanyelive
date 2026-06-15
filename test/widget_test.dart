import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iptv_app/main.dart';

void main() {
  testWidgets('App boots and shows home page', (WidgetTester tester) async {
    await tester.pumpWidget(const IptvApp());
    expect(find.text('IPTV'), findsWidgets);
    expect(find.text('Scaffold ready - awaiting features'), findsOneWidget);
  });
}
