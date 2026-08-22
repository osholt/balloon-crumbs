import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/completed_ride.dart';
import 'package:balloon_crumbs/domain/flight_replay.dart';
import 'package:balloon_crumbs/domain/geo_point.dart' as replay_geo;
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';

void main() {
  test('completed ride round-trips summary and route geometry', () {
    final ride = _ride();

    final restored = CompletedRide.fromJson(ride.toJson());

    expect(restored.rideId, ride.rideId);
    expect(restored.localRole, RideRole.rider);
    expect(restored.traveledRoute?.pathPointCount, 2);
    expect(restored.mapPoints, hasLength(2));
  });

  test('damaged optional geometry does not discard summary metadata', () {
    final json = _ride().toJson()
      ..['traveledRoute'] = {
        'schemaVersion': 1,
        'id': 'broken',
        'paths': 'not-a-list',
      };

    final restored = CompletedRide.fromJson(json);

    expect(restored.title, 'Flight 123456');
    expect(restored.traveledRoute, isNull);
    expect(restored.riderCount, 4);
  });

  test('schema two round-trips the synchronized flight replay', () {
    final start = DateTime.utc(2026, 7, 23, 12);
    final replay = FlightReplay(
      startedAt: start,
      endedAt: start.add(const Duration(hours: 2)),
      tracks: [
        FlightReplayTrack(
          id: 'balloon',
          label: 'Balloon',
          kind: FlightReplayTrackKind.balloon,
          samples: [
            FlightReplaySample(
              position: const replay_geo.GeoPoint(latitude: 53, longitude: -1),
              recordedAt: start,
              altitudeMeters: 300,
            ),
            FlightReplaySample(
              position: const replay_geo.GeoPoint(
                latitude: 53.1,
                longitude: -0.9,
              ),
              recordedAt: start.add(const Duration(minutes: 30)),
              altitudeMeters: 600,
            ),
          ],
        ),
      ],
      windContexts: const [],
      landingAreas: const [],
      peerTracksIncluded: false,
    );

    final restored = CompletedRide.fromJson(_ride(replay: replay).toJson());

    expect(restored.replay?.canReplay, isTrue);
    expect(restored.replay?.tracks.single.kind, FlightReplayTrackKind.balloon);
    expect(restored.replay?.tracks.single.samples.last.altitudeMeters, 600);
  });

  test('schema one archives remain readable without replay', () {
    final legacy = _ride().toJson()
      ..['schemaVersion'] = 1
      ..remove('replay');

    final restored = CompletedRide.fromJson(legacy);

    expect(restored.title, 'Flight 123456');
    expect(restored.replay, isNull);
    expect(restored.traveledRoute?.pathPointCount, 2);
  });
}

CompletedRide _ride({FlightReplay? replay}) => CompletedRide(
  rideId: 'ride-1',
  rideCode: '123456',
  rideName: null,
  localDisplayName: 'Oliver',
  localRole: RideRole.rider,
  startedAt: DateTime.utc(2026, 7, 23, 12),
  endedAt: DateTime.utc(2026, 7, 23, 14),
  archivedAt: DateTime.utc(2026, 7, 23, 14),
  riderCount: 4,
  eventCount: 12,
  totalDistanceMeters: 42000,
  plannedRoute: null,
  traveledRoute: ImportedRoute(
    id: 'trail',
    name: 'Recorded trail',
    importedAt: DateTime.utc(2026, 7, 23, 14),
    sourceFileName: 'ride.gpx',
    paths: const [
      RoutePath(
        kind: RoutePathKind.track,
        points: [
          GeoPoint(latitude: 53, longitude: -1),
          GeoPoint(latitude: 54, longitude: -2),
        ],
      ),
    ],
    waypoints: const [],
  ),
  replay: replay,
);
