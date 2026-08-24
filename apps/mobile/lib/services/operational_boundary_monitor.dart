import 'dart:math' as math;

import '../domain/altitude.dart';
import '../domain/altitude_unit.dart';
import '../domain/geo_point.dart';
import '../domain/operational_boundary.dart';

enum OperationalBoundaryAlertKind {
  lineCrossed,
  areaEntered,
  areaExited,
  belowMinimumAltitude,
  aboveMaximumAltitude,
}

enum OperationalBoundaryFixAssessment {
  usable,
  stale,
  inaccurate,
  missing,
  altitudeSourceMismatch,
  altitudeDatumMismatch,
  altitudeInaccurate,
}

class OperationalBoundaryAlert {
  const OperationalBoundaryAlert({
    required this.boundary,
    required this.kind,
    required this.observedAt,
    required this.assessment,
    this.position,
    this.altitudeMeters,
  });

  final OperationalBoundary boundary;
  final OperationalBoundaryAlertKind kind;
  final DateTime observedAt;
  final OperationalBoundaryFixAssessment assessment;
  final GeoPoint? position;
  final double? altitudeMeters;

  bool get confirmed => assessment == OperationalBoundaryFixAssessment.usable;

  String get message {
    final description = switch (kind) {
      OperationalBoundaryAlertKind.lineCrossed =>
        '${boundary.label} boundary crossed',
      OperationalBoundaryAlertKind.areaEntered => '${boundary.label} entered',
      OperationalBoundaryAlertKind.areaExited => '${boundary.label} exited',
      OperationalBoundaryAlertKind.belowMinimumAltitude =>
        '${boundary.label}: below ${boundary.altitudeUnit.altitude(boundary.lowerAltitudeMeters!)}',
      OperationalBoundaryAlertKind.aboveMaximumAltitude =>
        '${boundary.label}: above ${boundary.altitudeUnit.altitude(boundary.upperAltitudeMeters!)}',
    };
    if (confirmed) return description;
    final quality = switch (assessment) {
      OperationalBoundaryFixAssessment.stale => 'stale location',
      OperationalBoundaryFixAssessment.inaccurate => 'low-accuracy location',
      OperationalBoundaryFixAssessment.missing => 'missing location',
      OperationalBoundaryFixAssessment.altitudeSourceMismatch =>
        'unaccepted altitude source',
      OperationalBoundaryFixAssessment.altitudeDatumMismatch =>
        'different altitude reference',
      OperationalBoundaryFixAssessment.altitudeInaccurate =>
        'low-accuracy altitude',
      OperationalBoundaryFixAssessment.usable => 'usable location',
    };
    return 'Possible $description — $quality; not confirmed';
  }
}

/// Detects independent crossings across any number of shared advisories.
///
/// Only a fresh, sufficiently accurate sample advances the trusted state. A
/// poor sample may explain a possible crossing, but it cannot turn uncertainty
/// into a confirmed warning or prevent the next good fix from doing so.
class OperationalBoundaryMonitor {
  OperationalBoundaryMonitor({
    this.repeatCooldown = const Duration(minutes: 2),
    this.maximumFixAge = const Duration(seconds: 30),
    this.maximumHorizontalAccuracyMeters = 100,
    this.maximumAltitudeAccuracyMeters = 50,
    this.horizontalHysteresisMeters = 15,
    this.altitudeHysteresisMeters = 20,
  });

  final Duration repeatCooldown;
  final Duration maximumFixAge;
  final double maximumHorizontalAccuracyMeters;
  final double maximumAltitudeAccuracyMeters;
  final double horizontalHysteresisMeters;
  final double altitudeHysteresisMeters;

  final _previousTrustedPositionByBoundary = <String, GeoPoint>{};
  final _insideByBoundary = <String, bool>{};
  final _altitudeStateByBoundary = <String, int>{};
  final _revisionByBoundary = <String, String>{};
  final _lastAlertAt = <String, DateTime>{};

