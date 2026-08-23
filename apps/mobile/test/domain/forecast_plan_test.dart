import 'dart:convert';
import 'dart:io';

import 'package:balloon_crumbs/domain/forecast_plan.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/services/forecast_plan_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> fixture() => Map<String, Object?>.from(
    jsonDecode(File('../../fixtures/forecast_plan_v1.json').readAsStringSync())
        as Map,
  );

  test('parses every bounded version-one forecast field', () {
    final json = fixture()..['futureAdditiveField'] = 'ignored';
    final plan = ForecastPlanDocument.fromJson(json);

    expect(plan.name, 'Tuckers Grave forecast');
    expect(plan.altitudeStages, hasLength(6));
    expect(plan.constraints.altitudeCeilingMetersMsl, 1200);
    expect(plan.constraints.maximumDescentRateMetersPerSecond, 4);
    expect(plan.landingEnvelope, hasLength(4));
    expect(plan.wind.model, 'UKMO seamless');
    expect(plan.operationalBoundaries, hasLength(1));
    expect(plan.result.missDistanceMeters, 42);
    expect(plan.toJson(), isNot(contains('futureAdditiveField')));
  });

  test('imports and persists structured evidence beside forecast geometry', () {
    final plan = ForecastPlanDocument.fromJson(fixture());
    final route = const ForecastPlanImporter().import(
      plan,
      importedAt: DateTime.utc(2026, 8, 23, 6),
      sourceFileName: 'fixture.forecast-plan',
    );
    final restored = ImportedRoute.fromJsonString(route.toJsonString());

    expect(restored.isBalloonForecast, isTrue);
    expect(restored.pathPointCount, 3);
    expect(restored.paths.single.points[1].elevationMeters, 700);
    expect(
      restored.paths.single.points.last.recordedAt,
      DateTime.utc(2026, 8, 23, 7, 30),
    );
    expect(restored.forecastPlan?.altitudeStages, hasLength(6));
    expect(restored.forecastPlan?.gpxFallback, plan.gpxFallback);
  });

  test('unknown schema and unordered geometry reject the complete plan', () {
    expect(
      () => ForecastPlanDocument.fromJson(fixture()..['schemaVersion'] = 2),
      throwsFormatException,
    );

    final unordered = fixture();
    final track = List<Map<String, Object?>>.from(
      unordered['plannedTrack']! as List,
    );
    track[2] = {...track[2], 'elapsedSeconds': 100};
    unordered['plannedTrack'] = track;
    expect(
      () => ForecastPlanDocument.fromJson(unordered),
      throwsFormatException,
    );
  });
}
