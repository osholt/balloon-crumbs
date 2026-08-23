import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/live_route_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final forecast = _route('forecast');
  final road = _route('road');

  test('airborne roles follow the shared flight plan', () {
    final state = LiveRouteState(
      sharedFlightPlan: forecast,
      vehicleRoadRoute: road,
    );

    expect(state.activeFor(FlightRole.pilot), same(forecast));
    expect(state.activeFor(FlightRole.balloonCrew), same(forecast));
  });

  test('chase roles follow only their vehicle road route', () {
    final state = LiveRouteState(
      sharedFlightPlan: forecast,
      vehicleRoadRoute: road,
    );

    expect(state.activeFor(FlightRole.chaseDriver), same(road));
    expect(state.activeFor(FlightRole.chaseCrew), same(road));
  });

  test('a new forecast cannot overwrite local road guidance', () {
    final replacement = _route('replacement');
    final state = LiveRouteState(
      sharedFlightPlan: forecast,
      vehicleRoadRoute: road,
    ).withSharedFlightPlan(replacement);

    expect(state.sharedFlightPlan, same(replacement));
    expect(state.vehicleRoadRoute, same(road));
  });

  test('a dynamic road reroute cannot overwrite the forecast', () {
    final replacement = _route('replacement');
    final state = LiveRouteState(
      sharedFlightPlan: forecast,
      vehicleRoadRoute: road,
    ).withVehicleRoadRoute(replacement);

    expect(state.sharedFlightPlan, same(forecast));
    expect(state.vehicleRoadRoute, same(replacement));
  });
}

ImportedRoute _route(String id) => ImportedRoute(
  id: id,
  name: id,
  importedAt: DateTime.utc(2026, 8, 23),
  sourceFileName: '$id.gpx',
  paths: const [
    RoutePath(
      kind: RoutePathKind.track,
      points: [
        GeoPoint(latitude: 51.4, longitude: -2.7),
        GeoPoint(latitude: 51.5, longitude: -2.6),
      ],
    ),
  ],
  waypoints: const [],
);