  List<OperationalBoundaryAlert> evaluate({
    required Iterable<OperationalBoundary> boundaries,
    required GeoPoint? position,
    required DateTime now,
    DateTime? recordedAt,
    double? horizontalAccuracyMeters,
    double? altitudeMeters,
    AltitudeSource altitudeSource = AltitudeSource.unknown,
    AltitudeDatum altitudeDatum = AltitudeDatum.unknown,
    double? altitudeAccuracyMeters,
  }) {
    final active = boundaries
        .where((boundary) => boundary.enabled && boundary.appliesAt(now))
        .toList(growable: false);
    final activeIds = active.map((boundary) => boundary.id).toSet();
    _previousTrustedPositionByBoundary.removeWhere(
      (id, _) => !activeIds.contains(id),
    );
    _insideByBoundary.removeWhere((id, _) => !activeIds.contains(id));
    _altitudeStateByBoundary.removeWhere((id, _) => !activeIds.contains(id));
    _revisionByBoundary.removeWhere((id, _) => !activeIds.contains(id));
    _lastAlertAt.removeWhere(
      (key, _) => !activeIds.any((id) => key.startsWith('$id:')),
    );
    for (final boundary in active) {
      final revision =
          '${boundary.kind.name}:'
          '${boundary.updatedAt.toUtc().toIso8601String()}';
      if (_revisionByBoundary[boundary.id] == revision) continue;
      _previousTrustedPositionByBoundary.remove(boundary.id);
      _insideByBoundary.remove(boundary.id);
      _altitudeStateByBoundary.remove(boundary.id);
      _lastAlertAt.removeWhere((key, _) => key.startsWith('${boundary.id}:'));
      _revisionByBoundary[boundary.id] = revision;
    }
    final horizontalAssessment = _horizontalAssessment(
      position: position,
      recordedAt: recordedAt ?? now,
      horizontalAccuracyMeters: horizontalAccuracyMeters,
      now: now,
    );
    if (position == null) return const [];

    final alerts = <OperationalBoundaryAlert>[];
    final horizontalUsable =
        horizontalAssessment == OperationalBoundaryFixAssessment.usable;

    for (final boundary in active) {
      switch (boundary.kind) {
        case OperationalBoundaryKind.line:
          final previous = _previousTrustedPositionByBoundary[boundary.id];
          if (previous != null) {
            final crossing = _lineCrossing(
              previous,
              position,
              boundary.points,
              horizontalHysteresisMeters,
            );
            if (crossing != null &&
                _allowsDirection(boundary.warningDirection, crossing) &&
                _canAlert(
                  '${boundary.id}:line:${crossing.name}:${horizontalUsable ? 'confirmed' : 'possible'}',
                  now,
                )) {
              alerts.add(
                OperationalBoundaryAlert(
                  boundary: boundary,
                  kind: OperationalBoundaryAlertKind.lineCrossed,
                  observedAt: recordedAt ?? now,
                  assessment: horizontalAssessment,
                  position: position,
                ),
              );
            }
          }
          if (horizontalUsable &&
              _distanceToPolylineMeters(position, boundary.points) >=
                  horizontalHysteresisMeters) {
            _previousTrustedPositionByBoundary[boundary.id] = position;
          }
        case OperationalBoundaryKind.area:
          final inside = _insidePolygon(position, boundary.points);
          final previousInside = _insideByBoundary[boundary.id];
          final farEnough =
              _distanceToPolylineMeters(position, [
                ...boundary.points,
                boundary.points.first,
              ]) >=
              horizontalHysteresisMeters;
          if (previousInside != null &&
              previousInside != inside &&
              farEnough &&
              _allowsAreaDirection(boundary.warningDirection, inside) &&
              _canAlert(
                '${boundary.id}:area:$inside:${horizontalUsable ? 'confirmed' : 'possible'}',
                now,
              )) {
            alerts.add(
              OperationalBoundaryAlert(
                boundary: boundary,
                kind: inside
                    ? OperationalBoundaryAlertKind.areaEntered
                    : OperationalBoundaryAlertKind.areaExited,
                observedAt: recordedAt ?? now,
                assessment: horizontalAssessment,
                position: position,
              ),
            );
          }
          if (horizontalUsable && (previousInside == null || farEnough)) {
            _insideByBoundary[boundary.id] = inside;
          }
        case OperationalBoundaryKind.altitudeBand:
          break;
      }

      final horizontalApplies =
          boundary.kind == OperationalBoundaryKind.altitudeBand ||
          boundary.kind == OperationalBoundaryKind.line ||
          _insideByBoundary[boundary.id] == true;
      if (!horizontalApplies ||
          !boundary.hasAltitudeBand ||
          altitudeMeters == null) {
        continue;
      }
      final altitudeQuality = _altitudeAssessment(
        boundary: boundary,
        altitudeSource: altitudeSource,
        altitudeDatum: altitudeDatum,
        altitudeAccuracyMeters: altitudeAccuracyMeters,
      );
      if (altitudeQuality ==
              OperationalBoundaryFixAssessment.altitudeSourceMismatch ||
          altitudeQuality ==
              OperationalBoundaryFixAssessment.altitudeDatumMismatch) {
        continue;
      }
      final altitudeAssessment = horizontalUsable
          ? altitudeQuality
          : horizontalAssessment;
      final previousState = _altitudeStateByBoundary[boundary.id] ?? 0;
      final nextState = _altitudeState(boundary, altitudeMeters, previousState);
      if (nextState != previousState && nextState != 0) {
        final key =
            '${boundary.id}:altitude:$nextState:${altitudeAssessment == OperationalBoundaryFixAssessment.usable ? 'confirmed' : 'possible'}';
        if (_canAlert(key, now)) {
          alerts.add(
            OperationalBoundaryAlert(
              boundary: boundary,
              kind: nextState < 0
                  ? OperationalBoundaryAlertKind.belowMinimumAltitude
                  : OperationalBoundaryAlertKind.aboveMaximumAltitude,
              observedAt: recordedAt ?? now,
              assessment: altitudeAssessment,
              position: position,
              altitudeMeters: altitudeMeters,
            ),
          );
        }
      }
      if (horizontalUsable &&
          altitudeAssessment == OperationalBoundaryFixAssessment.usable) {
        _altitudeStateByBoundary[boundary.id] = nextState;
      }
    }

    return alerts;
  }

