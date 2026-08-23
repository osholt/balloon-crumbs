import '../domain/altitude.dart';
import '../domain/forecast_plan.dart';
import '../domain/imported_route.dart';

class ForecastPlanImporter {
  const ForecastPlanImporter();

  ImportedRoute import(
    ForecastPlanDocument plan, {
    required DateTime importedAt,
    required String sourceFileName,
  }) {
    GeoPoint point(
      double latitude,
      double longitude, {
      double? altitudeMetersMsl,
      DateTime? recordedAt,
    }) => GeoPoint(
      latitude: latitude,
      longitude: longitude,
      elevationMeters: altitudeMetersMsl,
      // Forecast is not a sensor source. The plan's wind provenance and
      // immutable purpose carry that distinction; altitude source remains
      // unknown rather than pretending it was measured.
      altitudeSource: AltitudeSource.unknown,
      altitudeDatum: altitudeMetersMsl == null
          ? AltitudeDatum.unknown
          : _datum(plan.launchAltitudeDatum),
      recordedAt: recordedAt,
    );

    final track = [
      for (final sample in plan.plannedTrack)
        point(
          sample.point.latitude,
          sample.point.longitude,
          altitudeMetersMsl: sample.altitudeMetersMsl,
          recordedAt: plan.departure.selectedAt.add(
            Duration(milliseconds: (sample.elapsedSeconds * 1000).round()),
          ),
        ),
    ];
    return ImportedRoute(
      id: plan.id,
      name: plan.name,
      description:
          'Original forecast from ${plan.source}. ${plan.wind.provider} '
          '${plan.wind.model}; forecast model only, not an aviation briefing.',
      purpose: ImportedRoutePurpose.balloonForecast,
      importedAt: importedAt,
      sourceFileName: sourceFileName,
      paths: [
        RoutePath(
          kind: RoutePathKind.track,
          name: 'Original forecast',
          points: List.unmodifiable(track),
        ),
      ],
      waypoints: [
        RouteWaypoint(
          point: point(
            plan.launch.latitude,
            plan.launch.longitude,
            altitudeMetersMsl: plan.launchElevationMetersMsl,
            recordedAt: plan.departure.selectedAt,
          ),
          name: 'Launch',
          symbol: 'Launch',
        ),
        RouteWaypoint(
          point: point(
            plan.forecastLanding.latitude,
            plan.forecastLanding.longitude,
          ),
          name: 'Forecast landing',
          symbol: 'Forecast landing',
        ),
        RouteWaypoint(
          point: point(
            plan.intendedLandingArea.center.latitude,
            plan.intendedLandingArea.center.longitude,
          ),
          name: 'Pilot intended landing area',
          description: 'Approximate area from the original planner forecast.',
          symbol: 'Landing area',
        ),
      ],
      plannedDuration: plan.plannedDuration,
      forecastPlan: plan,
    );
  }

  static AltitudeDatum _datum(String name) => switch (name) {
    'wgs84Geoid' => AltitudeDatum.wgs84Geoid,
    'wgs84Ellipsoid' => AltitudeDatum.wgs84Ellipsoid,
    'relativeToLaunch' => AltitudeDatum.relativeToLaunch,
    _ => AltitudeDatum.unknown,
  };
}
