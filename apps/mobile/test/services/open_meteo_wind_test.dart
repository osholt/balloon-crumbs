import 'dart:convert';

import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/services/open_meteo_wind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads a UKMO wind column grid from Open-Meteo', () async {
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      final entries = [
        for (var index = 0; index < 25; index += 1)
          {
            'latitude': 51.4 + index * 0.001,
            'longitude': -2.7 + index * 0.001,
            'elevation': 92 + index,
            'hourly': {
              'time': [
                '2026-08-21T09:00',
                '2026-08-21T10:00',
                '2026-08-21T11:00',
              ],
              'wind_speed_20m': [12, 18, 24],
              'wind_direction_20m': [260, 270, 280],
              'wind_speed_500m': [24, 36, 48],
              'wind_direction_500m': [170, 180, 190],
            },
          },
      ];
      return http.Response(jsonEncode(entries), 200);
    });
    addTearDown(client.close);

    final field = await OpenMeteoWindProvider(client: client).fetch(
      center: const GeoPoint(latitude: 51.44, longitude: -2.65),
      at: DateTime.utc(2026, 8, 21, 10, 10),
    );

    expect(requestedUri?.scheme, 'https');
    expect(requestedUri?.queryParameters['models'], 'ukmo_seamless');
    expect(
      requestedUri?.queryParameters['hourly'],
      allOf(contains('wind_speed_20m'), contains('wind_direction_2000m')),
    );
    expect(field.columns, hasLength(25));
    expect(
      requestedUri?.queryParameters['latitude']?.split(','),
      hasLength(25),
    );
    expect(
      requestedUri?.queryParameters['longitude']?.split(','),
      hasLength(25),
    );
    expect(field.validAt, DateTime.utc(2026, 8, 21, 10));
    expect(field.origin, WindForecastOrigin.openMeteoUkmo);
    expect(
      field.groundElevationAt(
        const GeoPoint(latitude: 51.404, longitude: -2.696),
      ),
      96,
    );
    final vector = field.at(
      const GeoPoint(latitude: 51.404, longitude: -2.696),
      500,
    );
    expect(vector?.speedKmh, 36);
    expect(vector?.fromDegrees, 180);
  });

  test('interpolates wind components across north without bearing wrap', () {
    const column = WindForecastColumn(
      position: GeoPoint(latitude: 51, longitude: -2),
      vectors: [
        WindForecastVector(
          altitudeMetersMsl: 100,
          fromDegrees: 350,
          speedKmh: 20,
        ),
        WindForecastVector(
          altitudeMetersMsl: 200,
          fromDegrees: 10,
          speedKmh: 20,
        ),
      ],
    );

    final middle = column.atAltitude(150)!;
    expect(middle.fromDegrees, anyOf(closeTo(0, 0.01), closeTo(360, 0.01)));
    expect(middle.speedKmh, closeTo(19.7, 0.1));
  });

  test('controller toggles display and reuses one vertical forecast', () async {
    final provider = _RecordingProvider();
    final controller = WindForecastController(
      provider,
      clock: () => DateTime.utc(2026, 8, 21, 10),
    );
    addTearDown(controller.dispose);

    await controller.refresh(const GeoPoint(latitude: 51.44, longitude: -2.65));
    controller.setSelectedAltitude(1240);
    controller.setEnabled(false);
    await controller.refresh(
      const GeoPoint(latitude: 51.441, longitude: -2.651),
    );

    expect(provider.fetchCount, 1);
    expect(controller.selectedAltitudeMetersMsl, 1250);
    expect(controller.followBalloonAltitude, isFalse);
    expect(controller.enabled, isFalse);
    expect(controller.field, isNotNull);
  });

  test('follows balloon altitude until a layer is selected manually', () {
    final controller = WindForecastController(_RecordingProvider());
    addTearDown(controller.dispose);

    controller.updateBalloonAltitude(780);
    expect(controller.selectedAltitudeMetersMsl, 800);
    expect(controller.followBalloonAltitude, isTrue);

    controller.setSelectedAltitude(300);
    controller.updateBalloonAltitude(1250);
    expect(controller.selectedAltitudeMetersMsl, 300);

    controller.setFollowBalloonAltitude(true);
    controller.updateBalloonAltitude(1250);
    expect(controller.selectedAltitudeMetersMsl, 1250);
  });
}

class _RecordingProvider implements WindForecastProvider {
  int fetchCount = 0;

  @override
  Future<WindForecastField> fetch({
    required GeoPoint center,
    required DateTime at,
  }) async {
    fetchCount += 1;
    return WindForecastField(
      columns: [
        WindForecastColumn(
          position: center,
          vectors: const [
            WindForecastVector(
              altitudeMetersMsl: 20,
              fromDegrees: 270,
              speedKmh: 15,
            ),
          ],
        ),
      ],
      validAt: at,
      fetchedAt: at,
      origin: WindForecastOrigin.openMeteoUkmo,
      sourceLabel: OpenMeteoWindProvider.sourceLabel,
    );
  }
}
