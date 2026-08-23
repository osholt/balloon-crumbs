import 'dart:convert';
import 'dart:io';

import 'package:balloon_crumbs/domain/forecast_plan.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/live_flight_projection.dart';
import 'package:balloon_crumbs/services/open_meteo_wind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ForecastPlanDocument plan() => ForecastPlanDocument.fromJson(
    Map<String, Object?>.from(
      jsonDecode(
            File('../../fixtures/forecast_plan_v1.json').readAsStringSync(),
          )
          as Map,
    ),
  );

  const vectors = [
    WindForecastVector(altitudeMetersMsl: 20, fromDegrees: 270, speedKmh: 18),
    WindForecastVector(altitudeMetersMsl: 300, fromDegrees: 180, speedKmh: 25),
    WindForecastVector(altitudeMetersMsl: 600, fromDegrees: 90, speedKmh: 32),
    WindForecastVector(altitudeMetersMsl: 1000, fromDegrees: 45, speedKmh: 40),
    WindForecastVector(altitudeMetersMsl: 2000, fromDegrees: 0, speedKmh: 45),
  ];

  test(
    'projects from fresh telemetry and forms a possible landing envelope',
    () {
      final now = DateTime.utc(2026, 8, 23, 7, 5);
      final result = const LiveFlightProjectionEngine().evaluate(
        plan: plan(),
        balloonFix: LocationSample(
          position: const GeoPoint(latitude: 51.5, longitude: -2.6),
          recordedAt: now.subtract(const Duration(seconds: 5)),
          accuracyMeters: 6,
          altitudeMeters: 100,
          altitudeSource: AltitudeSource.gnss,
          altitudeDatum: AltitudeDatum.relativeToLaunch,
        ),
        wind: WindForecastField(
          columns: const [
            WindForecastColumn(
              position: GeoPoint(latitude: 51.5, longitude: -2.6),
              vectors: vectors,
            ),
          ],
          validAt: now,
          fetchedAt: now.subtract(const Duration(minutes: 3)),
          origin: WindForecastOrigin.openMeteoUkmo,
          sourceLabel: OpenMeteoWindProvider.sourceLabel,
        ),
        now: now,
      );

      expect(result.status, LiveFlightProjectionStatus.available);
      expect(result.projection?.track.length, greaterThan(20));
      expect(result.projection?.track.first.elevationMeters, 192);
      expect(result.projection?.track.last.elevationMeters, closeTo(92, 0.01));
      expect(
        result.projection?.landingEnvelope.length,
        greaterThanOrEqualTo(4),
      );
      expect(
        result.projection?.landingEnvelope.first.latitude,
        result.projection?.landingEnvelope.last.latitude,
      );
      expect(result.projection?.windSource, contains('Open-Meteo'));
    },
  );

  test('forms a bounded live recovery envelope without an imported plan', () {
    final now = DateTime.utc(2026, 8, 23, 7, 5);
    final result = const LiveFlightProjectionEngine().evaluate(
      plan: null,
      balloonFix: LocationSample(
        position: const GeoPoint(latitude: 51.5, longitude: -2.6),
        recordedAt: now.subtract(const Duration(seconds: 5)),
        accuracyMeters: 6,
        altitudeMeters: 300,
        altitudeSource: AltitudeSource.gnss,
        altitudeDatum: AltitudeDatum.wgs84Geoid,
      ),
      wind: WindForecastField(
        columns: const [
          WindForecastColumn(
            position: GeoPoint(latitude: 51.5, longitude: -2.6),
            groundElevationMetersMsl: 92,
            vectors: vectors,
          ),
        ],
        validAt: now,
        fetchedAt: now.subtract(const Duration(minutes: 3)),
        origin: WindForecastOrigin.openMeteoUkmo,
        sourceLabel: OpenMeteoWindProvider.sourceLabel,
      ),
      now: now,
    );

    expect(result.status, LiveFlightProjectionStatus.available);
    expect(
      result.projection?.basis,
      LiveFlightProjectionBasis.liveRecoveryEstimate,
    );
    expect(result.projection?.track.first.elevationMeters, 300);
    expect(result.projection?.landingEnvelope.length, greaterThanOrEqualTo(4));
    expect(result.projection?.limitations, contains('20–120 minute'));
  });

  test('terrain-references Android ellipsoid movement from its first fix', () {
    final now = DateTime.utc(2026, 8, 23, 7, 5);
    const position = GeoPoint(latitude: 51.5, longitude: -2.6);
    final result = const LiveFlightProjectionEngine().evaluate(
      plan: null,
      balloonReferenceFix: LocationSample(
        position: position,
        recordedAt: now.subtract(const Duration(minutes: 5)),
        accuracyMeters: 6,
        altitudeMeters: 150,
        altitudeSource: AltitudeSource.gnss,
        altitudeDatum: AltitudeDatum.wgs84Ellipsoid,
      ),
      balloonFix: LocationSample(
        position: position,
        recordedAt: now,
        accuracyMeters: 6,
        altitudeMeters: 350,
        altitudeSource: AltitudeSource.gnss,
        altitudeDatum: AltitudeDatum.wgs84Ellipsoid,
      ),
      wind: WindForecastField(
        columns: const [
          WindForecastColumn(
            position: position,
            groundElevationMetersMsl: 92,
            vectors: vectors,
          ),
        ],
        validAt: now,
        fetchedAt: now,
        origin: WindForecastOrigin.openMeteoUkmo,
        sourceLabel: OpenMeteoWindProvider.sourceLabel,
      ),
      now: now,
    );

    expect(result.status, LiveFlightProjectionStatus.available);
    expect(result.projection?.track.first.elevationMeters, 292);
  });

  test('refuses stale fixes, stale wind and incompatible altitude data', () {
    final now = DateTime.utc(2026, 8, 23, 7, 5);
    final field = WindForecastField(
      columns: const [
        WindForecastColumn(
          position: GeoPoint(latitude: 51.5, longitude: -2.6),
          vectors: vectors,
        ),
      ],
      validAt: now,
      fetchedAt: now,
      origin: WindForecastOrigin.openMeteoUkmo,
      sourceLabel: OpenMeteoWindProvider.sourceLabel,
    );
    LocationSample fix({
      DateTime? recordedAt,
      AltitudeDatum datum = AltitudeDatum.wgs84Geoid,
    }) => LocationSample(
      position: const GeoPoint(latitude: 51.5, longitude: -2.6),
      recordedAt: recordedAt ?? now,
      accuracyMeters: 6,
      altitudeMeters: 180,
      altitudeSource: AltitudeSource.gnss,
      altitudeDatum: datum,
    );

    expect(
      const LiveFlightProjectionEngine()
          .evaluate(
            plan: plan(),
            balloonFix: fix(
              recordedAt: now.subtract(const Duration(minutes: 2)),
            ),
            wind: field,
            now: now,
          )
          .status,
      LiveFlightProjectionStatus.staleBalloonFix,
    );
    expect(
      const LiveFlightProjectionEngine()
          .evaluate(
            plan: plan(),
            balloonFix: fix(datum: AltitudeDatum.wgs84Ellipsoid),
            wind: field,
            now: now,
          )
          .status,
      LiveFlightProjectionStatus.noCompatibleAltitude,
    );
    expect(
      const LiveFlightProjectionEngine()
          .evaluate(
            plan: plan(),
            balloonFix: fix(),
            wind: WindForecastField(
              columns: field.columns,
              validAt: now,
              fetchedAt: now.subtract(const Duration(hours: 1)),
              origin: WindForecastOrigin.openMeteoUkmo,
              sourceLabel: field.sourceLabel,
            ),
            now: now,
          )
          .status,
      LiveFlightProjectionStatus.staleWind,
    );
  });

  test('stops extending the forecast envelope after LANDED', () {
    final result = const LiveFlightProjectionEngine().evaluate(
      plan: null,
      balloonFix: null,
      wind: null,
      now: DateTime.utc(2026, 8, 23, 8),
      flightLanded: true,
    );

    expect(result.status, LiveFlightProjectionStatus.landed);
    expect(result.projection, isNull);
    expect(result.message, contains('no longer extended'));
  });
}
