import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/route_store.dart';
import 'package:balloon_crumbs/features/ride/active_ride_shell.dart';

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
}

