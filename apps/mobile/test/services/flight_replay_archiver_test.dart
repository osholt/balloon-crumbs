import 'dart:convert';

import 'package:balloon_crumbs/domain/flight_replay.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/flight_replay_archiver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final started = DateTime.utc(2026, 8, 22, 6);
  final ended = started.add(const Duration(hours: 1));
  final events = _events(started);

  test('default replay keeps the balloon and local track but not peers', () {
    final replay = const FlightReplayArchiver().create(
      session: _session(started),
      events: events,
      startedAt: started,
      endedAt: ended,
    );

    expect(replay.tracks.map((track) => track.kind), [
      FlightReplayTrackKind.balloon,
      FlightReplayTrackKind.localChaser,
    ]);
    expect(replay.windContexts, hasLength(1));
    expect(replay.windContexts.single.isForecast, isTrue);
    expect(replay.landingAreas.single.label, 'North field');
    expect(replay.peerTracksIncluded, isFalse);
    expect(replay.canReplay, isTrue);
  });

  test('peer replay is explicit and strips peer identifiers and names', () {
    final replay = const FlightReplayArchiver().create(
      session: _session(started),
      events: events,
      startedAt: started,
      endedAt: ended,
      includePeerTracks: true,
    );

    expect(
      replay.tracks.where(
        (track) => track.kind == FlightReplayTrackKind.chaser,
      ),
      hasLength(1),
    );
    expect(replay.tracks.last.label, 'Chaser 1');
    final encoded = jsonEncode(replay.toJson());
    expect(encoded, isNot(contains('peer-private-device-id')));
    expect(encoded, isNot(contains('Private Chaser Name')));
    expect(replay.peerTracksIncluded, isTrue);
  });
}

RideSession _session(DateTime joinedAt) => RideSession(
  rideId: 'flight-1',
  rideCode: '123456',
  inviteSecret: '0123456789abcdef0123456789abcdef',
  joinToken: 'join-token',
  localRiderId: 'local-device',
  displayName: 'Local crew',
  role: RideRole.rider,
  joinedAt: joinedAt,
);

List<RideEvent> _events(DateTime start) => [
  _event('craft', 'pilot-device', RideEventType.craftRegistered, start, {
    'craftId': 'balloon-craft',
    'kind': 'balloon',
    'label': 'G-TEST',
  }),
  _event('attach', 'pilot-device', RideEventType.deviceAttachedToCraft, start, {
    'deviceId': 'pilot-device',
    'craftId': 'balloon-craft',
  }),
  for (var index = 0; index < 2; index++) ...[
    _locationEvent(
      'local-$index',
      'local-device',
      'Local crew',
      RideRole.rider,
      start.add(Duration(minutes: 5 + index * 5)),
      51.45 + index * 0.001,
    ),
    _locationEvent(
      'balloon-$index',
      'pilot-device',
      'Pilot',
      RideRole.lead,
      start.add(Duration(minutes: 5 + index * 5)),
      51.46 + index * 0.002,
      altitude: 300 + index * 50,
    ),
    _locationEvent(
      'peer-$index',
      'peer-private-device-id',
      'Private Chaser Name',
      RideRole.rider,
      start.add(Duration(minutes: 5 + index * 5)),
      51.44 + index * 0.001,
    ),
  ],
  _event(
    'landing',
    'pilot-device',
    RideEventType.landingAreaNoted,
    start.add(const Duration(minutes: 3)),
    {
      'latitude': 51.48,
      'longitude': -2.5,
      'radiusMeters': 500,
      'label': 'North field',
    },
  ),
  _event(
    'wind',
    'pilot-device',
    RideEventType.windContextNoted,
    start.add(const Duration(minutes: 4)),
    {
      'validAt': start.add(const Duration(minutes: 5)).toIso8601String(),
      'source': 'UKMO test forecast',
      'isForecast': true,
      'latitude': 51.45,
      'longitude': -2.6,
      'vectors': [
        {'altitudeMetersMsl': 100, 'fromDegrees': 240, 'speedKmh': 12},
      ],
    },
  ),
];

RideEvent _locationEvent(
  String id,
  String deviceId,
  String name,
  RideRole role,
  DateTime at,
  double latitude, {
  double? altitude,
}) => _event(id, deviceId, RideEventType.riderLocationUpdated, at, {
  'location': RiderLocation(
    riderId: deviceId,
    displayName: name,
    role: role,
    sample: LocationSample(
      position: GeoPoint(latitude: latitude, longitude: -2.6),
      recordedAt: at,
      accuracyMeters: 4,
      speedMetersPerSecond: 5,
      headingDegrees: 40,
      altitudeMeters: altitude,
    ),
    receivedAt: at,
  ).toJson(),
});

RideEvent _event(
  String id,
  String deviceId,
  RideEventType type,
  DateTime at,
  Map<String, Object?> payload,
) => RideEvent(
  id: id,
  rideId: 'flight-1',
  deviceId: deviceId,
  type: type,
  priority: EventPriority.routine,
  createdAt: at,
  payload: payload,
  signature: 'a' * 64,
);
