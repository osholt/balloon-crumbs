import 'dart:math' as math;

import '../domain/altitude.dart';
import '../domain/geo_point.dart';
import '../domain/operational_boundary.dart';

enum OperationalBoundaryAlertKind {
  lineCrossed,
  areaEntered,
  areaExited,
  belowMinimumAltitude,
  aboveMaximumAltitude,
}

class OperationalBoundaryAlert {
  const OperationalBoundaryAlert({required this.boundary, required this.kind});

  final OperationalBoundary boundary;
  final OperationalBoundaryAlertKind kind;

  String get message => switch (kind) {
    OperationalBoundaryAlertKind.lineCrossed =>
      '${boundary.label} boundary crossed',
    OperationalBoundaryAlertKind.areaEntered => '${boundary.label} entered',
    OperationalBoundaryAlertKind.areaExited => '${boundary.label} exited',
    OperationalBoundaryAlertKind.belowMinimumAltitude =>
      '${boundary.label}: below ${boundary.lowerAltitudeMeters!.round()} m',
    OperationalBoundaryAlertKind.aboveMaximumAltitude =>
      '${boundary.label}: above ${boundary.upperAltitudeMeters!.round()} m',
  };
}

/// Detects crossings across any number of shared boundaries.
class OperationalBoundaryMonitor {
  OperationalBoundaryMonitor({
    this.repeatCooldown = const Duration(minutes: 2),
    this.altitudeHysteresisMeters = 20,
  });

  final Duration repeatCooldown;
  final double altitudeHysteresisMeters;
  GeoPoint? _previousPosition;
  final _insideByBoundary = <String, bool>{};
  final _altitudeStateByBoundary = <String, int>{};
  final _lastAlertAt = <String, DateTime>{};

  List<OperationalBoundaryAlert> evaluate({
    required Iterable<OperationalBoundary> boundaries,
    required GeoPoint position,
    required DateTime now,
    double? altitudeMeters,
    AltitudeDatum altitudeDatum = AltitudeDatum.unknown,
  }) {
    final alerts = <OperationalBoundaryAlert>[];
    final previousPosition = _previousPosition;
    for (final boundary in boundaries) {
      switch (boundary.kind) {
        case OperationalBoundaryKind.line:
          if (previousPosition != null &&
              _crossesLine(previousPosition, position, boundary.points) &&
              _canAlert('${boundary.id}:line', now)) {
            alerts.add(
              OperationalBoundaryAlert(
                boundary: boundary,
                kind: OperationalBoundaryAlertKind.lineCrossed,
              ),
            );
          }
        case OperationalBoundaryKind.area:
          final inside = _insidePolygon(position, boundary.points);
          final previousInside = _insideByBoundary[boundary.id];
          if (previousInside != null &&
              previousInside != inside &&
              _canAlert('${boundary.id}:area', now)) {
            alerts.add(
              OperationalBoundaryAlert(
                boundary: boundary,
                kind: inside
                    ? OperationalBoundaryAlertKind.areaEntered
                    : OperationalBoundaryAlertKind.areaExited,
              ),
            );
          }
          _insideByBoundary[boundary.id] = inside;
        case OperationalBoundaryKind.altitudeBand:
          break;
      }

      final horizontalApplies =
          boundary.kind == OperationalBoundaryKind.altitudeBand ||
          boundary.kind == OperationalBoundaryKind.line ||
          _insideByBoundary[boundary.id] == true;
      if (!horizontalApplies ||
          !boundary.hasAltitudeBand ||
          altitudeMeters == null ||
          altitudeDatum != boundary.altitudeDatum) {
        continue;
      }
      final previousState = _altitudeStateByBoundary[boundary.id] ?? 0;
      final nextState = _altitudeState(boundary, altitudeMeters, previousState);
      if (nextState != previousState && nextState != 0) {
        final key = '${boundary.id}:altitude:$nextState';
        if (_canAlert(key, now)) {
          alerts.add(
            OperationalBoundaryAlert(
              boundary: boundary,
              kind: nextState < 0
                  ? OperationalBoundaryAlertKind.belowMinimumAltitude
                  : OperationalBoundaryAlertKind.aboveMaximumAltitude,
            ),
          );
        }
      }
      _altitudeStateByBoundary[boundary.id] = nextState;
    }
    _previousPosition = position;
    return alerts;
  }

  int _altitudeState(
    OperationalBoundary boundary,
    double altitude,
    int previous,
  ) {
    final lower = boundary.lowerAltitudeMeters;
    final upper = boundary.upperAltitudeMeters;
    if (previous < 0 &&
        lower != null &&
        altitude < lower + altitudeHysteresisMeters) {
      return -1;
    }
    if (previous > 0 &&
        upper != null &&
        altitude > upper - altitudeHysteresisMeters) {
      return 1;
    }
    if (lower != null && altitude < lower) return -1;
    if (upper != null && altitude > upper) return 1;
    return 0;
  }

  bool _canAlert(String key, DateTime now) {
    final previous = _lastAlertAt[key];
    if (previous != null && now.difference(previous) < repeatCooldown) {
      return false;
    }
    _lastAlertAt[key] = now;
    return true;
  }

  static bool _crossesLine(GeoPoint from, GeoPoint to, List<GeoPoint> line) {
    for (var index = 0; index < line.length - 1; index++) {
      if (_segmentsIntersect(from, to, line[index], line[index + 1])) {
        return true;
      }
    }
    return false;
  }

  static bool _segmentsIntersect(
    GeoPoint a,
    GeoPoint b,
    GeoPoint c,
    GeoPoint d,
  ) {
    double orientation(GeoPoint p, GeoPoint q, GeoPoint r) =>
        (q.longitude - p.longitude) * (r.latitude - p.latitude) -
        (q.latitude - p.latitude) * (r.longitude - p.longitude);
    const epsilon = 1e-12;
    bool opposite(double first, double second) =>
        (first > epsilon && second < -epsilon) ||
        (first < -epsilon && second > epsilon);
    bool onSegment(GeoPoint start, GeoPoint point, GeoPoint end) =>
        point.longitude >= math.min(start.longitude, end.longitude) - epsilon &&
        point.longitude <= math.max(start.longitude, end.longitude) + epsilon &&
        point.latitude >= math.min(start.latitude, end.latitude) - epsilon &&
        point.latitude <= math.max(start.latitude, end.latitude) + epsilon;

    final first = orientation(a, b, c);
    final second = orientation(a, b, d);
    final third = orientation(c, d, a);
    final fourth = orientation(c, d, b);
    if (opposite(first, second) && opposite(third, fourth)) return true;
    if (first.abs() <= epsilon && onSegment(a, c, b)) return true;
    if (second.abs() <= epsilon && onSegment(a, d, b)) return true;
    if (third.abs() <= epsilon && onSegment(c, a, d)) return true;
    return fourth.abs() <= epsilon && onSegment(c, b, d);
  }

  static bool _insidePolygon(GeoPoint point, List<GeoPoint> polygon) {
    var inside = false;
    for (
      var first = 0, second = polygon.length - 1;
      first < polygon.length;
      second = first++
    ) {
      final a = polygon[first];
      final b = polygon[second];
      final intersects =
          ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude);
      if (intersects) inside = !inside;
    }
    return inside;
  }
}
