import 'package:balloon_crumbs/controllers/ride_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/data/in_memory_session_store.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/features/ride/flight_assignment_screen.dart';
import 'package:balloon_crumbs/services/nearby_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RideController> restoreLegacy(RideRole role) async {
    final sessions = InMemorySessionStore();
    final persisted =
        RideSession(
            rideId: 'legacy-flight',
            rideCode: '123456',
            inviteSecret: 'legacy-secret-with-enough-entropy',
            joinToken: 'legacy-token-with-enough-entropy',
            localRiderId: 'legacy-device',
            displayName: 'Alex',
            role: role,
            joinedAt: DateTime.utc(2026, 8, 1),
          ).toJson()
          ..remove('flightRole')
          ..remove('localCraftId');
    await sessions.save(RideSession.fromJson(persisted));
    var id = 0;
    final controller = RideController(
      InMemoryEventStore(),
      sessions,
      const _FakeNearbyBridge(),
      idFactory: () => 'event-${id++}',
      clock: () => DateTime.utc(2026, 8, 23),
    );
    await controller.initialize();
    return controller;
  }

  testWidgets('a legacy creator gets an explicit pilot restore gate', (
    tester,
  ) async {
    final controller = await restoreLegacy(RideRole.lead);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: FlightAssignmentScreen(controller: controller)),
    );

    expect(find.text('Restore this phone as the pilot'), findsOneWidget);
    expect(find.text('Restore pilot view'), findsOneWidget);
    expect(find.byKey(const Key('repair-role-chaseDriver')), findsNothing);
    await tester.tap(find.byKey(const Key('confirm-flight-assignment')));
    await tester.pumpAndSettle();

    expect(controller.localFlightRole, FlightRole.pilot);
    expect(controller.hasFlightAuthority, isTrue);
    expect(controller.session!.requiresFlightAssignment, isFalse);
  });

  testWidgets('a legacy participant chooses job and chase vehicle', (
    tester,
  ) async {
    final controller = await restoreLegacy(RideRole.rider);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: FlightAssignmentScreen(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('repair-role-chaseDriver')));
    await tester.enterText(
      find.byKey(const Key('repair-vehicle-label-field')),
      'Recovery One',
    );
    await tester.tap(find.byKey(const Key('confirm-flight-assignment')));
    await tester.pumpAndSettle();

    expect(controller.localFlightRole, FlightRole.chaseDriver);
    expect(controller.localCraft?.craft.label, 'Recovery One');
    expect(controller.hasFlightAuthority, isFalse);
  });
}

class _FakeNearbyBridge extends NearbyBridge {
  const _FakeNearbyBridge();

  @override
  Future<NearbyCapabilities> capabilities() async => const NearbyCapabilities(
    platform: 'test',
    nativeBridgeReady: true,
    nearbyApiLinked: false,
    status: 'phase0',
  );
}
