import 'dart:convert';

import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/services/hmlr_inspire_reference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const configuration = HmlrInspireReferenceConfiguration(
    enabled: true,
    endpoint: 'https://balloon-crumbs.pages.dev/api/v1/reference/inspire',
  );

  test('requires an explicitly enabled secure endpoint', () {
    expect(
      const HmlrInspireReferenceConfiguration(
        endpoint: 'https://example.test/api/v1/reference/inspire',
      ).isConfigured,
      isFalse,
    );
    expect(configuration.isConfigured, isTrue);
    expect(
      const HmlrInspireReferenceConfiguration(
        enabled: true,
        endpoint: 'http://example.test/api/v1/reference/inspire',
      ).isConfigured,
      isFalse,
    );
  });

  test(
    'accepts bounded geometry and strips unexpected public properties',
    () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'id': 'inspire-1',
                'properties': {
                  'inspireId': 'inspire-1',
                  'ownerName': 'must not survive validation',
                },
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [
                      [-2.59, 51.45],
                      [-2.58, 51.45],
                      [-2.58, 51.46],
                      [-2.59, 51.45],
                    ],
                  ],
                },
              },
            ],
            'metadata': {
              'available': true,
              'source': 'HM Land Registry INSPIRE Index Polygons',
              'datasetDate': '2026-08-02',
              'coverage': 'England and Wales',
              'limitation': 'Indicative registered freehold extent only.',
              'attribution': ['HMLR attribution', 'OS attribution'],
              'conditionsUrl':
                  'https://use-land-property-data.service.gov.uk/datasets/inspire/#conditions',
              'truncated': false,
            },
          }),
          200,
          headers: {'content-type': 'application/geo+json'},
        );
      });
      addTearDown(client.close);
      final provider = HmlrInspireReferenceProvider(
        configuration: configuration,
        client: client,
      );

      final result = await provider.lookup(
        const GeoPoint(latitude: 51.4545, longitude: -2.5879),
        radiusMetres: 500,
      );

      expect(requested.queryParameters['radiusMetres'], '500');
      expect(result.available, isTrue);
      expect(result.polygons, hasLength(1));
      expect(result.datasetDate, DateTime(2026, 8, 2));
      expect(jsonEncode(result.geoJson), isNot(contains('ownerName')));
      expect(result.geoJson['features'], [
        {
          'type': 'Feature',
          'id': 'inspire-1',
          'properties': {'inspireId': 'inspire-1'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [-2.59, 51.45],
                [-2.58, 51.45],
                [-2.58, 51.46],
                [-2.59, 51.45],
              ],
            ],
          },
        },
      ]);
    },
  );

  test('preserves an honest outside-coverage result', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [],
          'metadata': {
            'available': false,
            'coverage': 'England and Wales only',
            'limitation':
                'No Scotland or Northern Ireland coverage; absence does not mean unregistered.',
          },
        }),
        200,
      ),
    );
    addTearDown(client.close);

    final result = await HmlrInspireReferenceProvider(
      configuration: configuration,
      client: client,
    ).lookup(const GeoPoint(latitude: 55.95, longitude: -3.19));

    expect(result.available, isFalse);
    expect(result.polygons, isEmpty);
    expect(result.limitation, contains('does not mean unregistered'));
  });

  test('rejects oversized or unverifiable responses', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);

    expect(
      HmlrInspireReferenceProvider(
        configuration: configuration,
        client: client,
      ).lookup(const GeoPoint(latitude: 51.45, longitude: -2.58)),
      throwsA(isA<HmlrInspireReferenceException>()),
    );
  });
}
