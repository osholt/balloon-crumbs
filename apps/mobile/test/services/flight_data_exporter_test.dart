import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/services/flight_data_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 24, 6);
  final session = RideSession(
    rideId: 'flight-1',
    rideCode: 'TUCKER',
    inviteSecret: 'invite-secret-long-enough',
    joinToken: 'join-token-0123456789',
    localRiderId: 'pilot',
    displayName: 'Pilot',
    role: RideRole.lead,
    joinedAt: start,
  );

  RideEvent fix(
    String id,
    int seconds, {
    Object? latitude = 51.303,
    Object? altitude = 120,
  }) => RideEvent(
    id: id,
    rideId: session.rideId,
    deviceId: session.localRiderId,
    type: RideEventType.riderLocationUpdated,
    priority: EventPriority.routine,
    signature: 'test',
    createdAt: start.add(Duration(seconds: seconds)),
    payload: {
      'location': {
        'sample': {
          'position': {'latitude': latitude, 'longitude': -2.409},
          'recordedAt': start.add(Duration(seconds: seconds)).toIso8601String(),
          if (altitude != null) ...{
            'altitudeMeters': altitude,
            'altitudeSource': 'gnss',
            'altitudeDatum': 'wgs84Geoid',
            'altitudeAccuracyMeters': 6,
          },
        },
      },
    },
  );

  ImportedRoute plan() => ImportedRoute(
    id: 'plan',
    name: 'Forecast flight',
    importedAt: start,
    sourceFileName: 'plan.json',
    purpose: ImportedRoutePurpose.balloonForecast,
    paths: const [
      RoutePath(
        kind: RoutePathKind.track,
        points: [
          GeoPoint(latitude: 51.3, longitude: -2.4, elevationMeters: 150),
          GeoPoint(latitude: 51.4, longitude: -2.3),
        ],
      ),
    ],
    waypoints: const [],
  );

  test('CSV labels measured, calculated, missing and rejected telemetry', () {
    final csv = const FlightDataExporter().telemetryCsv(
      session: session,
      events: [
        fix('measured', 0),
        fix('missing-altitude', 30, altitude: null),
        fix('rejected-altitude', 60, altitude: 'bad'),
        fix('rejected-position', 90, latitude: 500),
        fix('after-gap', 300),
      ],
      plannedRoute: plan(),
    );

    expect(csv, contains('"position_quality","altitude_quality"'));
    expect(csv, contains('"measured","measured","gnss","wgs84Geoid"'));
    expect(csv, contains('"measured","missing","unknown","unknown"'));
    expect(csv, contains('"measured","rejected","unknown","unknown"'));
    expect(csv, contains('"rejected"'));
    expect(csv, contains('"recording_gap"'));
    expect(csv, contains('"calculated","calculated"'));
    expect(csv, contains('"calculated","missing"'));
    expect(csv, isNot(contains('"pilot"')));
  });

  test('KML separates the measured track from the calculated plan', () {
    final route = ImportedRoute(
      id: 'track',
      name: 'Recorded flight',
      importedAt: start,
      sourceFileName: 'track.gpx',
      paths: const [
        RoutePath(
          kind: RoutePathKind.track,
          points: [
            GeoPoint(
              latitude: 51.303,
              longitude: -2.409,
              elevationMeters: 120,
              altitudeSource: AltitudeSource.gnss,
              altitudeDatum: AltitudeDatum.wgs84Geoid,
            ),
            GeoPoint(latitude: 51.304, longitude: -2.408),
          ],
        ),
      ],
      waypoints: const [],
    );

    final kml = const FlightDataExporter().kml(
      name: 'Tucker flight',
      traveledRoute: route,
      plannedRoute: plan(),
    );

    expect(kml, contains('Recorded track'));
    expect(kml, contains('Planned or forecast route'));
    expect(kml, contains('<value>measured</value>'));
    expect(kml, contains('<value>calculated</value>'));
    expect(kml, contains('-2.408,51.304'));
    expect(kml, isNot(contains('-2.408,51.304,0')));
  });
}
