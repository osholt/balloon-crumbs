import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/controllers/ride_simulation_controller.dart';
import 'package:balloon_crumbs/controllers/situational_awareness_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';

/// Ride Lab flies the lead agent as a balloon so the demo exercises the WP2
/// telemetry rather than describing it (`docs/delivery-plan.md`, issue #16).
///
/// The point of these tests is the *contrast*: the balloon carries altitude and
/// the chase vehicles do not, so any surface that renders height has to handle
/// both in the same frame.
void main() {
  late InMemoryEventStore store;
  late SituationalAwarenessController awareness;
  late RideSimulationController simulation;

  const route = [
    GeoPoint(latitude: 51, longitude: -1),
    GeoPoint(latitude: 51, longitude: -0.9),
  ];

  setUp(() async {
    store = InMemoryEventStore();
    final session = RideSession(
      rideId: 'sim-flight',
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

  LocationSample? balloonFix() => awareness.riderLocations
      .where((location) => location.role == RideRole.lead)
      .map((location) => location.sample)
      .firstOrNull;

  Iterable<LocationSample> chaseFixes() => awareness.riderLocations
      .where((location) => location.role != RideRole.lead)
      .map((location) => location.sample);

  test('the balloon reports altitude and the chase vehicles do not', () {
    final balloon = balloonFix();

    expect(balloon, isNotNull);
    expect(balloon!.hasAltitude, isTrue);
    expect(balloon.altitudeSource, AltitudeSource.gnss);
    expect(balloon.altitudeAccuracyMeters, isNotNull);

    // The contrast is the point: a chase vehicle on the road carries no
    // altitude, so every surface has to render both states side by side.
    expect(chaseFixes(), isNotEmpty);
    for (final fix in chaseFixes()) {
      expect(fix.hasAltitude, isFalse);
      expect(fix.altitudeSource, AltitudeSource.unknown);
    }
  });

  test('the flight climbs out, holds a level, then descends to land', () async {
    final heights = <double>[];
    final climbRates = <double>[];

    // Sample the whole track rather than the endpoints: a profile that only
    // agreed at the ends could be a straight line, which is not a flight.
    for (var step = 0; step < 24; step += 1) {
      final fix = balloonFix();
      if (fix?.altitudeMeters case final altitude?) {
        heights.add(altitude);
        climbRates.add(fix!.verticalSpeedMetersPerSecond ?? 0);
      }
      await simulation.advance(const Duration(seconds: 20));
    }

    expect(heights.length, greaterThan(8));

    final launch = heights.first;
    final peak = heights.reduce((a, b) => a > b ? a : b);
    final landing = heights.last;

    expect(launch, lessThan(peak), reason: 'the balloon has to climb');
    expect(landing, lessThan(peak), reason: 'and come back down');
    expect(peak, greaterThan(400), reason: 'a real flight gains real height');
    expect(
      climbRates.any((rate) => rate > 1),
      isTrue,
      reason: 'a climb is reported as a climb',
    );
    expect(
      climbRates.any((rate) => rate < -1),
      isTrue,
      reason: 'a descent is reported as a descent',
    );
  });

  test('every reported height survives the relay wire form', () {
    final balloon = balloonFix()!;
    final decoded = LocationSample.fromJson(balloon.toJson());

    expect(decoded.altitudeMeters, balloon.altitudeMeters);
    expect(decoded.altitudeSource, AltitudeSource.gnss);
    expect(decoded.altitudeAccuracyMeters, balloon.altitudeAccuracyMeters);
    expect(
      decoded.verticalSpeedMetersPerSecond,
      balloon.verticalSpeedMetersPerSecond,
    );
  });
}
