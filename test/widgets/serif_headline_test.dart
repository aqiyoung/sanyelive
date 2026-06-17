import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threelive/widgets/serif_headline.dart';

void main() {
  testWidgets('SerifHeadline renders text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SerifHeadline('三页直播'),
        ),
      ),
    );
    expect(find.text('三页直播'), findsOneWidget);
  });

  testWidgets('SerifHeadline renders subtitle when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SerifHeadline(
            'Title',
            subtitle: 'subtitle text',
          ),
        ),
      ),
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('subtitle text'), findsOneWidget);
  });
}
