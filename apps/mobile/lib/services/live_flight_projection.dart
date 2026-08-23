import 'dart:math' as math;

import '../domain/forecast_plan.dart';
import '../domain/geo_point.dart' as live;
import '../domain/imported_route.dart' as route;
import '../domain/rider_location.dart';
import 'open_meteo_wind.dart';

enum LiveFlightProjectionStatus {
  available,
  noStructuredPlan,
  noBalloonFix,
  staleBalloonFix,
  noCompatibleAltitude,
  noWind,
  staleWind,
  outsideWindValidity,
  noUsableWindVector,
  landed,
}

class LiveFlightProjection {
  const LiveFlightProjection({
    required this.track,
    required this.landingEnvelope,
    required this.computedAt,
    required this.windValidAt,
    required this.windFetchedAt,
    required this.windSource,
    required this.duration,
  });

  final List<route.GeoPoint> track;
  final List<route.GeoPoint> landingEnvelope;
  final DateTime computedAt;
  final DateTime windValidAt;
  final DateTime windFetchedAt;
  final String windSource;
  final Duration duration;
}

class LiveFlightProjectionAssessment {
  const LiveFlightProjectionAssessment(this.status, {this.projection});

  final LiveFlightProjectionStatus status;
  final LiveFlightProjection? projection;

  bool get isAvailable => projection != null;

  String get message => switch (status) {
    LiveFlightProjectionStatus.available =>
      'Recalculated from the latest balloon fix and forecast wind.',
    LiveFlightProjectionStatus.noStructuredPlan =>
      'A structured forecast plan is needed for a live projection.',
    LiveFlightProjectionStatus.noBalloonFix =>
      'Waiting for the balloon position and altitude.',
    LiveFlightProjectionStatus.staleBalloonFix =>
      'The balloon fix is too old to project safely.',
    LiveFlightProjectionStatus.noCompatibleAltitude =>
      'The balloon altitude datum cannot be compared with the plan.',
    LiveFlightProjectionStatus.noWind => 'No forecast wind field is available.',
    LiveFlightProjectionStatus.staleWind =>
      'The forecast wind field is stale; the last projection is not extended.',
    LiveFlightProjectionStatus.outsideWindValidity =>
      'The forecast is not valid near the current flight time.',
    LiveFlightProjectionStatus.noUsableWindVector =>
      'The forecast contains no usable wind at the balloon position.',
    LiveFlightProjectionStatus.landed =>
      'The balloon is marked LANDED; the forecast envelope is no longer extended.',
  };
}

/// Advisory projection from current aircraft telemetry and forecast model wind.
///
/// This is deliberately deterministic and has no network dependency. The wind
/// controller fetches a bounded field; this engine only consumes a fresh field,
/// applies the imported ascent/descent limits, and labels the result as model
/// output. It never changes the pilot's intended landing area.
class LiveFlightProjectionEngine {
  const LiveFlightProjectionEngine({
    this.maximumFixAge = const Duration(seconds: 45),
    this.maximumWindAge = const Duration(minutes: 30),
    this.maximumWindValidityOffset = const Duration(minutes: 90),
    this.maximumDuration = const Duration(hours: 6),
    this.step = const Duration(minutes: 1),
  });

  final Duration maximumFixAge;
  final Duration maximumWindAge;
  final Duration maximumWindValidityOffset;
  final Duration maximumDuration;
  final Duration step;

