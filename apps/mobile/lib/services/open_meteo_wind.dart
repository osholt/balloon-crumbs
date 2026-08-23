import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/geo_point.dart';
import 'geo_calculations.dart';

/// Height levels exposed by Open-Meteo's UKMO UKV forecast that are useful to
/// a typical balloon flight. Values are metres above mean sea level (MSL).
const openMeteoWindAltitudeLevels = <int>[
  20,
  50,
  100,
  150,
  200,
  300,
  400,
  500,
  600,
  800,
  1000,
  1250,
  1500,
  2000,
];

enum WindForecastOrigin { openMeteoUkmo, bundledFallback }

class WindForecastVector {
  const WindForecastVector({
    required this.altitudeMetersMsl,
    required this.fromDegrees,
    required this.speedKmh,
  });

  final double altitudeMetersMsl;

  /// Meteorological direction: where the wind comes from.
  final double fromDegrees;
  final double speedKmh;

  double get towardDegrees => (fromDegrees + 180) % 360;
  double get speedMetersPerSecond => speedKmh / 3.6;

  double get eastMetersPerSecond {
    final radians = towardDegrees * math.pi / 180;
    return speedMetersPerSecond * math.sin(radians);
  }

  double get northMetersPerSecond {
    final radians = towardDegrees * math.pi / 180;
    return speedMetersPerSecond * math.cos(radians);
  }

  static WindForecastVector fromComponents({
    required double altitudeMetersMsl,
    required double eastMetersPerSecond,
    required double northMetersPerSecond,
  }) {
    final speed = math.sqrt(
      eastMetersPerSecond * eastMetersPerSecond +
          northMetersPerSecond * northMetersPerSecond,
    );
    final toward =
        (math.atan2(eastMetersPerSecond, northMetersPerSecond) * 180 / math.pi +
            360) %
        360;
    return WindForecastVector(
      altitudeMetersMsl: altitudeMetersMsl,
      fromDegrees: (toward + 180) % 360,
      speedKmh: speed * 3.6,
    );
  }
}

class WindForecastColumn {
  const WindForecastColumn({
    required this.position,
    required this.vectors,
    this.groundElevationMetersMsl,
  });

  final GeoPoint position;
  final List<WindForecastVector> vectors;
  final double? groundElevationMetersMsl;

  WindForecastVector? atAltitude(double altitudeMetersMsl) {
    if (vectors.isEmpty) return null;
    final ordered = [...vectors]
      ..sort(
        (first, second) =>
            first.altitudeMetersMsl.compareTo(second.altitudeMetersMsl),
      );
    if (altitudeMetersMsl <= ordered.first.altitudeMetersMsl) {
      return ordered.first;
    }
    if (altitudeMetersMsl >= ordered.last.altitudeMetersMsl) {
      return ordered.last;
    }
    for (var index = 0; index < ordered.length - 1; index += 1) {
      final below = ordered[index];
      final above = ordered[index + 1];
      if (altitudeMetersMsl > above.altitudeMetersMsl) continue;
      final span = above.altitudeMetersMsl - below.altitudeMetersMsl;
      final fraction = span <= 0
          ? 0.0
          : (altitudeMetersMsl - below.altitudeMetersMsl) / span;
      // Interpolate the vector, not the bearing. A 350°/10° pair averages to
      // north, while averaging the bearing numbers would point south.
      return WindForecastVector.fromComponents(
        altitudeMetersMsl: altitudeMetersMsl,
        eastMetersPerSecond:
            below.eastMetersPerSecond +
            (above.eastMetersPerSecond - below.eastMetersPerSecond) * fraction,
        northMetersPerSecond:
            below.northMetersPerSecond +
            (above.northMetersPerSecond - below.northMetersPerSecond) *
                fraction,
      );
    }
    return ordered.last;
  }
}

class WindForecastSample {
  const WindForecastSample({required this.position, required this.vector});

  final GeoPoint position;
  final WindForecastVector vector;
}

class WindForecastField {
  const WindForecastField({
    required this.columns,
    required this.validAt,
    required this.fetchedAt,
    required this.origin,
    required this.sourceLabel,
  });

  final List<WindForecastColumn> columns;
  final DateTime validAt;
  final DateTime fetchedAt;
  final WindForecastOrigin origin;
  final String sourceLabel;

  bool get isLiveForecast => origin == WindForecastOrigin.openMeteoUkmo;

  WindForecastVector? at(GeoPoint position, double altitudeMetersMsl) {
    if (columns.isEmpty) return null;
    final nearest = columns.reduce(
      (first, second) =>
          GeoCalculations.distanceMeters(position, first.position) <=
              GeoCalculations.distanceMeters(position, second.position)
          ? first
          : second,
    );
    return nearest.atAltitude(altitudeMetersMsl);
  }

