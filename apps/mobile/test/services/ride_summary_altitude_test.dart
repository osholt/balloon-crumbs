import 'dart:convert';
import 'dart:typed_data';

import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/services/gpx_exporter.dart';
import 'package:balloon_crumbs/services/gpx_parser.dart';
import 'package:balloon_crumbs/services/ride_summary_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// A balloon flight exported without its vertical dimension is not a balloon
/// flight (#16).
///
/// The altitude already reached `LocationSample`, and the GPX writer already
/// knew how to emit `<ele>`. What was missing was the middle: the recap
/// rebuilt the flown trail from the journal and dropped the height on the way.
void main() {
  final startedAt = DateTime.utc(2026, 8, 8, 6, 5);

  final session = RideSession(
    rideId: 'flight-1',
    rideCode: '123456',
    inviteSecret: 'invite-secret-long-enough',
    joinToken: 'join-token-0123456789',
    localRiderId: 'pilot',
    displayName: 'Pilot',
    role: RideRole.lead,
    joinedAt: startedAt,
  );

  RideEvent fix(int seconds, double latitude, {double? altitude}) => RideEvent(
    id: 'fix-$seconds',
    rideId: 'flight-1',
    deviceId: 'pilot',
    type: RideEventType.riderLocationUpdated,
    priority: EventPriority.routine,
    signature: 'test',
    createdAt: startedAt.add(Duration(seconds: seconds)),
    payload: {
      'location': {
        'sample': {
          'position': {'latitude': latitude, 'longitude': -2.6413},
          'recordedAt': startedAt
              .add(Duration(seconds: seconds))
              .toIso8601String(),
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

  RideEvent started() => RideEvent(
    id: 'started',
    rideId: 'flight-1',
    deviceId: 'pilot',
    type: RideEventType.rideStarted,
    priority: EventPriority.routine,
    signature: 'test',
    createdAt: startedAt,
    payload: const {},
  );

  test('a recorded climb reaches the exported GPX as <ele>', () {
    final route = const RideSummaryExporter().traveledRoute(session, [
      started(),
      fix(0, 51.4459, altitude: 60),
      fix(30, 51.4462, altitude: 240),
    ], generatedAt: startedAt.add(const Duration(minutes: 1)));
    expect(route, isNotNull);
    expect(route!.paths.single.points.map((point) => point.elevationMeters), [
      60,
      240,
    ]);

    final gpx = const GpxExporter().export(route);
    expect(gpx, contains('<ele>60.000</ele>'));
    expect(gpx, contains('<ele>240.000</ele>'));

    final imported = const GpxParser().parse(
      Uint8List.fromList(utf8.encode(gpx)),
      routeId: 'round-trip',
      sourceFileName: 'flight.gpx',
      importedAt: startedAt.add(const Duration(minutes: 2)),
    );
    final points = imported.paths.single.points;
    expect(points.first.altitudeSource, AltitudeSource.gnss);
    expect(points.first.altitudeDatum, AltitudeDatum.wgs84Geoid);
    expect(points.first.altitudeAccuracyMeters, 6);
  });

  test('a fix with no altitude exports no <ele>, rather than zero', () {
    // The failure this guards against reads as sea level on any map that
    // colours by height, which for a balloon is the one number that matters.
    final route = const RideSummaryExporter().traveledRoute(session, [
      started(),
      fix(0, 51.4459),
      fix(30, 51.4462),
    ], generatedAt: startedAt.add(const Duration(minutes: 1)));
    expect(route!.paths.single.points.map((point) => point.elevationMeters), [
      null,
      null,
    ]);
    expect(const GpxExporter().export(route), isNot(contains('<ele>')));
  });

  test('a malformed altitude costs that point its height, not the export', () {
    // Relayed fixes are untrusted input. One bad value must not take the whole
    // flight down with it.
    final route = const RideSummaryExporter().traveledRoute(session, [
      started(),
      fix(0, 51.4459, altitude: 60),
      RideEvent(
        id: 'broken',
        rideId: 'flight-1',
        deviceId: 'pilot',
        type: RideEventType.riderLocationUpdated,
        priority: EventPriority.routine,
        signature: 'test',
        createdAt: startedAt.add(const Duration(seconds: 30)),
        payload: const {
          'location': {
            'sample': {
              'position': {'latitude': 51.4462, 'longitude': -2.6413},
              'altitudeMeters': 'not a number',
            },
          },
        },
      ),
    ], generatedAt: startedAt.add(const Duration(minutes: 1)));
    expect(route!.paths.single.points.map((point) => point.elevationMeters), [
      60,
      null,
    ]);
  });
}
