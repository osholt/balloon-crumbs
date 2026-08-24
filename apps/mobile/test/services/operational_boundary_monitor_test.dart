import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/operational_boundary.dart';
import 'package:balloon_crumbs/services/operational_boundary_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 22, 7);

  test('detects independent line and area crossings', () {
    final monitor = OperationalBoundaryMonitor();
    final boundaries = [
      _boundary(
        id: 'line',
        kind: OperationalBoundaryKind.line,
        points: const [
          GeoPoint(latitude: 51.0, longitude: -2.0),
          GeoPoint(latitude: 51.1, longitude: -2.0),
        ],
      ),
      _boundary(
        id: 'area',
        kind: OperationalBoundaryKind.area,
        points: const [
          GeoPoint(latitude: 51.0, longitude: -1.9),
          GeoPoint(latitude: 51.1, longitude: -1.9),
          GeoPoint(latitude: 51.1, longitude: -1.8),
          GeoPoint(latitude: 51.0, longitude: -1.8),
        ],
      ),
    ];
    monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 51.05, longitude: -2.05),
      now: start,
    );

    final lineAlerts = monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 51.05, longitude: -1.95),
      now: start.add(const Duration(seconds: 10)),
    );
    final areaAlerts = monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 51.05, longitude: -1.85),
      now: start.add(const Duration(seconds: 20)),
    );

    expect(
      lineAlerts.map((alert) => alert.kind),
      contains(OperationalBoundaryAlertKind.lineCrossed),
    );
    expect(
      areaAlerts.map((alert) => alert.kind),
      contains(OperationalBoundaryAlertKind.areaEntered),
    );
  });

  test('altitude alerts require the declared datum and apply hysteresis', () {
    final monitor = OperationalBoundaryMonitor();
    final boundary = _boundary(
      id: 'height',
      kind: OperationalBoundaryKind.altitudeBand,
      lower: 200,
      upper: 800,
    );

    expect(
      monitor.evaluate(
        boundaries: [boundary],
        position: const GeoPoint(latitude: 51, longitude: -2),
        now: start,
        altitudeMeters: 190,
        altitudeSource: AltitudeSource.gnss,
        altitudeDatum: AltitudeDatum.wgs84Ellipsoid,
      ),
      isEmpty,
    );
    final below = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 5)),
      altitudeMeters: 190,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
    );
    final stillBelow = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 10)),
      altitudeMeters: 205,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
    );
    final recovered = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 15)),
      altitudeMeters: 225,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
    );

    expect(
      below.single.kind,
      OperationalBoundaryAlertKind.belowMinimumAltitude,
    );
    expect(stillBelow, isEmpty);
    expect(recovered, isEmpty);
  });

  test('collinear movement beyond a line does not report a crossing', () {
    final monitor = OperationalBoundaryMonitor();
    final boundary = _boundary(
      id: 'short-line',
      kind: OperationalBoundaryKind.line,
      points: const [
        GeoPoint(latitude: 51, longitude: -2),
        GeoPoint(latitude: 51, longitude: -1.9),
      ],
    );
    monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -1.7),
      now: start,
    );

    final alerts = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -1.6),
      now: start.add(const Duration(seconds: 10)),
    );

    expect(alerts, isEmpty);
  });

  test('line direction and GPS hysteresis suppress wrong-way jitter', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final boundary = _boundary(
      id: 'oriented-line',
      kind: OperationalBoundaryKind.line,
      warningDirection: OperationalBoundaryWarningDirection.entering,
      points: const [
        GeoPoint(latitude: 51.0, longitude: -2.0),
        GeoPoint(latitude: 51.1, longitude: -2.0),
      ],
    );
    monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -1.99),
      now: start,
    );
    expect(
      monitor.evaluate(
        boundaries: [boundary],
        position: const GeoPoint(latitude: 51.05, longitude: -2.0001),
        now: start.add(const Duration(seconds: 1)),
      ),
      isEmpty,
    );
    final entering = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -2.01),
      now: start.add(const Duration(seconds: 2)),
    );
    expect(entering.single.confirmed, isTrue);

    final wrongWay = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -1.99),
      now: start.add(const Duration(seconds: 3)),
    );
    expect(wrongWay, isEmpty);
  });

  test('stale crossing is possible then a fresh fix confirms it', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final boundary = _boundary(
      id: 'freshness',
      kind: OperationalBoundaryKind.line,
      points: const [
        GeoPoint(latitude: 51, longitude: -2),
        GeoPoint(latitude: 51.1, longitude: -2),
      ],
    );
    monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -2.01),
      recordedAt: start,
      now: start,
    );
    final stale = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -1.99),
      recordedAt: start,
      now: start.add(const Duration(minutes: 1)),
    );
    expect(stale.single.confirmed, isFalse);
    expect(stale.single.message, contains('not confirmed'));

    final fresh = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -1.99),
      recordedAt: start.add(const Duration(minutes: 1, seconds: 1)),
      now: start.add(const Duration(minutes: 1, seconds: 1)),
    );
    expect(fresh.single.confirmed, isTrue);
  });

  test('a missing fix does not advance or erase trusted line state', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final boundary = _boundary(
      id: 'missing-fix',
      kind: OperationalBoundaryKind.line,
      points: const [
        GeoPoint(latitude: 51, longitude: -2),
        GeoPoint(latitude: 51.1, longitude: -2),
      ],
    );
    monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -2.01),
      now: start,
    );
    expect(
      monitor.evaluate(
        boundaries: [boundary],
        position: null,
        now: start.add(const Duration(seconds: 1)),
      ),
      isEmpty,
    );

    final fresh = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51.05, longitude: -1.99),
      now: start.add(const Duration(seconds: 2)),
    );

    expect(fresh.single.kind, OperationalBoundaryAlertKind.lineCrossed);
    expect(fresh.single.confirmed, isTrue);
  });

  test('disabled and out-of-window boundaries are ignored', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final boundaries = [
      _boundary(
        id: 'disabled',
        kind: OperationalBoundaryKind.area,
        enabled: false,
        points: _square,
      ),
      _boundary(
        id: 'expired',
        kind: OperationalBoundaryKind.area,
        validUntil: start.subtract(const Duration(seconds: 1)),
        points: _square,
      ),
    ];
    monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 50.9, longitude: -2.2),
      now: start,
    );
    expect(
      monitor.evaluate(
        boundaries: boundaries,
        position: const GeoPoint(latitude: 51.05, longitude: -2.05),
        now: start.add(const Duration(seconds: 1)),
      ),
      isEmpty,
    );
  });

  test('overlapping named areas alert independently', () {
    final monitor = OperationalBoundaryMonitor();
    final boundaries = [
      _boundary(id: 'one', kind: OperationalBoundaryKind.area, points: _square),
      _boundary(id: 'two', kind: OperationalBoundaryKind.area, points: _square),
    ];
    monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 50.9, longitude: -2.2),
      now: start,
    );
    final alerts = monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 51.05, longitude: -2.05),
      now: start.add(const Duration(seconds: 1)),
    );
    expect(alerts.map((alert) => alert.boundary.id), {'one', 'two'});
  });

  test('proximity to one line does not freeze another line state', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final boundaries = [
      _boundary(
        id: 'nearby-line',
        kind: OperationalBoundaryKind.line,
        points: const [
          GeoPoint(latitude: 51.0, longitude: -2.0),
          GeoPoint(latitude: 51.1, longitude: -2.0),
        ],
      ),
      _boundary(
        id: 'crossed-line',
        kind: OperationalBoundaryKind.line,
        points: const [
          GeoPoint(latitude: 51.05, longitude: -2.2),
          GeoPoint(latitude: 51.05, longitude: -1.8),
        ],
      ),
    ];
    monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 51.04, longitude: -2.0001),
      now: start,
    );
    monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 51.0499, longitude: -2.0001),
      now: start.add(const Duration(seconds: 1)),
    );

    final crossed = monitor.evaluate(
      boundaries: boundaries,
      position: const GeoPoint(latitude: 51.06, longitude: -2.0001),
      now: start.add(const Duration(seconds: 2)),
    );

    expect(crossed, hasLength(1));
    expect(crossed.single.boundary.id, 'crossed-line');
  });

  test('area crossing works across the antimeridian', () {
    final monitor = OperationalBoundaryMonitor();
    final boundary = _boundary(
      id: 'date-line',
      kind: OperationalBoundaryKind.area,
      points: const [
        GeoPoint(latitude: -1, longitude: 179.5),
        GeoPoint(latitude: 1, longitude: 179.5),
        GeoPoint(latitude: 1, longitude: -179.5),
        GeoPoint(latitude: -1, longitude: -179.5),
      ],
    );
    monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 0, longitude: 178),
      now: start,
    );
    final alerts = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 0, longitude: -179.8),
      now: start.add(const Duration(seconds: 1)),
    );
    expect(alerts.single.kind, OperationalBoundaryAlertKind.areaEntered);
  });

  test('altitude source and accuracy cannot create a confirmed warning', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final boundary = _boundary(
      id: 'altitude-quality',
      kind: OperationalBoundaryKind.altitudeBand,
      lower: 200,
      upper: 800,
    );
    expect(
      monitor.evaluate(
        boundaries: [boundary],
        position: const GeoPoint(latitude: 51, longitude: -2),
        now: start,
        altitudeMeters: 900,
        altitudeSource: AltitudeSource.unknown,
        altitudeDatum: AltitudeDatum.wgs84Geoid,
      ),
      isEmpty,
    );
    final inaccurate = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 1)),
      altitudeMeters: 900,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
      altitudeAccuracyMeters: 100,
    );
    expect(inaccurate.single.confirmed, isFalse);

    final accurate = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 2)),
      altitudeMeters: 900,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
      altitudeAccuracyMeters: 5,
    );
    expect(accurate.single.confirmed, isTrue);
  });

  test('a stale horizontal fix cannot confirm an altitude warning', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final boundary = _boundary(
      id: 'stale-altitude',
      kind: OperationalBoundaryKind.altitudeBand,
      upper: 800,
    );

    final stale = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      recordedAt: start,
      now: start.add(const Duration(minutes: 1)),
      altitudeMeters: 900,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
      altitudeAccuracyMeters: 5,
    );
    expect(stale.single.confirmed, isFalse);
    expect(stale.single.assessment, OperationalBoundaryFixAssessment.stale);

    final fresh = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      recordedAt: start.add(const Duration(minutes: 1, seconds: 1)),
      now: start.add(const Duration(minutes: 1, seconds: 1)),
      altitudeMeters: 900,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
      altitudeAccuracyMeters: 5,
    );
    expect(fresh.single.confirmed, isTrue);
  });

  test('disabling a boundary clears its trusted transition state', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final enabled = _boundary(
      id: 're-enabled-area',
      kind: OperationalBoundaryKind.area,
      points: _square,
    );
    final disabled = _boundary(
      id: enabled.id,
      kind: enabled.kind,
      enabled: false,
      points: enabled.points,
    );
    monitor.evaluate(
      boundaries: [enabled],
      position: const GeoPoint(latitude: 50.9, longitude: -2.2),
      now: start,
    );
    monitor.evaluate(
      boundaries: [disabled],
      position: const GeoPoint(latitude: 51.05, longitude: -2.05),
      now: start.add(const Duration(seconds: 1)),
    );

    final firstFixAfterReEnable = monitor.evaluate(
      boundaries: [enabled],
      position: const GeoPoint(latitude: 51.05, longitude: -2.05),
      now: start.add(const Duration(seconds: 2)),
    );
    expect(firstFixAfterReEnable, isEmpty);

    final exit = monitor.evaluate(
      boundaries: [enabled],
      position: const GeoPoint(latitude: 50.9, longitude: -2.2),
      now: start.add(const Duration(seconds: 3)),
    );
    expect(exit.single.kind, OperationalBoundaryAlertKind.areaExited);
  });

  test('editing a boundary resets state before evaluating new geometry', () {
    final monitor = OperationalBoundaryMonitor(repeatCooldown: Duration.zero);
    final original = _boundary(
      id: 'edited-area',
      kind: OperationalBoundaryKind.area,
      points: _square,
    );
    const position = GeoPoint(latitude: 51.05, longitude: -2.05);
    monitor.evaluate(boundaries: [original], position: position, now: start);
    final edited = OperationalBoundary(
      id: original.id,
      label: original.label,
      kind: original.kind,
      points: const [
        GeoPoint(latitude: 52, longitude: -3.1),
        GeoPoint(latitude: 52.1, longitude: -3.1),
        GeoPoint(latitude: 52.1, longitude: -3),
        GeoPoint(latitude: 52, longitude: -3),
      ],
      source: original.source,
      updatedAt: original.updatedAt.add(const Duration(minutes: 1)),
    );

    final firstEditedFix = monitor.evaluate(
      boundaries: [edited],
      position: position,
      now: start.add(const Duration(minutes: 1)),
    );

    expect(firstEditedFix, isEmpty);
  });
}

const _square = [
  GeoPoint(latitude: 51, longitude: -2.1),
  GeoPoint(latitude: 51.1, longitude: -2.1),
  GeoPoint(latitude: 51.1, longitude: -2),
  GeoPoint(latitude: 51, longitude: -2),
];

OperationalBoundary _boundary({
  required String id,
  required OperationalBoundaryKind kind,
  List<GeoPoint> points = const [],
  double? lower,
  double? upper,
  bool enabled = true,
  DateTime? validUntil,
  OperationalBoundaryWarningDirection warningDirection =
      OperationalBoundaryWarningDirection.either,
}) => OperationalBoundary(
  id: id,
  label: id,
  kind: kind,
  points: points,
  source: 'Test advisory',
  updatedAt: DateTime.utc(2026, 8, 22),
  enabled: enabled,
  validUntil: validUntil,
  warningDirection: warningDirection,
  lowerAltitudeMeters: lower,
  upperAltitudeMeters: upper,
  altitudeDatum: AltitudeDatum.wgs84Geoid,
);