  double? groundElevationAt(GeoPoint position) {
    final available = columns
        .where((column) => column.groundElevationMetersMsl != null)
        .toList(growable: false);
    if (available.isEmpty) return null;
    return available
        .reduce(
          (first, second) =>
              GeoCalculations.distanceMeters(position, first.position) <=
                  GeoCalculations.distanceMeters(position, second.position)
              ? first
              : second,
        )
        .groundElevationMetersMsl;
  }

  List<WindForecastSample> vectorsAt(double altitudeMetersMsl) =>
      List.unmodifiable([
        for (final column in columns)
          if (column.atAltitude(altitudeMetersMsl) case final vector?)
            WindForecastSample(position: column.position, vector: vector),
      ]);
}

abstract interface class WindForecastProvider {
  Future<WindForecastField> fetch({
    required GeoPoint center,
    required DateTime at,
  });
}

/// Latest UK Met Office UKV wind forecast, delivered by Open-Meteo.
///
/// This is forecast model output, not an airborne observation and not an
/// aviation weather briefing. The request asks for the same 5×5, approximately
/// 120 km field as the planner and a short time window; slider changes reuse
/// the vertical profile and never create another network request.
class OpenMeteoWindProvider implements WindForecastProvider {
  OpenMeteoWindProvider({
    required this.client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 10),
    this.maximumResponseBytes = 2 * 1024 * 1024,
  }) : endpoint = endpoint ?? Uri.https('api.open-meteo.com', '/v1/forecast');

  static const sourceLabel = 'UKMO UKV forecast via Open-Meteo';
  static const attribution = 'Weather data by Open-Meteo.com';
  static final attributionUri = Uri.parse('https://open-meteo.com/');

  final http.Client client;
  final Uri endpoint;
  final Duration timeout;
  final int maximumResponseBytes;

  @override
  Future<WindForecastField> fetch({
    required GeoPoint center,
    required DateTime at,
  }) async {
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty) {
      throw const FormatException('Open-Meteo wind endpoint must use HTTPS.');
    }
    final requestedPoints = windForecastGrid(center);
    final variables = <String>[
      for (final altitude in openMeteoWindAltitudeLevels) ...[
        'wind_speed_${altitude}m',
        'wind_direction_${altitude}m',
      ],
    ];
    final uri = endpoint.replace(
      queryParameters: {
        'latitude': requestedPoints
            .map((point) => point.latitude.toStringAsFixed(6))
            .join(','),
        'longitude': requestedPoints
            .map((point) => point.longitude.toStringAsFixed(6))
            .join(','),
        'models': 'ukmo_seamless',
        'hourly': variables.join(','),
        'wind_speed_unit': 'kmh',
        'timezone': 'GMT',
        'past_hours': '1',
        'forecast_hours': '3',
      },
    );
    final response = await client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'Open-Meteo wind request failed (${response.statusCode}).',
      );
    }
    if (response.bodyBytes.length > maximumResponseBytes) {
      throw const FormatException('Open-Meteo wind response is too large.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final entries = decoded is List ? decoded : [decoded];
    final columns = <WindForecastColumn>[];
    DateTime? commonValidAt;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final latitude = (entry['latitude'] as num?)?.toDouble();
      final longitude = (entry['longitude'] as num?)?.toDouble();
      final groundElevation = (entry['elevation'] as num?)?.toDouble();
      final hourly = entry['hourly'];
      if (latitude == null || longitude == null || hourly is! Map) continue;
      final times = hourly['time'];
      if (times is! List || times.isEmpty) continue;
      final parsedTimes = <DateTime>[];
      for (final value in times) {
        final parsed = DateTime.tryParse('${value}Z')?.toUtc();
        if (parsed != null) parsedTimes.add(parsed);
      }
      if (parsedTimes.length != times.length) continue;
      final target = at.toUtc();
      var timeIndex = 0;
      for (var index = 1; index < parsedTimes.length; index += 1) {
        if ((parsedTimes[index].difference(target)).abs() <
            (parsedTimes[timeIndex].difference(target)).abs()) {
          timeIndex = index;
        }
      }
      final validAt = parsedTimes[timeIndex];
      commonValidAt ??= validAt;
      final vectors = <WindForecastVector>[];
      for (final altitude in openMeteoWindAltitudeLevels) {
        final speeds = hourly['wind_speed_${altitude}m'];
        final directions = hourly['wind_direction_${altitude}m'];
        if (speeds is! List || directions is! List) continue;
        if (timeIndex >= speeds.length || timeIndex >= directions.length) {
          continue;
        }
        final speed = (speeds[timeIndex] as num?)?.toDouble();
        final direction = (directions[timeIndex] as num?)?.toDouble();
        if (speed == null || direction == null) continue;
        if (!speed.isFinite || !direction.isFinite || speed < 0) continue;
        vectors.add(
          WindForecastVector(
            altitudeMetersMsl: altitude.toDouble(),
            fromDegrees: direction % 360,
            speedKmh: speed,
          ),
        );
      }
      if (vectors.isNotEmpty) {
        columns.add(
          WindForecastColumn(
            position: GeoPoint(latitude: latitude, longitude: longitude),
            vectors: List.unmodifiable(vectors),
            groundElevationMetersMsl: groundElevation?.isFinite == true
                ? groundElevation
                : null,
          ),
        );
      }
    }
    if (columns.isEmpty || commonValidAt == null) {
      throw const FormatException('Open-Meteo returned no usable wind data.');
    }
    return WindForecastField(
      columns: List.unmodifiable(columns),
      validAt: commonValidAt,
      fetchedAt: DateTime.now().toUtc(),
      origin: WindForecastOrigin.openMeteoUkmo,
      sourceLabel: sourceLabel,
    );
  }
}

