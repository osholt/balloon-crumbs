import 'dart:convert';
import 'dart:io';

import 'package:balloon_crumbs/domain/forecast_plan.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/services/forecast_plan_importer.dart';
import 'package:balloon_crumbs/services/flight_plan_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'summarises planner timing, altitude phases, rates and landing points',
    () {
      final start = DateTime.utc(2026, 8, 23, 6);
      final route = ImportedRoute(
        id: 'forecast',
        name: 'Tuckers Grave forecast',
        importedAt: start,
        sourceFileName: 'forecast.gpx',
        purpose: ImportedRoutePurpose.balloonForecast,
        paths: [
          RoutePath(
            kind: RoutePathKind.track,
            points: [
              GeoPoint(
                latitude: 51.2,
                longitude: -2.4,
                elevationMeters: 120,
                recordedAt: start,
              ),
              GeoPoint(
                latitude: 51.21,
                longitude: -2.39,
                elevationMeters: 300,
                recordedAt: start.add(const Duration(minutes: 2)),
              ),
              GeoPoint(
                latitude: 51.22,
                longitude: -2.38,
                elevationMeters: 600,
                recordedAt: start.add(const Duration(minutes: 5)),
              ),
              GeoPoint(
                latitude: 51.23,
                longitude: -2.37,
                elevationMeters: 300,
                recordedAt: start.add(const Duration(minutes: 10)),
              ),
              GeoPoint(
                latitude: 51.24,
                longitude: -2.36,
                elevationMeters: 130,
                recordedAt: start.add(const Duration(minutes: 12)),
              ),
            ],
          ),
        ],
        waypoints: const [
          RouteWaypoint(
            point: GeoPoint(latitude: 51.25, longitude: -2.35),
            name: 'Pilot intended landing area',
          ),
        ],
      );

      final summary = FlightPlanSummary.fromRoute(route)!;

      expect(summary.startTime, start);
      expect(summary.landingTime, start.add(const Duration(minutes: 12)));
      expect(summary.duration, const Duration(minutes: 12));
      expect(summary.minimumAltitudeMetersMsl, 120);
      expect(summary.maximumAltitudeMetersMsl, 600);
      expect(summary.maximumAscentRateMetersPerSecond, closeTo(1.67, 0.01));
      expect(summary.maximumDescentRateMetersPerSecond, closeTo(1.42, 0.01));
      expect(summary.stages.first.phase, FlightPlanStagePhase.launch);
      expect(summary.stages[2].phase, FlightPlanStagePhase.peak);
      expect(summary.stages.last.phase, FlightPlanStagePhase.landing);
      expect(summary.forecastLanding!.latitude, 51.24);
      expect(summary.intendedLanding!.latitude, 51.25);
    },
  );

  test('uses planned duration for an untimed forecast', () {
    final route = ImportedRoute(
      id: 'untimed',
      name: 'Untimed forecast',
      importedAt: DateTime.utc(2026, 8, 23),
      sourceFileName: 'forecast.gpx',
      purpose: ImportedRoutePurpose.balloonForecast,
      paths: const [
        RoutePath(
          kind: RoutePathKind.track,
          points: [
            GeoPoint(latitude: 51, longitude: -2),
            GeoPoint(latitude: 51.1, longitude: -1.9),
          ],
        ),
      ],
      waypoints: const [],
      plannedDuration: Duration(hours: 1),
    );

    final summary = FlightPlanSummary.fromRoute(route)!;

    expect(summary.duration, const Duration(hours: 1));
    expect(summary.startTime, isNull);
    expect(summary.hasTimedAltitudeProfile, isFalse);
  });

  test('prefers exact structured stages, limits and source evidence', () {
    final plan = ForecastPlanDocument.fromJson(
      Map<String, Object?>.from(
        jsonDecode(
              File('../../fixtures/forecast_plan_v1.json').readAsStringSync(),
            )
            as Map,
      ),
    );
    final route = const ForecastPlanImporter().import(
      plan,
      importedAt: DateTime.utc(2026, 8, 23, 6),
      sourceFileName: 'fixture.forecast-plan',
    );

    final summary = FlightPlanSummary.fromRoute(route)!;

    expect(summary.stages, hasLength(6));
    expect(summary.stages[2].altitudeMetersMsl, 600);
    expect(summary.maximumAscentRateMetersPerSecond, 3);
    expect(summary.maximumDescentRateMetersPerSecond, 4);
    expect(summary.altitudeCeilingMetersMsl, 1200);
    expect(summary.matchingWindowStart, DateTime.utc(2026, 8, 23, 6, 24));
    expect(summary.windProvider, 'Open-Meteo');
    expect(summary.landingEnvelope, hasLength(4));
  });

  test('does not interpret a road route as a flight plan', () {
    final route = ImportedRoute(
      id: 'road',
      name: 'Road route',
      importedAt: DateTime.utc(2026, 8, 23),
      sourceFileName: 'road.gpx',
      paths: const [
        RoutePath(
          kind: RoutePathKind.route,
          points: [GeoPoint(latitude: 51, longitude: -2)],
        ),
      ],
      waypoints: const [],
    );

    expect(FlightPlanSummary.fromRoute(route), isNull);
  });
}
