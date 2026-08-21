import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/controllers/ride_simulation_controller.dart';
import 'package:balloon_crumbs/controllers/situational_awareness_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/features/map/craft_icon.dart';
import 'package:balloon_crumbs/services/ride_completion_detector.dart';

void main() {
  late InMemoryEventStore store;
  late SituationalAwarenessController awareness;
  late RideSimulationController simulation;
  late RideSession session;
  const route = [
    GeoPoint(latitude: 51, longitude: -1),
    GeoPoint(latitude: 51, longitude: -0.9),
  ];

  setUp(() async {
    store = InMemoryEventStore();
    session = RideSession(
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
    awareness = SituationalAwarenessController(store, session, route: route);
    await awareness.initialize();
    simulation = RideSimulationController(
      awareness,
      session: session,
      route: route,
      tickInterval: const Duration(days: 1),
    );
    await simulation.initialize();
  });

  tearDown(() {
    simulation.dispose();
    awareness.dispose();
  });

  Future<RideSimulationController> buildLegacyFleet() async {
    final controller = RideSimulationController(
      awareness,
      session: session,
      route: route,
      riderCount: 5,
      tickInterval: const Duration(days: 1),
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'emits one balloon and one Land Rover and advances virtual time',
    () async {
      expect(awareness.riderLocations, hasLength(2));
      expect(awareness.authenticatedLocationEvidence, hasLength(2));
      final chase = simulation.riders.singleWhere(
        (rider) => rider.id == RideSimulationController.companionRiderId,
      );
      expect(chase.displayName, 'Land Rover');
      expect(chase.role, RideRole.rider);
      expect(chase.motorcycleStyle, CraftIconStyle.fourByFour);

      final initialProgress = simulation.progress;
      await simulation.advance(const Duration(seconds: 2));

      expect(simulation.progress, greaterThan(initialProgress));
      expect(simulation.simulatedElapsed, const Duration(seconds: 16));
    },
  );

  test('keeps the fleet staged until the ride starts', () async {
    final stagedSession = RideSession(
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
    final stagedAwareness = SituationalAwarenessController(
      InMemoryEventStore(),
      stagedSession,
      route: const [
        GeoPoint(latitude: 51, longitude: -1),
        GeoPoint(latitude: 51, longitude: -0.9),
      ],
      rideStarted: false,
    );
    await stagedAwareness.initialize();
    final stagedSimulation = RideSimulationController(
      stagedAwareness,
      session: stagedSession,
      route: const [
        GeoPoint(latitude: 51, longitude: -1),
        GeoPoint(latitude: 51, longitude: -0.9),
      ],
      tickInterval: const Duration(days: 1),
      rideStarted: false,
    );
    addTearDown(() {
      stagedSimulation.dispose();
      stagedAwareness.dispose();
    });
    await stagedSimulation.initialize();

    final initialProgress = stagedSimulation.progress;
    stagedSimulation.start();
    await stagedSimulation.advance(const Duration(seconds: 2));

    expect(stagedSimulation.state, RideSimulationState.ready);
    expect(stagedSimulation.progress, initialProgress);
    expect(stagedSimulation.simulatedElapsed, Duration.zero);
    expect(
      stagedSimulation.riders.every((rider) => rider.speedMetersPerSecond == 0),
      isTrue,
    );

    stagedSimulation.setRideStarted(true);
    stagedSimulation.start();
    await stagedSimulation.advance(const Duration(seconds: 2));

    expect(stagedSimulation.state, RideSimulationState.running);
    expect(stagedSimulation.progress, greaterThan(initialProgress));
  });

  test('uses short updates for continuous visual movement', () {
    final smoothSimulation = RideSimulationController(
      awareness,
      session: RideSession(
        rideId: 'sim-ride',
        rideCode: 'SIM123',
        inviteSecret: 'simulation-secret-that-is-long-enough',
        joinToken: 'test-join-token-0123456789',
        localRiderId: 'lead',
        displayName: 'Demo Lead',
        role: RideRole.lead,
        joinedAt: DateTime.utc(2026, 7, 17),
        isSimulation: true,
      ),
      route: const [
        GeoPoint(latitude: 51, longitude: -1),
        GeoPoint(latitude: 51, longitude: -0.9),
      ],
    );
    addTearDown(smoothSimulation.dispose);

    expect(smoothSimulation.tickInterval, const Duration(milliseconds: 100));
    expect(smoothSimulation.eventInterval, const Duration(seconds: 2));
  });

  test('supports a configurable thirty-rider fleet', () async {
    final largeFleet = RideSimulationController(
      awareness,
      session: RideSession(
        rideId: 'sim-ride',
        rideCode: 'SIM123',
        inviteSecret: 'simulation-secret-that-is-long-enough',
        joinToken: 'test-join-token-0123456789',
        localRiderId: 'lead',
        displayName: 'Demo Lead',
        role: RideRole.lead,
        joinedAt: DateTime.utc(2026, 7, 17),
        isSimulation: true,
        simulationRiderCount: 30,
      ),
      route: const [
        GeoPoint(latitude: 51, longitude: -1),
        GeoPoint(latitude: 51, longitude: -0.9),
      ],
      riderCount: 30,
      tickInterval: const Duration(days: 1),
    );
    addTearDown(largeFleet.dispose);
    await largeFleet.initialize();

    expect(largeFleet.riderCount, 30);
    expect(largeFleet.riders, hasLength(30));
    expect(largeFleet.riders.map((rider) => rider.id).toSet(), hasLength(30));
    expect(
      largeFleet.riders.where(
        (rider) => rider.id == RideSimulationController.backRiderId,
      ),
      hasLength(1),
    );
    largeFleet.setAlexOffRoute(true);
    await largeFleet.advance(const Duration(seconds: 1));
    expect(
      largeFleet.riders
          .singleWhere(
            (rider) => rider.id == RideSimulationController.offRouteRiderId,
          )
          .isOffRoute,
      isTrue,
    );
  });

  test('retains a recent trail for the simulated leader', () async {
    final initialLeader = simulation.riders.singleWhere(
      (rider) => rider.role == RideRole.lead,
    );
    expect(initialLeader.travelTrail, hasLength(1));

    await simulation.advance(const Duration(seconds: 1));

    final movingLeader = simulation.riders.singleWhere(
      (rider) => rider.role == RideRole.lead,
    );
    expect(movingLeader.travelTrail.length, greaterThan(1));
  });

  test('switches between balloon and Land Rover perspectives', () {
    simulation.setLocalRole(RideRole.rider);
    expect(simulation.localRole, RideRole.rider);
    final follower = simulation.riders.singleWhere((rider) => rider.isLocal);
    final leader = simulation.riders.singleWhere(
      (rider) => rider.displayName == 'Balloon',
    );
    expect(follower.displayName, 'You · Land Rover');
    expect(follower.motorcycleStyle, CraftIconStyle.fourByFour);
    expect(leader.role, RideRole.lead);
  });

  test('the two demo craft keep moving after changing perspective', () async {
    simulation.setLocalRole(RideRole.rider);
    simulation.setTimeScale(1);
    final before = {
      for (final rider in simulation.riders) rider.id: rider.position,
    };

    await simulation.advance(const Duration(seconds: 30));

    final follower = simulation.riders.singleWhere((rider) => rider.isLocal);
    final leader = simulation.riders.singleWhere(
      (rider) => rider.displayName == 'Balloon',
    );
    expect(follower.role, RideRole.rider);
    expect(leader.role, RideRole.lead);
    expect(follower.position, isNot(before[follower.id]));
    expect(leader.position, isNot(before[leader.id]));
  });

  test(
    'off-route visual trail is local to the current simulation run',
    () async {
      final legacy = await buildLegacyFleet();
      legacy.setAlexOffRoute(true);
      await legacy.advance(const Duration(seconds: 1));

      final alex = legacy.riders.singleWhere(
        (rider) => rider.id == RideSimulationController.offRouteRiderId,
      );
      expect(alex.offRouteTrail, hasLength(greaterThanOrEqualTo(2)));
      expect(
        alex.offRouteTrail.every(
          (point) => point.latitude > 50 && point.latitude < 52,
        ),
        isTrue,
      );

      legacy.setAlexOffRoute(false);
      expect(
        legacy.riders
            .singleWhere(
              (rider) => rider.id == RideSimulationController.offRouteRiderId,
            )
            .offRouteTrail,
        isEmpty,
      );
    },
  );

  test('can delay TEC and inject a synthetic roadworks hazard', () async {
    final legacy = await buildLegacyFleet();
    final normalTecSpeed = legacy.riders
        .singleWhere(
          (rider) => rider.id == RideSimulationController.backRiderId,
        )
        .speedMetersPerSecond;
    legacy.setBackRiderDelayed(true);
    final delayedTecSpeed = legacy.riders
        .singleWhere(
          (rider) => rider.id == RideSimulationController.backRiderId,
        )
        .speedMetersPerSecond;
    expect(delayedTecSpeed, lessThan(normalTecSpeed));

    await legacy.reportRoadworks();
    expect(awareness.activeHazards.single.details, contains('Ride Lab'));
    expect(
      (awareness.activeHazards.single.position.longitude -
              awareness.localLocation!.sample.position.longitude)
          .abs(),
      greaterThan(0.0001),
    );
  });

  test('completion publishes stopped GPS fixes', () async {
    simulation.setTimeScale(16);
    // Completion is intentionally group-wide.
    for (var index = 0; index < 3; index += 1) {
      await simulation.advance(const Duration(minutes: 1));
      if (simulation.state == RideSimulationState.completed) break;
    }

    expect(simulation.state, RideSimulationState.completed);
    expect(
      simulation.riders.every((rider) => rider.speedMetersPerSecond == 0),
      isTrue,
    );
    expect(
      awareness.riderLocations.every(
        (location) => location.sample.speedMetersPerSecond == 0,
      ),
      isTrue,
    );
    expect(
      const RideCompletionDetector().everyoneReachedDestination(
        destination: const GeoPoint(latitude: 51, longitude: -0.9),
        riderLocations: awareness.riderLocations,
        now: DateTime.now(),
        // The fleet's own progress, not a stand-in: arrival is only arrival once
        // the route is behind the group (#206).
        routeProgressFraction: simulation.progress,
      ),
      isTrue,
    );
  });
}
