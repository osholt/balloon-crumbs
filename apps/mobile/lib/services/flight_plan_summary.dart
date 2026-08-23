import '../domain/imported_route.dart';

enum FlightPlanStagePhase { launch, climb, level, descend, peak, landing }

class FlightPlanStage {
  const FlightPlanStage({
    required this.point,
    required this.phase,
    this.time,
    this.altitudeMetersMsl,
  });

  final GeoPoint point;
  final FlightPlanStagePhase phase;
  final DateTime? time;
  final double? altitudeMetersMsl;

  String get label => switch (phase) {
    FlightPlanStagePhase.launch => 'Launch',
    FlightPlanStagePhase.climb => 'Climb',
    FlightPlanStagePhase.level => 'Level flight',
    FlightPlanStagePhase.descend => 'Descent',
    FlightPlanStagePhase.peak => 'Maximum altitude',
    FlightPlanStagePhase.landing => 'Forecast landing',
  };
}

/// A compact, aviation-specific interpretation of a planner forecast.
///
/// Planner GPX files contain a timed, altitude-bearing line rather than road
/// manoeuvres. This model keeps that distinction explicit and gives the live
/// flight UI a bounded set of useful stages instead of hundreds of raw fixes.
class FlightPlanSummary {
  const FlightPlanSummary({
    required this.routeName,
    required this.stages,
    required this.startTime,
    required this.landingTime,
    required this.duration,
    required this.minimumAltitudeMetersMsl,
    required this.maximumAltitudeMetersMsl,
    required this.maximumAscentRateMetersPerSecond,
    required this.maximumDescentRateMetersPerSecond,
    required this.forecastLanding,
    required this.intendedLanding,
  });

  final String routeName;
  final List<FlightPlanStage> stages;
  final DateTime? startTime;
  final DateTime? landingTime;
  final Duration? duration;
  final double? minimumAltitudeMetersMsl;
  final double? maximumAltitudeMetersMsl;
  final double? maximumAscentRateMetersPerSecond;
  final double? maximumDescentRateMetersPerSecond;
  final GeoPoint? forecastLanding;
  final GeoPoint? intendedLanding;

  bool get hasTimedAltitudeProfile =>
      stages.any((stage) => stage.time != null) &&
      stages.any((stage) => stage.altitudeMetersMsl != null);

  static FlightPlanSummary? fromRoute(ImportedRoute? route) {
    if (route == null || !route.isBalloonForecast) return null;
    final points = [for (final path in route.paths) ...path.points];
    if (points.isEmpty) return null;

    final timed = points.where((point) => point.recordedAt != null).toList();
    final startTime = timed.isEmpty ? null : timed.first.recordedAt;
    final landingTime = timed.isEmpty ? null : timed.last.recordedAt;
    final timedDuration = startTime != null && landingTime != null
        ? landingTime.difference(startTime)
        : null;
    final duration = timedDuration != null && !timedDuration.isNegative
        ? timedDuration
        : route.plannedDuration;

    final altitudes = points
        .map((point) => point.elevationMeters)
        .whereType<double>()
        .toList(growable: false);
    final minimumAltitude = altitudes.isEmpty
        ? null
        : altitudes.reduce((first, second) => first < second ? first : second);
    final maximumAltitude = altitudes.isEmpty
        ? null
        : altitudes.reduce((first, second) => first > second ? first : second);

    double? maximumAscentRate;
    double? maximumDescentRate;
    for (var index = 1; index < points.length; index += 1) {
      final previous = points[index - 1];
      final current = points[index];
      final previousTime = previous.recordedAt;
      final currentTime = current.recordedAt;
      final previousAltitude = previous.elevationMeters;
      final currentAltitude = current.elevationMeters;
      if (previousTime == null ||
          currentTime == null ||
          previousAltitude == null ||
          currentAltitude == null) {
        continue;
      }
      final seconds =
          currentTime.difference(previousTime).inMilliseconds / 1000;
      if (seconds <= 0) continue;
      final rate = (currentAltitude - previousAltitude) / seconds;
      if (rate > 0 && (maximumAscentRate == null || rate > maximumAscentRate)) {
        maximumAscentRate = rate;
      }
      if (rate < 0) {
        final descent = -rate;
        if (maximumDescentRate == null || descent > maximumDescentRate) {
          maximumDescentRate = descent;
        }
      }
    }

    final stageIndices = _stageIndices(points);
    final maximumIndex = maximumAltitude == null
        ? null
        : points.indexWhere(
            (point) => point.elevationMeters == maximumAltitude,
          );
    final stages = <FlightPlanStage>[];
    for (final index in stageIndices) {
      final point = points[index];
      stages.add(
        FlightPlanStage(
          point: point,
          time: point.recordedAt,
          altitudeMetersMsl: point.elevationMeters,
          phase: _phaseAt(points, index, maximumIndex: maximumIndex),
        ),
      );
    }

    GeoPoint? waypointNamed(String text) {
      for (final waypoint in route.waypoints) {
        final searchable = [
          waypoint.name,
          waypoint.description,
          waypoint.symbol,
        ].whereType<String>().join(' ').toLowerCase();
        if (searchable.contains(text)) return waypoint.point;
      }
      return null;
    }

    return FlightPlanSummary(
      routeName: route.name,
      stages: List.unmodifiable(stages),
      startTime: startTime,
      landingTime: landingTime,
      duration: duration,
      minimumAltitudeMetersMsl: minimumAltitude,
      maximumAltitudeMetersMsl: maximumAltitude,
      maximumAscentRateMetersPerSecond: maximumAscentRate,
      maximumDescentRateMetersPerSecond: maximumDescentRate,
      forecastLanding: waypointNamed('forecast landing') ?? points.last,
      intendedLanding: waypointNamed('intended landing'),
    );
  }
}

