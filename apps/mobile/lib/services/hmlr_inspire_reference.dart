import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/imported_route.dart';

class HmlrInspireReferenceConfiguration {
  const HmlrInspireReferenceConfiguration({
    this.enabled = false,
    this.endpoint = '',
  });

  factory HmlrInspireReferenceConfiguration.fromEnvironment() =>
      HmlrInspireReferenceConfiguration(
        enabled: const bool.fromEnvironment(
          'BALLOON_CRUMBS_HMLR_INSPIRE_ENABLED',
        ),
        endpoint: const String.fromEnvironment(
          'BALLOON_CRUMBS_HMLR_INSPIRE_URL',
          defaultValue:
              'https://balloon-crumbs.pages.dev/api/v1/reference/inspire',
        ),
      );

  final bool enabled;
  final String endpoint;

  bool get isConfigured {
    final uri = Uri.tryParse(endpoint);
    return enabled &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }
}

class HmlrInspireReferenceResult {
  const HmlrInspireReferenceResult({
    required this.geoJson,
    required this.polygons,
    required this.available,
    required this.source,
    required this.datasetDate,
    required this.coverage,
    required this.limitation,
    required this.attribution,
    required this.conditionsUrl,
    required this.truncated,
  });

  final Map<String, dynamic> geoJson;
  final List<List<GeoPoint>> polygons;
  final bool available;
  final String source;
  final DateTime? datasetDate;
  final String coverage;
  final String limitation;
  final List<String> attribution;
  final String conditionsUrl;
  final bool truncated;
}

class HmlrInspireReferenceException implements Exception {
  const HmlrInspireReferenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HmlrInspireReferenceProvider {
  HmlrInspireReferenceProvider({
    required this.configuration,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const maximumResponseBytes = 384 * 1024;
  static const maximumFeatures = 100;
  static const maximumPoints = 20_000;

  final HmlrInspireReferenceConfiguration configuration;
  final http.Client _client;
  final bool _ownsClient;

  Future<HmlrInspireReferenceResult> lookup(
    GeoPoint center, {
    int radiusMetres = 1500,
  }) async {
    if (!configuration.isConfigured) {
      throw const HmlrInspireReferenceException(
        'Indicative registered-property extents are not configured.',
      );
    }
    if (radiusMetres < 25 || radiusMetres > 2000) {
      throw const HmlrInspireReferenceException(
        'Reference lookup radius is outside the safe range.',
      );
    }
    final endpoint = Uri.parse(configuration.endpoint).replace(
      queryParameters: {
        'latitude': '${center.latitude}',
        'longitude': '${center.longitude}',
        'radiusMetres': '$radiusMetres',
      },
    );
    late http.Response response;
    try {
      response = await _client
          .get(endpoint, headers: const {'Accept': 'application/geo+json'})
          .timeout(const Duration(seconds: 6));
    } on Object {
      throw const HmlrInspireReferenceException(
        'Indicative registered-property extents are unavailable.',
      );
    }
    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty ||
        response.bodyBytes.length > maximumResponseBytes) {
      throw const HmlrInspireReferenceException(
        'Indicative registered-property extents are unavailable.',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['type'] != 'FeatureCollection' ||
          decoded['features'] is! List ||
          decoded['metadata'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid reference response.');
      }
      final sourceFeatures = decoded['features'] as List;
      if (sourceFeatures.length > maximumFeatures) {
        throw const FormatException('Too many reference features.');
      }
      final features = <Map<String, dynamic>>[];
      final polygons = <List<GeoPoint>>[];
      var pointCount = 0;
      for (final rawFeature in sourceFeatures) {
        if (rawFeature is! Map<String, dynamic> ||
            rawFeature['geometry'] is! Map<String, dynamic>) {
          throw const FormatException('Invalid reference feature.');
        }
        final id = rawFeature['id'];
        if (id is! String || id.isEmpty || id.length > 160) {
          throw const FormatException('Invalid reference identifier.');
        }
        final geometry = rawFeature['geometry'] as Map<String, dynamic>;
        final parsed = _parsePolygons(geometry);
        pointCount += parsed.fold(
          0,
          (total, polygon) => total + polygon.length,
        );
        if (pointCount > maximumPoints) {
          throw const FormatException('Reference geometry is too detailed.');
        }
        polygons.addAll(parsed);
        features.add({
          'type': 'Feature',
          'id': id,
          'properties': {'inspireId': id},
          'geometry': geometry,
        });
      }
      final metadata = decoded['metadata'] as Map<String, dynamic>;
      final available = metadata['available'] == true;
      final limitation = _boundedString(metadata['limitation'], 1000);
      if (limitation.isEmpty) {
        throw const FormatException('Reference limitation is required.');
      }
      final attribution = switch (metadata['attribution']) {
        final List values =>
          values
              .map((value) => _boundedString(value, 600))
              .where((value) => value.isNotEmpty)
              .take(2)
              .toList(growable: false),
        _ => const <String>[],
      };
      final datasetDate = DateTime.tryParse(
        _boundedString(metadata['datasetDate'], 32),
      );
      return HmlrInspireReferenceResult(
        geoJson: {'type': 'FeatureCollection', 'features': features},
        polygons: polygons,
        available: available,
        source: _boundedString(metadata['source'], 200),
        datasetDate: datasetDate,
        coverage: _boundedString(metadata['coverage'], 200),
        limitation: limitation,
        attribution: attribution,
        conditionsUrl: _boundedString(metadata['conditionsUrl'], 500),
        truncated: metadata['truncated'] == true,
      );
    } on Object {
      throw const HmlrInspireReferenceException(
        'Indicative registered-property extents could not be verified.',
      );
    }
  }

  static List<List<GeoPoint>> _parsePolygons(Map<String, dynamic> geometry) {
    final coordinates = geometry['coordinates'];
    return switch (geometry['type']) {
      'Polygon' => [_parseOuterRing(coordinates)],
      'MultiPolygon' when coordinates is List =>
        coordinates.map(_parseOuterRing).toList(growable: false),
      _ => throw const FormatException('Unsupported reference geometry.'),
    };
  }

  static List<GeoPoint> _parseOuterRing(Object? polygon) {
    if (polygon is! List || polygon.isEmpty || polygon.first is! List) {
      throw const FormatException('Invalid reference polygon.');
    }
    final ring = polygon.first as List;
    if (ring.length < 4) {
      throw const FormatException('Reference polygon is too short.');
    }
    return ring
        .map((rawPoint) {
          if (rawPoint is! List || rawPoint.length < 2) {
            throw const FormatException('Invalid reference coordinate.');
          }
          final longitude = rawPoint[0];
          final latitude = rawPoint[1];
          if (longitude is! num || latitude is! num) {
            throw const FormatException('Invalid reference coordinate.');
          }
          final point = GeoPoint(
            latitude: latitude.toDouble(),
            longitude: longitude.toDouble(),
          );
          if (point.latitude < 49.5 ||
              point.latitude > 56.2 ||
              point.longitude < -7 ||
              point.longitude > 2.2) {
            throw const FormatException(
              'Reference coordinate is out of bounds.',
            );
          }
          return point;
        })
        .toList(growable: false);
  }

  static String _boundedString(Object? value, int maximumLength) {
    if (value is! String) return '';
    final trimmed = value.trim();
    return trimmed.length <= maximumLength ? trimmed : '';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