  OperationalBoundaryFixAssessment _horizontalAssessment({
    required GeoPoint? position,
    required DateTime recordedAt,
    required double? horizontalAccuracyMeters,
    required DateTime now,
  }) {
    if (position == null) return OperationalBoundaryFixAssessment.missing;
    final age = now.difference(recordedAt);
    if (age.isNegative || age > maximumFixAge) {
      return OperationalBoundaryFixAssessment.stale;
    }
    if (horizontalAccuracyMeters != null &&
        (!horizontalAccuracyMeters.isFinite ||
            horizontalAccuracyMeters < 0 ||
            horizontalAccuracyMeters > maximumHorizontalAccuracyMeters)) {
      return OperationalBoundaryFixAssessment.inaccurate;
    }
    return OperationalBoundaryFixAssessment.usable;
  }

  OperationalBoundaryFixAssessment _altitudeAssessment({
    required OperationalBoundary boundary,
    required AltitudeSource altitudeSource,
    required AltitudeDatum altitudeDatum,
    required double? altitudeAccuracyMeters,
  }) {
    if (!boundary.acceptedAltitudeSources.contains(altitudeSource)) {
      return OperationalBoundaryFixAssessment.altitudeSourceMismatch;
    }
    if (altitudeDatum != boundary.altitudeDatum) {
      return OperationalBoundaryFixAssessment.altitudeDatumMismatch;
    }
    if (altitudeAccuracyMeters != null &&
        (!altitudeAccuracyMeters.isFinite ||
            altitudeAccuracyMeters < 0 ||
            altitudeAccuracyMeters > maximumAltitudeAccuracyMeters)) {
      return OperationalBoundaryFixAssessment.altitudeInaccurate;
    }
    return OperationalBoundaryFixAssessment.usable;
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

  static bool _allowsAreaDirection(
    OperationalBoundaryWarningDirection direction,
    bool nowInside,
  ) =>
      direction == OperationalBoundaryWarningDirection.either ||
      (direction == OperationalBoundaryWarningDirection.entering &&
          nowInside) ||
      (direction == OperationalBoundaryWarningDirection.leaving && !nowInside);

  static bool _allowsDirection(
    OperationalBoundaryWarningDirection configured,
    OperationalBoundaryWarningDirection observed,
  ) =>
      configured == OperationalBoundaryWarningDirection.either ||
      configured == observed;

  static OperationalBoundaryWarningDirection? _lineCrossing(
    GeoPoint from,
    GeoPoint to,
    List<GeoPoint> line,
    double hysteresisMeters,
  ) {
    if (_distanceToPolylineMeters(from, line) < hysteresisMeters ||
        _distanceToPolylineMeters(to, line) < hysteresisMeters) {
      return null;
    }
    for (var index = 0; index < line.length - 1; index++) {
      final start = line[index];
      final end = line[index + 1];
      final projected = _projectTogether([from, to, start, end]);
      if (!_segmentsIntersect(
        projected[0],
        projected[1],
        projected[2],
        projected[3],
      )) {
        continue;
      }
      final before = _side(projected[2], projected[3], projected[0]);
      final after = _side(projected[2], projected[3], projected[1]);
      if (before == 0 || after == 0 || before.sign == after.sign) continue;
      return before < after
          ? OperationalBoundaryWarningDirection.entering
          : OperationalBoundaryWarningDirection.leaving;
    }
    return null;
  }

  static double _side(_XY a, _XY b, _XY point) =>
      (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x);

  static bool _segmentsIntersect(_XY a, _XY b, _XY c, _XY d) {
    final first = _side(a, b, c);
    final second = _side(a, b, d);
    final third = _side(c, d, a);
    final fourth = _side(c, d, b);
    const epsilon = 1e-6;
    return ((first > epsilon && second < -epsilon) ||
            (first < -epsilon && second > epsilon)) &&
        ((third > epsilon && fourth < -epsilon) ||
            (third < -epsilon && fourth > epsilon));
  }

  static double _distanceToPolylineMeters(GeoPoint point, List<GeoPoint> line) {
    var best = double.infinity;
    for (var index = 0; index < line.length - 1; index++) {
      final projected = _projectTogether([point, line[index], line[index + 1]]);
      best = math.min(
        best,
        _distanceToSegment(projected[0], projected[1], projected[2]),
      );
    }
    return best;
  }

  static double _distanceToSegment(_XY point, _XY start, _XY end) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      return math.sqrt(
        math.pow(point.x - start.x, 2) + math.pow(point.y - start.y, 2),
      );
    }
    final fraction =
        (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
            .clamp(0.0, 1.0);
    final x = start.x + fraction * dx;
    final y = start.y + fraction * dy;
    return math.sqrt(math.pow(point.x - x, 2) + math.pow(point.y - y, 2));
  }

