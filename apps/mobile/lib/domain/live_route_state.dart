import 'flight_role.dart';
import 'imported_route.dart';

/// Keeps the shared airborne forecast separate from one vehicle's road route.
///
/// They may share geometry near the landing area, but they have different
/// owners and meanings. A pilot publishing a new forecast must never replace a
/// driver's turn-by-turn route, and a driver's dynamic reroute must never be
/// broadcast as the aircraft plan.
class LiveRouteState {
  const LiveRouteState({this.sharedFlightPlan, this.vehicleRoadRoute});

  final ImportedRoute? sharedFlightPlan;
  final ImportedRoute? vehicleRoadRoute;

  ImportedRoute? activeFor(FlightRole role) =>
      role.isChasing ? vehicleRoadRoute : sharedFlightPlan;

  LiveRouteState withSharedFlightPlan(ImportedRoute? route) => LiveRouteState(
    sharedFlightPlan: route,
    vehicleRoadRoute: vehicleRoadRoute,
  );

  LiveRouteState withVehicleRoadRoute(ImportedRoute? route) => LiveRouteState(
    sharedFlightPlan: sharedFlightPlan,
    vehicleRoadRoute: route,
  );
}