  LiveFlightProjectionAssessment evaluate({
    required ForecastPlanDocument? plan,
    required LocationSample? balloonFix,
    required WindForecastField? wind,
    required DateTime now,
    bool allowReferenceWind = false,
    bool flightLanded = false,
  }) {
    if (flightLanded) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.landed,
      );
    }
    if (plan == null) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.noStructuredPlan,
      );
    }
    if (balloonFix == null || balloonFix.altitudeMeters == null) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.noBalloonFix,
      );
    }
    final utcNow = now.toUtc();
    if (balloonFix.ageAt(utcNow) > maximumFixAge) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.staleBalloonFix,
      );
    }
    final altitudeMsl = _altitudeMsl(plan, balloonFix);
    if (altitudeMsl == null) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.noCompatibleAltitude,
      );
    }
    if (wind == null) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.noWind,
      );
    }
    if (!allowReferenceWind && !wind.isLiveForecast) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.noWind,
      );
    }
    if (!allowReferenceWind &&
        utcNow.difference(wind.fetchedAt.toUtc()).abs() > maximumWindAge) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.staleWind,
      );
    }
    if (utcNow.difference(wind.validAt.toUtc()).abs() >
        maximumWindValidityOffset) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.outsideWindValidity,
      );
    }

    final duration = _boundedDuration(plan);
    final primary = _integrate(
      start: balloonFix.position,
      startAltitudeMsl: altitudeMsl,
      duration: duration,
      wind: wind,
      altitudeAt: (fraction) =>
          _plannedAltitude(plan, fraction, startAltitudeMsl: altitudeMsl),
      constraints: plan.constraints,
      retainTrack: true,
      startedAt: utcNow,
      datum: balloonFix.altitudeDatum,
    );
    if (primary == null) {
      return const LiveFlightProjectionAssessment(
        LiveFlightProjectionStatus.noUsableWindVector,
      );
    }

    final endpoints = <route.GeoPoint>[];
    for (final level in openMeteoWindAltitudeLevels) {
      final target = math.min(
        level.toDouble(),
        plan.constraints.altitudeCeilingMetersMsl,
      );
      if (target < plan.launchElevationMetersMsl) continue;
      final endpoint = _integrate(
        start: balloonFix.position,
        startAltitudeMsl: altitudeMsl,
        duration: duration,
        wind: wind,
        altitudeAt: (fraction) => _candidateAltitude(
          fraction: fraction,
          duration: duration,
          startAltitudeMsl: altitudeMsl,
          targetAltitudeMsl: target,
          landingAltitudeMsl: plan.launchElevationMetersMsl,
          maximumAscentRate: plan.constraints.maximumAscentRateMetersPerSecond,
          maximumDescentRate:
              plan.constraints.maximumDescentRateMetersPerSecond,
        ),
        constraints: plan.constraints,
        retainTrack: false,
        startedAt: utcNow,
        datum: balloonFix.altitudeDatum,
      )?.last;
      if (endpoint != null) endpoints.add(endpoint);
    }
    endpoints.add(primary.last);
    final envelope = _convexHull(endpoints);
    return LiveFlightProjectionAssessment(
      LiveFlightProjectionStatus.available,
      projection: LiveFlightProjection(
        track: List.unmodifiable(primary),
        landingEnvelope: List.unmodifiable(envelope),
        computedAt: utcNow,
        windValidAt: wind.validAt.toUtc(),
        windFetchedAt: wind.fetchedAt.toUtc(),
        windSource: wind.sourceLabel,
        duration: duration,
      ),
    );
  }

  Duration _boundedDuration(ForecastPlanDocument plan) {
    final maximum = Duration(
      milliseconds: (plan.constraints.maximumDurationMinutes * 60000).round(),
    );
    final candidate = plan.plannedDuration < maximum
        ? plan.plannedDuration
        : maximum;
    if (candidate > maximumDuration) return maximumDuration;
    return candidate < const Duration(minutes: 10)
        ? const Duration(minutes: 10)
        : candidate;
  }

  static double? _altitudeMsl(ForecastPlanDocument plan, LocationSample fix) =>
      switch (fix.altitudeDatum) {
        AltitudeDatum.wgs84Geoid => fix.altitudeMeters,
        AltitudeDatum.relativeToLaunch =>
          plan.launchElevationMetersMsl + fix.altitudeMeters!,
        AltitudeDatum.wgs84Ellipsoid || AltitudeDatum.unknown => null,
      };

  static double _plannedAltitude(
    ForecastPlanDocument plan,
    double fraction, {
    required double startAltitudeMsl,
  }) {
    final stages = plan.altitudeStages;
    ForecastPlanStage below = stages.first;
    ForecastPlanStage above = stages.last;
    for (var index = 1; index < stages.length; index += 1) {
      if (fraction <= stages[index].fraction) {
        below = stages[index - 1];
        above = stages[index];
        break;
      }
    }
    final span = above.fraction - below.fraction;
    final local = span <= 0 ? 0.0 : (fraction - below.fraction) / span;
    final planned =
        below.altitudeMetersMsl +
        (above.altitudeMetersMsl - below.altitudeMetersMsl) * local;
    // Begin at the measured altitude without translating the landing altitude.
    // The correction fades out across the flight rather than drawing an
    // impossible vertical jump at the first forecast sample.
    return planned +
        (startAltitudeMsl - stages.first.altitudeMetersMsl) * (1 - fraction);
  }

  static double _candidateAltitude({
    required double fraction,
    required Duration duration,
    required double startAltitudeMsl,
    required double targetAltitudeMsl,
    required double landingAltitudeMsl,
    required double maximumAscentRate,
    required double maximumDescentRate,
  }) {
    final seconds = duration.inMilliseconds / 1000;
    final elapsed = seconds * fraction;
    final ascentSeconds = math.max(
      0,
      (targetAltitudeMsl - startAltitudeMsl) / maximumAscentRate,
    );
    final descentSeconds = math.max(
      0,
      (targetAltitudeMsl - landingAltitudeMsl) / maximumDescentRate,
    );
    if (elapsed < ascentSeconds) {
      return startAltitudeMsl + maximumAscentRate * elapsed;
    }
    final descentStarts = math.max(ascentSeconds, seconds - descentSeconds);
    if (elapsed <= descentStarts) return targetAltitudeMsl;
    return math.max(
      landingAltitudeMsl,
      targetAltitudeMsl - maximumDescentRate * (elapsed - descentStarts),
    );
  }

  List<route.GeoPoint>? _integrate({
    required live.GeoPoint start,
    required double startAltitudeMsl,
    required Duration duration,
    required WindForecastField wind,
    required double Function(double fraction) altitudeAt,
    required ForecastPlanConstraints constraints,
    required bool retainTrack,
    required DateTime startedAt,
    required AltitudeDatum datum,
  }) {
    final totalSeconds = duration.inMilliseconds / 1000;
    final stepSeconds = math.max(1.0, step.inMilliseconds / 1000);
    var position = start;
    var altitude = startAltitudeMsl;
    final output = <route.GeoPoint>[
      _routePoint(position, altitude, startedAt, datum),
    ];
    for (var elapsed = 0.0; elapsed < totalSeconds;) {
      final seconds = math.min(stepSeconds, totalSeconds - elapsed);
      final nextElapsed = elapsed + seconds;
      final desired = altitudeAt(
        nextElapsed / totalSeconds,
      ).clamp(-500.0, constraints.altitudeCeilingMetersMsl);
      final maximumRise =
          constraints.maximumAscentRateMetersPerSecond * seconds;
      final maximumFall =
          constraints.maximumDescentRateMetersPerSecond * seconds;
      altitude = desired > altitude
          ? math.min(desired, altitude + maximumRise)
          : math.max(desired, altitude - maximumFall);
      final vector = wind.at(position, altitude);
      if (vector == null) return null;
      position = _move(
        position,
        eastMeters: vector.eastMetersPerSecond * seconds,
        northMeters: vector.northMetersPerSecond * seconds,
      );
      elapsed = nextElapsed;
      if (retainTrack || elapsed >= totalSeconds) {
        output.add(
          _routePoint(
            position,
            altitude,
            startedAt.add(Duration(milliseconds: (elapsed * 1000).round())),
            datum,
          ),
        );
      }
    }
    return output;
  }

  static route.GeoPoint _routePoint(
    live.GeoPoint point,
    double altitudeMsl,
    DateTime recordedAt,
    AltitudeDatum sourceDatum,
  ) => route.GeoPoint(
    latitude: point.latitude,
    longitude: point.longitude,
    elevationMeters: altitudeMsl,
    altitudeSource: AltitudeSource.unknown,
    altitudeDatum: sourceDatum == AltitudeDatum.relativeToLaunch
        ? AltitudeDatum.wgs84Geoid
        : sourceDatum,
    recordedAt: recordedAt,
  );

  static live.GeoPoint _move(
    live.GeoPoint point, {
    required double eastMeters,
    required double northMeters,
  }) {
    final longitudeScale = math
        .cos(point.latitude * math.pi / 180)
        .abs()
        .clamp(0.01, 1.0);
    return live.GeoPoint(
      latitude: (point.latitude + northMeters / 111320).clamp(-90, 90),
      longitude: (point.longitude + eastMeters / (111320 * longitudeScale))
          .clamp(-180, 180),
    );
  }

  static List<route.GeoPoint> _convexHull(List<route.GeoPoint> points) {
    final unique =
        <String, route.GeoPoint>{
          for (final point in points)
            '${point.latitude.toStringAsFixed(7)}:'
                    '${point.longitude.toStringAsFixed(7)}':
                point,
        }.values.toList()..sort((first, second) {
          final byLongitude = first.longitude.compareTo(second.longitude);
          return byLongitude != 0
              ? byLongitude
              : first.latitude.compareTo(second.latitude);
        });
    if (unique.length < 3) return const [];

    double cross(route.GeoPoint a, route.GeoPoint b, route.GeoPoint c) =>
        (b.longitude - a.longitude) * (c.latitude - a.latitude) -
        (b.latitude - a.latitude) * (c.longitude - a.longitude);

    final lower = <route.GeoPoint>[];
    for (final point in unique) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <route.GeoPoint>[];
    for (final point in unique.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    final hull = [
      ...lower.take(lower.length - 1),
      ...upper.take(upper.length - 1),
    ];
    if (hull.length < 3) return const [];
    return List.unmodifiable([...hull, hull.first]);
  }
}
