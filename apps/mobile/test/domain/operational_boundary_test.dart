import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/altitude_unit.dart';
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
      _upsert(
        'pilot-boundary',
        boundary,
        start.add(const Duration(minutes: 1)),
      ),
      _event(
        id: 'forged',
        deviceId: 'chaser',
        type: RideEventType.operationalBoundaryUpserted,
        createdAt: start.add(const Duration(minutes: 2)),
        payload: OperationalBoundary(
          id: boundary.id,
          label: 'Forged edit',
          kind: boundary.kind,
          points: boundary.points,
          source: boundary.source,
          updatedAt: start.add(const Duration(minutes: 2)),
        ).toEventPayload(leaderRiderId: 'chaser'),
      ),
      _event(
        id: 'forged-remove',
        deviceId: 'chaser',
        type: RideEventType.operationalBoundaryRemoved,
        createdAt: start.add(const Duration(minutes: 3)),
        payload: const {'leaderRiderId': 'chaser', 'boundaryId': 'area'},
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.label, 'Keep clear');
  });

  test('configuration round-trips with units, validity and source rules', () {
    final boundary = OperationalBoundary(
      id: 'configured-band',
      label: 'Briefed operating band',
      kind: OperationalBoundaryKind.altitudeBand,
      points: const [],
      source: 'Morning flight briefing',
      updatedAt: start,
      enabled: false,
      effectiveFrom: start.add(const Duration(minutes: 10)),
      validUntil: start.add(const Duration(hours: 2)),
      limitations: 'Forecast advisory; confirm before flight.',
      lowerAltitudeMeters: 152.4,
      upperAltitudeMeters: 914.4,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
      altitudeUnit: AltitudeUnit.feet,
      acceptedAltitudeSources: const {AltitudeSource.barometric},
    );

    final restored = OperationalBoundary.fromJson(boundary.toJson());

    expect(restored.isValid, isTrue);
    expect(restored.enabled, isFalse);
    expect(restored.altitudeUnit, AltitudeUnit.feet);
    expect(restored.acceptedAltitudeSources, {AltitudeSource.barometric});
    expect(restored.limitations, contains('Forecast'));
    expect(restored.appliesAt(start), isFalse);
    expect(restored.appliesAt(start.add(const Duration(hours: 1))), isTrue);
    expect(restored.appliesAt(start.add(const Duration(hours: 3))), isFalse);
  });

  test('offline event order converges for three edited boundaries', () {
    final line = OperationalBoundary(
      id: 'line',
      label: 'Boundary line',
      kind: OperationalBoundaryKind.line,
      points: const [
        GeoPoint(latitude: 51, longitude: -2.1),
        GeoPoint(latitude: 51.1, longitude: -2),
      ],
      source: 'Pilot briefing',
      updatedAt: start,
    );
    final area = OperationalBoundary(
      id: 'area',
      label: 'Boundary area',
      kind: OperationalBoundaryKind.area,
      points: const [
        GeoPoint(latitude: 51, longitude: -2.1),
        GeoPoint(latitude: 51.1, longitude: -2.1),
        GeoPoint(latitude: 51.1, longitude: -2),
      ],
      source: 'Pilot briefing',
      updatedAt: start,
    );
    final altitude = OperationalBoundary(
      id: 'altitude',
      label: 'Altitude limits',
      kind: OperationalBoundaryKind.altitudeBand,
      points: const [],
      source: 'Pilot briefing',
      updatedAt: start,
      upperAltitudeMeters: 900,
    );
    final editTime = start.add(const Duration(minutes: 2));
    final events = [
      _event(
        id: 'created',
        type: RideEventType.rideCreated,
        createdAt: start,
        payload: const {'role': 'lead'},
      ),
      _upsert('line', line, start.add(const Duration(minutes: 1))),
      _upsert('area', area, start.add(const Duration(minutes: 1))),
      _upsert('altitude', altitude, start.add(const Duration(minutes: 1))),
      _upsert(
        'area-edit-a',
        OperationalBoundary(
          id: area.id,
          label: area.label,
          kind: area.kind,
          points: area.points,
          source: area.source,
          updatedAt: editTime,
          enabled: true,
        ),
        editTime,
      ),
      _upsert(
        'area-edit-z',
        OperationalBoundary(
          id: area.id,
          label: area.label,
          kind: area.kind,
          points: area.points,
          source: area.source,
          updatedAt: editTime,
          enabled: false,
        ),
        editTime,
      ),
    ];

    final reducer = const OperationalBoundaryReducer();
    final forward = reducer.fromEvents(events);
    final reverse = reducer.fromEvents(events.reversed);

    expect(
      forward.map((boundary) => boundary.toJson()),
      reverse.map((boundary) => boundary.toJson()),
    );
    expect(forward, hasLength(3));
    expect(
      forward.singleWhere((boundary) => boundary.id == 'area').enabled,
      isFalse,
    );
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
