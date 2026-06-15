import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iptv_app/widgets/channel_tile.dart';

void main() {
  testWidgets('ChannelTile renders number, name, country', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChannelTile(
            channelNumber: '01',
            channelName: 'CCTV-1',
            country: '中国大陆',
          ),
        ),
      ),
    );
    expect(find.text('01'), findsOneWidget);
    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('中国大陆'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('ChannelTile hides LIVE badge when isLive is false',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChannelTile(
            channelNumber: '02',
            channelName: 'X',
            isLive: false,
          ),
        ),
      ),
    );
    expect(find.text('LIVE'), findsNothing);
  });
}
