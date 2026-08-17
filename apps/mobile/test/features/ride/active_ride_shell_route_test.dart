import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/imported_route.dart' as imported_route;
import 'package:balloon_crumbs/domain/route_store.dart';
import 'package:balloon_crumbs/features/ride/active_ride_shell.dart';
import 'package:balloon_crumbs/services/road_routing.dart';

void main() {
  test('Ride Lab marks one point for a paired roundabout', () {
    final entry = RoadRouteManeuver(
      position: const imported_route.GeoPoint(latitude: 51.5, longitude: -2.35),
      type: 'rotary',
      exitNumber: 2,
    );
    final exit = RoadRouteManeuver(
      position: const imported_route.GeoPoint(
        latitude: 51.501,
        longitude: -2.351,
      ),
      type: 'exit rotary',
    );

    expect(simulationMarkerManeuvers([entry, exit]), [entry]);
  });

  group('reroute takeover around a junction', () {
    test('waits while approaching or clearing the current manoeuvre', () {
      expect(
        shouldDeferRejoinNavigation(
          hasRoutedPlan: true,
          distanceToCurrentManeuverMeters: 47,
          metersSincePreviousManeuver: null,
        ),
        isTrue,
      );
      expect(
        shouldDeferRejoinNavigation(
          hasRoutedPlan: true,
          distanceToCurrentManeuverMeters: 300,
          metersSincePreviousManeuver: 42,
        ),
        isTrue,
      );
    });

    test('applies after clearance and never delays a degraded plan', () {
      expect(
        shouldDeferRejoinNavigation(
          hasRoutedPlan: true,
          distanceToCurrentManeuverMeters: 300,
          metersSincePreviousManeuver: 80,
        ),
        isFalse,
      );
      expect(
        shouldDeferRejoinNavigation(
          hasRoutedPlan: false,
          distanceToCurrentManeuverMeters: 10,
          metersSincePreviousManeuver: 10,
        ),
        isFalse,
      );
    });
  });


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
}

