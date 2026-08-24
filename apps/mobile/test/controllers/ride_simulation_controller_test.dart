import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/controllers/ride_simulation_controller.dart';
import 'package:balloon_crumbs/controllers/situational_awareness_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/domain/craft.dart' show CraftKind;
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
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
      expect(chase.craftStyle, CraftIconStyle.fourByFour);

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
      largeFleet.riders
          .singleWhere((rider) => rider.role == RideRole.lead)
          .craftStyle,
      CraftIconStyle.balloon,
    );
    expect(
      largeFleet.riders
          .where((rider) => rider.role != RideRole.lead)
          .every((rider) => rider.craftStyle.kind == CraftKind.vehicle),
      isTrue,
    );
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

  test(
    'crew links disconnect, freeze peers, and converge nearby-only',
    () async {
      final remoteId = RideSimulationController.companionRiderId;
      RiderLocation remote() => awareness.riderLocations.singleWhere(
        (location) => location.riderId == remoteId,
      );
      final before = remote();

      await simulation.setConnectivity(SimulationConnectivity.disconnected);
      await simulation.advance(const Duration(seconds: 10));

      expect(simulation.connectivity, SimulationConnectivity.disconnected);
      expect(remote().sample.recordedAt, before.sample.recordedAt);
      expect(remote().sample.position, before.sample.position);

      await simulation.setConnectivity(SimulationConnectivity.nearbyOnly);

      expect(simulation.connectivity, SimulationConnectivity.nearbyOnly);
      expect(
        remote().sample.recordedAt.isAfter(before.sample.recordedAt),
        isTrue,
      );
      expect(remote().sample.position, isNot(before.sample.position));
    },
  );

  test(
    'balloon fix quality covers inaccurate, altitude loss and GPS loss',
    () async {
      await simulation.setBalloonFixQuality(
        SimulationBalloonFixQuality.inaccurate,
      );
      expect(awareness.localLocation!.sample.accuracyMeters, 150);
      expect(awareness.localLocation!.sample.altitudeAccuracyMeters, 80);

      await simulation.setBalloonFixQuality(
        SimulationBalloonFixQuality.positionOnly,
      );
      expect(awareness.localLocation!.sample.altitudeMeters, isNull);
      expect(
        awareness.localLocation!.sample.altitudeSource,
        AltitudeSource.unknown,
      );

      final lastBalloonFix = awareness.localLocation!.sample.recordedAt;
      await simulation.setBalloonFixQuality(
        SimulationBalloonFixQuality.unavailable,
      );
      await simulation.advance(const Duration(seconds: 10));
      expect(awareness.localLocation!.sample.recordedAt, lastBalloonFix);

      await simulation.setBalloonFixQuality(
        SimulationBalloonFixQuality.precise,
      );
      expect(
        awareness.localLocation!.sample.recordedAt.isAfter(lastBalloonFix),
        isTrue,
      );
      expect(awareness.localLocation!.sample.accuracyMeters, 4);
      expect(awareness.localLocation!.sample.altitudeMeters, isNotNull);
    },
  );

  test('two chase vehicles follow independent road paths', () async {
    final fleet = await _buildSeededFleet(
      seed: 742023,
      route: route,
      chaseRoutesByAgentId: const {
        RideSimulationController.offRouteRiderId: [
          GeoPoint(latitude: 51, longitude: -1),
          GeoPoint(latitude: 51.05, longitude: -1),
        ],
        RideSimulationController.backRiderId: [
          GeoPoint(latitude: 51, longitude: -1),
          GeoPoint(latitude: 50.95, longitude: -1),
        ],
      },
    );
    addTearDown(fleet.dispose);

    await fleet.advance(const Duration(seconds: 30));

    final north = fleet.riders.singleWhere(
      (rider) => rider.id == RideSimulationController.offRouteRiderId,
    );
    final south = fleet.riders.singleWhere(
      (rider) => rider.id == RideSimulationController.backRiderId,
    );
    expect(north.position.latitude, greaterThan(51));
    expect(south.position.latitude, lessThan(51));
    expect(north.travelTrail.last.longitude, closeTo(-1, 0.000001));
    expect(south.travelTrail.last.longitude, closeTo(-1, 0.000001));
  });

  test('the same seed and inputs reproduce every craft decision', () async {
    final first = await _buildSeededFleet(seed: 99, route: route);
    final second = await _buildSeededFleet(seed: 99, route: route);
    final different = await _buildSeededFleet(seed: 100, route: route);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(different.dispose);

    for (final controller in [first, second, different]) {
      controller.setTimeScale(1);
      await controller.advance(const Duration(seconds: 37));
    }

    List<(String, GeoPoint, double)> decisions(
      RideSimulationController value,
    ) => [
      for (final rider in value.riders)
        (rider.id, rider.position, rider.speedMetersPerSecond),
    ];

    expect(decisions(first), decisions(second));
    expect(decisions(first), isNot(decisions(different)));
  });

  test('switches between balloon and Land Rover perspectives', () {
    simulation.setLocalRole(RideRole.rider);
    expect(simulation.localRole, RideRole.rider);
    final follower = simulation.riders.singleWhere((rider) => rider.isLocal);
    final leader = simulation.riders.singleWhere(
      (rider) => rider.displayName == 'Balloon',
    );
    expect(follower.displayName, 'You · Land Rover');
    expect(follower.craftStyle, CraftIconStyle.fourByFour);
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
    expect(awareness.activeHazards.single.details, contains('flight-replay'));
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

Future<RideSimulationController> _buildSeededFleet({
  required int seed,
  required List<GeoPoint> route,
  Map<String, List<GeoPoint>> chaseRoutesByAgentId = const {},
}) async {
  final session = RideSession(
    rideId: 'seed-$seed',
    rideCode: 'SIM123',
    inviteSecret: 'simulation-secret-that-is-long-enough',
    joinToken: 'test-join-token-0123456789',
    localRiderId: 'lead',
    displayName: 'Demo Lead',
    role: RideRole.lead,
    joinedAt: DateTime.utc(2026, 7, 17),
    isSimulation: true,
    simulationRiderCount: 4,
  );
  final awareness = SituationalAwarenessController(
    InMemoryEventStore(),
    session,
    route: route,
  );
  await awareness.initialize();
  addTearDown(awareness.dispose);
  final controller = RideSimulationController(
    awareness,
    session: session,
    route: route,
    chaseRoutesByAgentId: chaseRoutesByAgentId,
    riderCount: 4,
    scenarioSeed: seed,
    clock: () => DateTime.utc(2026, 7, 17, 6),
    tickInterval: const Duration(days: 1),
  );
  await controller.initialize();
  return controller;
}
