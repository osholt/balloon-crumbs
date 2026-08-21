import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/controllers/ride_simulation_controller.dart';
import 'package:balloon_crumbs/controllers/situational_awareness_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/features/simulation/ride_simulation_screen.dart';

void main() {
  testWidgets('Ride Lab disables motion before the leader starts the ride', (
    tester,
  ) async {
    final session = RideSession(
      rideId: 'staged-sim-ride',
      rideCode: 'SIM123',
      inviteSecret: 'simulation-secret-that-is-long-enough',
      joinToken: 'test-join-token-0123456789',
      localRiderId: 'lead',
      displayName: 'Demo Lead',
      role: RideRole.lead,
      joinedAt: DateTime.utc(2026, 7, 17),
      isSimulation: true,
    );
    const route = [
      GeoPoint(latitude: 51, longitude: -1),
      GeoPoint(latitude: 51, longitude: -0.9),
    ];
    final awareness = SituationalAwarenessController(
      InMemoryEventStore(),
      session,
      route: route,
      rideStarted: false,
    );
    await awareness.initialize();
    final simulation = RideSimulationController(
      awareness,
      session: session,
      route: route,
      tickInterval: const Duration(days: 1),
      rideStarted: false,
    );
    await simulation.initialize();
    addTearDown(() {
      simulation.dispose();
      awareness.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RideSimulationScreen(
          controller: simulation,
          onRestart: () async {},
          onExit: () async {},
          onRoleChanged: (role) async => simulation.setLocalRole(role),
          onRiderCountChanged: (_) async {},
        ),
      ),
    );

    expect(find.text('READY'), findsOneWidget);
    expect(find.text('Waiting for start'), findsOneWidget);
    final playButton = tester.widget<FilledButton>(
      find.byKey(const Key('simulation-play-pause')),
    );
    expect(playButton.onPressed, isNull);
  });

  testWidgets('Ride Lab presents the live two-craft demo in landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = RideSession(
      rideId: 'sim-ride',
      rideCode: 'SIM123',
      inviteSecret: 'simulation-secret-that-is-long-enough',
      joinToken: 'test-join-token-0123456789',
      localRiderId: 'lead',
      displayName: 'Demo Lead',
      role: RideRole.lead,
      joinedAt: DateTime.utc(2026, 7, 17),
      isSimulation: true,
    );
    const route = [
      GeoPoint(latitude: 51, longitude: -1),
      GeoPoint(latitude: 51, longitude: -0.9),
    ];
    final awareness = SituationalAwarenessController(
      InMemoryEventStore(),
      session,
      route: route,
    );
    await awareness.initialize();
    final simulation = RideSimulationController(
      awareness,
      session: session,
      route: route,
      tickInterval: const Duration(days: 1),
    );
    await simulation.initialize();
    addTearDown(() {
      simulation.dispose();
      awareness.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RideSimulationScreen(
          controller: simulation,
          onRestart: () async {},
          onExit: () async {},
          onRoleChanged: (role) async => simulation.setLocalRole(role),
          onRiderCountChanged: (_) async {},
        ),
      ),
    );

    expect(find.text('Ride Lab'), findsOneWidget);
    expect(find.text('LIVE DEMO CRAFT'), findsOneWidget);
    expect(find.text('Balloon'), findsWidgets);
    expect(find.text('Land Rover'), findsOneWidget);
    expect(find.byKey(const Key('simulation-off-route')), findsNothing);
    expect(find.byKey(const Key('simulation-role')), findsOneWidget);
    expect(find.text('Chase'), findsOneWidget);
    expect(find.byKey(const Key('simulation-rider-count')), findsNothing);

    await tester.ensureVisible(find.text('Chase'));
    await tester.tap(find.text('Chase'));
    await tester.pump();
    expect(simulation.localRole, RideRole.rider);

    expect(tester.takeException(), isNull);
  });
}
