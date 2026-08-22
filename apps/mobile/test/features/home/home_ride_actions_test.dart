import 'package:balloon_crumbs/features/home/home_ride_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ride setup keeps landing controls ahead of search and extras', (
    tester,
  ) async {
    var selectedRadius = 250.0;
    var mapSelectionRequested = false;
    var createRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: StatefulBuilder(
              builder: (context, setState) => HomeRideActions(
                onCreate: () => createRequested = true,
                onJoin: () {},
                onMore: () {},
                onSelectLandingZone: () => mapSelectionRequested = true,
                onCancelSelection: () {},
                onPreviousLandingZones: null,
                onRadiusChanged: (radius) =>
                    setState(() => selectedRadius = radius),
                radiusMeters: selectedRadius,
                recentLandingZoneCount: 0,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Intended landing area'), findsOneWidget);
    expect(find.text('Create flight'), findsOneWidget);
    expect(find.text('Join crew'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);

    await tester.tap(find.text('Set on map'));
    await tester.tap(find.byKey(const Key('landing-radius-500')));
    await tester.tap(find.text('Create flight'));

    expect(mapSelectionRequested, isTrue);
    expect(selectedRadius, 500);
    expect(createRequested, isTrue);
  });
}