/// Twenty-five sample points covering roughly 120 × 120 km around [center].
List<GeoPoint> windForecastGrid(GeoPoint center) => List.unmodifiable([
  for (final latitudeOffset in const [-0.54, -0.27, 0.0, 0.27, 0.54])
    for (final longitudeOffset in const [-0.85, -0.425, 0.0, 0.425, 0.85])
      GeoPoint(
        latitude: (center.latitude + latitudeOffset).clamp(-90, 90),
        longitude: (center.longitude + longitudeOffset).clamp(-180, 180),
      ),
]);

class WindForecastController extends ChangeNotifier {
  WindForecastController(
    this._provider, {
    DateTime Function()? clock,
    WindForecastField? initialField,
    bool enabled = true,
    int selectedAltitudeMetersMsl = 500,
    bool followBalloonAltitude = true,
    this.recenterDistanceMeters = 25000,
  }) : _clock = clock ?? DateTime.now,
       _field = initialField,
       _selectedAltitudeMetersMsl = _nearestLevel(
         selectedAltitudeMetersMsl.toDouble(),
       ) {
    _enabled = enabled;
    _followBalloonAltitude = followBalloonAltitude;
  }

  final WindForecastProvider _provider;
  final DateTime Function() _clock;
  final double recenterDistanceMeters;
  WindForecastField? _field;
  bool _enabled = true;
  bool _followBalloonAltitude = true;
  int _selectedAltitudeMetersMsl;
  bool _loading = false;
  String? _error;
  GeoPoint? _lastCenter;
  DateTime? _lastAttemptAt;
  int _generation = 0;

  WindForecastField? get field => _field;
  bool get enabled => _enabled;
  bool get followBalloonAltitude => _followBalloonAltitude;
  bool get loading => _loading;
  String? get error => _error;
  int get selectedAltitudeMetersMsl => _selectedAltitudeMetersMsl;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  void setSelectedAltitude(double value) {
    _followBalloonAltitude = false;
    final next = _nearestLevel(value);
    if (next == _selectedAltitudeMetersMsl) {
      notifyListeners();
      return;
    }
    _selectedAltitudeMetersMsl = next;
    notifyListeners();
  }

  void setFollowBalloonAltitude(bool value) {
    if (_followBalloonAltitude == value) return;
    _followBalloonAltitude = value;
    notifyListeners();
  }

  void updateBalloonAltitude(double? altitudeMetersMsl) {
    if (!_followBalloonAltitude || altitudeMetersMsl == null) return;
    final next = _nearestLevel(altitudeMetersMsl);
    if (next == _selectedAltitudeMetersMsl) return;
    _selectedAltitudeMetersMsl = next;
    notifyListeners();
  }

  Future<void> refresh(GeoPoint center, {bool force = false}) async {
    final now = _clock().toUtc();
    final lastAttempt = _lastAttemptAt;
    if (!force &&
        (_loading ||
            (lastAttempt != null &&
                now.difference(lastAttempt).abs() <
                    const Duration(minutes: 10)))) {
      return;
    }
    final lastCenter = _lastCenter;
    final field = _field;
    final fresh =
        field != null &&
        now.difference(field.fetchedAt).abs() < const Duration(minutes: 30);
    final nearby =
        lastCenter != null &&
        GeoCalculations.distanceMeters(lastCenter, center) <
            recenterDistanceMeters;
    if (!force && fresh && nearby && field.isLiveForecast) return;
    final generation = ++_generation;
    _lastAttemptAt = now;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _provider.fetch(center: center, at: _clock());
      if (generation != _generation) return;
      _field = result;
      _lastCenter = center;
    } on Object catch (error) {
      if (generation != _generation) return;
      _error = '$error';
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  static int _nearestLevel(double value) => openMeteoWindAltitudeLevels.reduce(
    (first, second) =>
        (first - value).abs() <= (second - value).abs() ? first : second,
  );
}