List<int> _stageIndices(List<GeoPoint> points) {
  if (points.length <= 10) {
    return List.generate(points.length, (index) => index, growable: false);
  }

  final important = <int>{0, points.length - 1};
  double? maximumAltitude;
  int? maximumIndex;
  for (final (index, point) in points.indexed) {
    final altitude = point.elevationMeters;
    if (altitude != null &&
        (maximumAltitude == null || altitude > maximumAltitude)) {
      maximumAltitude = altitude;
      maximumIndex = index;
    }
    if (index == 0 || index == points.length - 1) continue;
    final before = _altitudeDirection(points[index - 1], point);
    final after = _altitudeDirection(point, points[index + 1]);
    if (before != after && before != 0 && after != 0) important.add(index);
  }
  if (maximumIndex != null) important.add(maximumIndex);

  for (var step = 1; step < 8; step += 1) {
    important.add(((points.length - 1) * step / 8).round());
  }

  final ordered = important.toList()..sort();
  if (ordered.length <= 10) return ordered;
  final retained = <int>{0, points.length - 1};
  if (maximumIndex != null) retained.add(maximumIndex);
  final interior = ordered
      .where((index) => !retained.contains(index))
      .toList(growable: false);
  final spaces = 10 - retained.length;
  for (var slot = 0; slot < spaces; slot += 1) {
    final position =
        ((slot + 1) * (interior.length + 1) / (spaces + 1)).round() - 1;
    retained.add(interior[position.clamp(0, interior.length - 1)]);
  }
  return retained.toList()..sort();
}

FlightPlanStagePhase _phaseAt(
  List<GeoPoint> points,
  int index, {
  required int? maximumIndex,
}) {
  if (index == 0) return FlightPlanStagePhase.launch;
  if (index == points.length - 1) return FlightPlanStagePhase.landing;
  if (index == maximumIndex) return FlightPlanStagePhase.peak;

  final direction = _altitudeDirection(points[index - 1], points[index + 1]);
  if (direction > 0) return FlightPlanStagePhase.climb;
  if (direction < 0) return FlightPlanStagePhase.descend;
  return FlightPlanStagePhase.level;
}

int _altitudeDirection(GeoPoint first, GeoPoint second) {
  final firstAltitude = first.elevationMeters;
  final secondAltitude = second.elevationMeters;
  if (firstAltitude == null || secondAltitude == null) return 0;
  final difference = secondAltitude - firstAltitude;
  if (difference.abs() < 2) return 0;
  return difference > 0 ? 1 : -1;
}
