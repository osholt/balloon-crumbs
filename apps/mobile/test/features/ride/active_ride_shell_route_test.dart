import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/route_store.dart';
import 'package:balloon_crumbs/features/ride/active_ride_shell.dart';
import 'package:balloon_crumbs/features/map/ride_map.dart';

void main() {
  test(
    'a new ride waits for its scoped route store before mounting the map',
    () {
      final rideStore = InMemoryRouteStore();

      expect(
        activeRideMapStoreWhenReady(
          initializing: true,
          isSimulation: false,
          rideRouteStore: rideStore,
          simulationRouteStore: null,
        ),
        isNull,
      );
      expect(
        activeRideMapStoreWhenReady(
          initializing: false,
          isSimulation: false,
          rideRouteStore: rideStore,
          simulationRouteStore: null,
        ),
        same(rideStore),
      );
      expect(
        activeRideMapStoreWhenReady(
          initializing: false,
          isSimulation: false,
          rideRouteStore: null,
          simulationRouteStore: null,
        ),
        isNull,
      );
    },
  );

  test('only stopped drivers and chase crew can change a vehicle target', () {
    final now = DateTime.utc(2026, 8, 23, 12);
    MapNavigationPosition navigation(
      double? speed, {
      Duration age = Duration.zero,
    }) => MapNavigationPosition(
      point: const GeoPoint(latitude: 51.5, longitude: -2.6),
      recordedAt: now.subtract(age),
      speedMetersPerSecond: speed,
      accuracyMeters: 5,
      altitudeSource: AltitudeSource.unknown,
      altitudeDatum: AltitudeDatum.unknown,
    );

    expect(
      canChangeChaseGuidanceTarget(
        role: FlightRole.chaseCrew,
        navigation: null,
        now: now,
      ),
      isTrue,
    );
    expect(
      canChangeChaseGuidanceTarget(
        role: FlightRole.chaseDriver,
        navigation: navigation(0.2),
        now: now,
      ),
      isTrue,
    );
    expect(
      canChangeChaseGuidanceTarget(
        role: FlightRole.chaseDriver,
        navigation: navigation(8),
        now: now,
      ),
      isFalse,
    );
    expect(
      canChangeChaseGuidanceTarget(
        role: FlightRole.chaseDriver,
        navigation: navigation(0, age: const Duration(seconds: 11)),
        now: now,
      ),
      isFalse,
      reason: 'an old zero-speed fix must not be treated as safely stopped',
    );
    expect(
      canChangeChaseGuidanceTarget(
        role: FlightRole.pilot,
        navigation: navigation(0),
        now: now,
      ),
      isFalse,
    );
  });
}
