import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threelive/widgets/category_card.dart';

void main() {
  testWidgets('CategoryCard renders title and subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryCard(
            title: '央视',
            subtitle: 'CCTV-1 ~ CCTV-16',
            icon: Icons.tv,
          ),
        ),
      ),
    );
    expect(find.text('央视'), findsOneWidget);
    expect(find.text('CCTV-1 ~ CCTV-16'), findsOneWidget);
    expect(find.byIcon(Icons.tv), findsOneWidget);
  });

  testWidgets('CategoryCard onTap fires callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryCard(
            title: 'Test',
            subtitle: 'Sub',
            icon: Icons.tv,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(CategoryCard));
    expect(tapped, isTrue);
  });
}
