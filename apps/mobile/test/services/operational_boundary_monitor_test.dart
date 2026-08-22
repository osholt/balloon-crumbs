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
        altitudeDatum: AltitudeDatum.wgs84Ellipsoid,
      ),
      isEmpty,
    );
    final below = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 5)),
      altitudeMeters: 190,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
    );
    final stillBelow = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 10)),
      altitudeMeters: 205,
      altitudeDatum: AltitudeDatum.wgs84Geoid,
    );
    final recovered = monitor.evaluate(
      boundaries: [boundary],
      position: const GeoPoint(latitude: 51, longitude: -2),
      now: start.add(const Duration(seconds: 15)),
      altitudeMeters: 225,
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
}

OperationalBoundary _boundary({
  required String id,
  required OperationalBoundaryKind kind,
  List<GeoPoint> points = const [],
  double? lower,
  double? upper,
}) => OperationalBoundary(
  id: id,
  label: id,
  kind: kind,
  points: points,
  source: 'Test advisory',
  updatedAt: DateTime.utc(2026, 8, 22),
  lowerAltitudeMeters: lower,
  upperAltitudeMeters: upper,
  altitudeDatum: AltitudeDatum.wgs84Geoid,
);
