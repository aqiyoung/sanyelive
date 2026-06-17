import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threelive/features/favorites/favorites_service.dart';
import 'package:threelive/widgets/channel_tile.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        // �?6: 用内�?store 避免 sqflite �?test env 报错
        favoritesServiceProvider.overrideWithValue(
          FavoritesService(store: InMemoryFavoritesStore()),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('ChannelTile renders number, name, country', (tester) async {
    await tester.pumpWidget(
      _wrap(const ChannelTile(
        channelNumber: '01',
        channelName: 'CCTV-1',
        country: '中国大陆',
      )),
    );
    expect(find.text('01'), findsOneWidget);
    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('中国大陆'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('ChannelTile hides LIVE badge when isLive is false',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const ChannelTile(
        channelNumber: '02',
        channelName: 'X',
        isLive: false,
      )),
    );
    expect(find.text('LIVE'), findsNothing);
  });
}
