import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/operational_boundary.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 22, 7);

  test('several pilot boundaries coexist and can be removed independently', () {
    final line = OperationalBoundary(
      id: 'restricted-road',
      label: 'Restricted airspace edge',
      kind: OperationalBoundaryKind.line,
      points: const [
        GeoPoint(latitude: 51.0, longitude: -2.1),
        GeoPoint(latitude: 51.1, longitude: -2.0),
      ],
      source: 'Pilot-entered advisory boundary',
      updatedAt: start,
    );
    final altitude = OperationalBoundary(
      id: 'height-band',
      label: 'Planned altitude band',
      kind: OperationalBoundaryKind.altitudeBand,
      points: const [],
      source: 'Flight briefing',
      updatedAt: start,
      lowerAltitudeMeters: 150,
      upperAltitudeMeters: 900,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
    );
    final events = [
      _event(
        id: 'created',
        type: RideEventType.rideCreated,
        createdAt: start,
        payload: const {'role': 'lead'},
      ),
      _upsert('line', line, start.add(const Duration(minutes: 1))),
      _upsert('height', altitude, start.add(const Duration(minutes: 2))),
      _event(
        id: 'remove-line',
        type: RideEventType.operationalBoundaryRemoved,
        createdAt: start.add(const Duration(minutes: 3)),
        payload: const {
          'leaderRiderId': 'pilot',
          'boundaryId': 'restricted-road',
        },
      ),
    ];

    final result = const OperationalBoundaryReducer().fromEvents(
      events.reversed,
    );

    expect(result, hasLength(1));
    expect(result.single.id, 'height-band');
    expect(result.single.upperAltitudeMeters, 900);
  });

  test('a chaser cannot add or remove pilot boundaries', () {
    final boundary = OperationalBoundary(
      id: 'area',
      label: 'Keep clear',
      kind: OperationalBoundaryKind.area,
      points: const [
        GeoPoint(latitude: 51.0, longitude: -2.1),
        GeoPoint(latitude: 51.1, longitude: -2.1),
        GeoPoint(latitude: 51.1, longitude: -2.0),
      ],
      source: 'NOTAM briefing copied by pilot',
      updatedAt: start,
    );
    final result = const OperationalBoundaryReducer().fromEvents([
      _event(
        id: 'created',
        type: RideEventType.rideCreated,
        createdAt: start,
        payload: const {'role': 'lead'},
      ),
      _event(
        id: 'joined',
        deviceId: 'chaser',
        type: RideEventType.riderJoined,
        createdAt: start,
        payload: const {'role': 'rider'},
      ),
      _event(
        id: 'forged',
        deviceId: 'chaser',
        type: RideEventType.operationalBoundaryUpserted,
        createdAt: start.add(const Duration(minutes: 1)),
        payload: boundary.toEventPayload(leaderRiderId: 'chaser'),
      ),
    ]);

    expect(result, isEmpty);
  });
}

RideEvent _upsert(
  String id,
  OperationalBoundary boundary,
  DateTime createdAt,
) => _event(
  id: id,
  type: RideEventType.operationalBoundaryUpserted,
  createdAt: createdAt,
  payload: boundary.toEventPayload(leaderRiderId: 'pilot'),
);

RideEvent _event({
  required String id,
  String deviceId = 'pilot',
  required RideEventType type,
  required DateTime createdAt,
  required Map<String, Object?> payload,
}) => RideEvent(
  id: id,
  rideId: 'flight-a',
  deviceId: deviceId,
  type: type,
  priority: EventPriority.important,
  createdAt: createdAt,
  payload: payload,
  signature: 'signed-for-reducer-test',
);
