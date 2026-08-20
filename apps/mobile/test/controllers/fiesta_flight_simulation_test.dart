import 'package:balloon_crumbs/controllers/ride_simulation_controller.dart';
import 'package:balloon_crumbs/controllers/situational_awareness_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/services/fiesta_flight_loader.dart';
import 'package:balloon_crumbs/services/geo_calculations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The balloon flies its own air track; the chase drives a road.
///
/// The old demo dragged every craft along one road polyline and synthesised an
/// altitude from progress along it, which meant the numbers on screen could not
/// disagree with the map however wrong they were. These assert the two are
/// genuinely different journeys.
void main() {
  // Ashton Court, and the field on Moor Lane at West Town, Backwell that the
  // measured winds of 8 August 2026 actually carry the balloon to.
  const launch = GeoPoint(latitude: 51.4459, longitude: -2.6413);
  const landing = GeoPoint(latitude: 51.41278, longitude: -2.75845);

  // A short stand-in for the chase road route. The real one is 13.4 km of road;
  // these tests only need it to be somewhere the balloon is not.
  const chaseRoute = [
    GeoPoint(latitude: 51.4459, longitude: -2.6413),
    GeoPoint(latitude: 51.4300, longitude: -2.6800),
    GeoPoint(latitude: 51.4128, longitude: -2.7585),
  ];

  BalloonFlight flight() {
    // Three samples is enough to have a climb, a level and a descent, with a
    // known height at a known moment.
    return const BalloonFlight(
      name: 'test flight',
      launch: launch,
      source: 'test',
      windLayers: [
        BalloonWindLayer(heightMetres: 173, fromDegrees: 55, speedKmh: 13.2),
      ],
      samples: [
        BalloonFlightSample(
          position: launch,
          heightMetres: 0,
          elapsed: Duration.zero,
        ),
        BalloonFlightSample(
          position: GeoPoint(latitude: 51.4300, longitude: -2.7000),
          heightMetres: 180,
          elapsed: Duration(minutes: 26),
        ),
        BalloonFlightSample(
          position: landing,
          heightMetres: 0,
          elapsed: Duration(minutes: 52),
        ),
      ],
    );
  }

  Future<RideSimulationController> build({bool rideStarted = true}) async {
    final store = InMemoryEventStore();
    final session = RideSession(
      rideId: 'fiesta',
      rideCode: 'FIE123',
      inviteSecret: 'simulation-secret-that-is-long-enough',
      joinToken: 'test-join-token-0123456789',
      localRiderId: 'pilot',
      displayName: 'Pilot',
      role: RideRole.lead,
      joinedAt: DateTime.utc(2026, 8, 8, 6, 5),
      isSimulation: true,
    );
    final awareness = SituationalAwarenessController(
      store,
      session,
      route: chaseRoute,
    );
    await awareness.initialize();
    final simulation = RideSimulationController(
      awareness,
      session: session,
      route: chaseRoute,
      balloonFlight: flight(),
      tickInterval: const Duration(days: 1),
      rideStarted: rideStarted,
    );
    await simulation.initialize();
    // Pinned so the durations in these tests are the simulated ones rather than
    // eight times smaller, which is the default demo speed.
    simulation.setTimeScale(1);
    return simulation;
  }

  test(
    'the balloon starts on the launch field, not on the road route',
    () async {
      final simulation = await build(rideStarted: false);
      addTearDown(simulation.dispose);

      final balloon = simulation.riders.firstWhere(
        (rider) => rider.role == RideRole.lead,
      );
      expect(
        GeoCalculations.distanceMeters(balloon.position, launch),
        lessThan(5),
      );
    },
  );

  test('the balloon leaves the road while the chase stays on it', () async {
    final simulation = await build();
    addTearDown(simulation.dispose);
    // Half an hour in: the balloon is out over farmland, the chase is on tarmac.
    await simulation.advance(const Duration(minutes: 26));

    final balloon = simulation.riders.firstWhere(
      (rider) => rider.role == RideRole.lead,
    );
    final chase = simulation.riders.where(
      (rider) => rider.role != RideRole.lead,
    );
    expect(chase, isNotEmpty);

    double metresFromChaseRoute(GeoPoint point) => chaseRoute
        .map((leg) => GeoCalculations.distanceMeters(point, leg))
        .reduce((a, b) => a < b ? a : b);

    // The balloon's mid-flight position is nowhere near any road route vertex.
    expect(
      metresFromChaseRoute(balloon.position),
      greaterThan(500),
      reason: 'the balloon should be off the road, not on it',
    );
  });

  test('the balloon lands where the winds put it, and stays down', () async {
    final simulation = await build();
    addTearDown(simulation.dispose);
    await simulation.advance(const Duration(minutes: 52));
    final atLanding = simulation.riders
        .firstWhere((rider) => rider.role == RideRole.lead)
        .position;
    expect(GeoCalculations.distanceMeters(atLanding, landing), lessThan(30));

    // Well past the end of the flight. A balloon that is down is down; the
    // clock running on must not walk it off the field.
    await simulation.advance(const Duration(minutes: 30));
    final later = simulation.riders
        .firstWhere((rider) => rider.role == RideRole.lead)
        .position;
    expect(GeoCalculations.distanceMeters(later, atLanding), lessThan(1));
  });

  test('the chase keeps driving after the balloon is down', () async {
    // A crew arriving after the envelope is packed is an ordinary retrieve, not
    // a missed rendezvous. Nothing should stop them or flag it.
    final simulation = await build();
    addTearDown(simulation.dispose);
    await simulation.advance(const Duration(minutes: 52));
    final chaseAtLanding = simulation.riders
        .where((rider) => rider.role != RideRole.lead)
        .map((rider) => rider.position)
        .toList();

    await simulation.advance(const Duration(minutes: 5));
    final chaseLater = simulation.riders
        .where((rider) => rider.role != RideRole.lead)
        .map((rider) => rider.position)
        .toList();

    expect(chaseLater.length, chaseAtLanding.length);
    final moved = [
      for (var index = 0; index < chaseLater.length; index += 1)
        GeoCalculations.distanceMeters(
          chaseLater[index],
          chaseAtLanding[index],
        ),
    ];
    expect(
      moved.any((metres) => metres > 1),
      isTrue,
      reason: 'at least one chase vehicle should still be moving',
    );
  });
}