  static List<_XY> _projectTogether(List<GeoPoint> points) {
    const earthRadiusMeters = 6371008.8;
    final latitudeOrigin =
        points.map((point) => point.latitude).reduce((a, b) => a + b) /
        points.length;
    final longitudeOrigin = points.first.longitude;
    final latitudeScale = math.pi / 180 * earthRadiusMeters;
    final longitudeScale =
        latitudeScale * math.cos(latitudeOrigin * math.pi / 180);
    return [
      for (final point in points)
        _XY(
          _normaliseLongitude(point.longitude - longitudeOrigin) *
              longitudeScale,
          (point.latitude - latitudeOrigin) * latitudeScale,
        ),
    ];
  }

  static double _normaliseLongitude(double value) {
    var result = value;
    while (result > 180) {
      result -= 360;
    }
    while (result < -180) {
      result += 360;
    }
    return result;
  }

  static bool _insidePolygon(GeoPoint point, List<GeoPoint> polygon) {
    final projected = _projectTogether([point, ...polygon]);
    final target = projected.first;
    final shape = projected.skip(1).toList(growable: false);
    var inside = false;
    for (
      var first = 0, second = shape.length - 1;
      first < shape.length;
      second = first++
    ) {
      final a = shape[first];
      final b = shape[second];
      final intersects =
          ((a.y > target.y) != (b.y > target.y)) &&
          (target.x < (b.x - a.x) * (target.y - a.y) / (b.y - a.y) + a.x);
      if (intersects) inside = !inside;
    }
    return inside;
  }
}

class _XY {
  const _XY(this.x, this.y);

  final double x;
  final double y;
}
