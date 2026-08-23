import 'dart:convert';

import 'geo_point.dart';
import 'operational_boundary.dart';

class ForecastPlanConstraints {
  const ForecastPlanConstraints({
    required this.altitudeCeilingMetersMsl,
    required this.maximumAscentRateMetersPerSecond,
    required this.maximumDescentRateMetersPerSecond,
    required this.minimumDurationMinutes,
    required this.maximumDurationMinutes,
  });

  final double altitudeCeilingMetersMsl;
  final double maximumAscentRateMetersPerSecond;
  final double maximumDescentRateMetersPerSecond;
  final double minimumDurationMinutes;
  final double maximumDurationMinutes;

  Map<String, Object?> toJson() => {
    'altitudeCeilingMsl': altitudeCeilingMetersMsl,
    'maximumAscentRateMps': maximumAscentRateMetersPerSecond,
    'maximumDescentRateMps': maximumDescentRateMetersPerSecond,
    'minimumDurationMinutes': minimumDurationMinutes,
    'maximumDurationMinutes': maximumDurationMinutes,
  };
}

class ForecastPlanStage {
  const ForecastPlanStage({
    required this.fraction,
    required this.plannedAt,
    required this.altitudeMetersMsl,
    required this.changeRateMetersPerSecond,
  });

  final double fraction;
  final DateTime plannedAt;
  final double altitudeMetersMsl;
  final double changeRateMetersPerSecond;

  Map<String, Object?> toJson() => {
    'fraction': fraction,
    'plannedAt': plannedAt.toUtc().toIso8601String(),
    'altitudeMsl': altitudeMetersMsl,
    'changeRateMps': changeRateMetersPerSecond,
  };
}

class ForecastPlanTrackPoint {
  const ForecastPlanTrackPoint({
    required this.point,
    required this.altitudeMetersMsl,
    required this.elapsedSeconds,
  });

  final GeoPoint point;
  final double altitudeMetersMsl;
  final double elapsedSeconds;

  Map<String, Object?> toJson() => {
    ...point.toJson(),
    'altitudeMsl': altitudeMetersMsl,
    'elapsedSeconds': elapsedSeconds,
  };
}

class ForecastPlanDeparture {
  const ForecastPlanDeparture({
    required this.selectedAt,
    this.matchingWindowStart,
    this.matchingWindowEnd,
  });

  final DateTime selectedAt;
  final DateTime? matchingWindowStart;
  final DateTime? matchingWindowEnd;

  Map<String, Object?> toJson() => {
    'selectedAt': selectedAt.toUtc().toIso8601String(),
    if (matchingWindowStart != null)
      'matchingWindowStart': matchingWindowStart!.toUtc().toIso8601String(),
    if (matchingWindowEnd != null)
      'matchingWindowEnd': matchingWindowEnd!.toUtc().toIso8601String(),
  };
}

class ForecastPlanLandingArea {
  const ForecastPlanLandingArea({
    required this.center,
    required this.updatedAt,
    this.radiusMeters,
    this.polygon = const [],
  });

  final GeoPoint center;
  final double? radiusMeters;
  final List<GeoPoint> polygon;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'centre': center.toJson(),
    if (radiusMeters != null) 'radiusMetres': radiusMeters,
    if (polygon.isNotEmpty)
      'polygon': polygon.map((point) => point.toJson()).toList(growable: false),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class ForecastPlanDestination {
  const ForecastPlanDestination({
    required this.point,
    required this.toleranceMeters,
  });

  final GeoPoint point;
  final double toleranceMeters;

  Map<String, Object?> toJson() => {
    'point': point.toJson(),
    'toleranceMetres': toleranceMeters,
  };
}

class ForecastPlanWind {
  const ForecastPlanWind({
    required this.provider,
    required this.model,
    required this.requestedAt,
    required this.validFrom,
    required this.validTo,
    required this.attribution,
    required this.licence,
    required this.fieldDigest,
  });

  final String provider;
  final String model;
  final DateTime requestedAt;
  final DateTime validFrom;
  final DateTime validTo;
  final String attribution;
  final String licence;
  final String fieldDigest;

  Map<String, Object?> toJson() => {
    'provider': provider,
    'model': model,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    'validFrom': validFrom.toUtc().toIso8601String(),
    'validTo': validTo.toUtc().toIso8601String(),
    'attribution': attribution,
    'licence': licence,
    'forecastOnly': true,
    'fieldDigest': fieldDigest,
  };
}

class ForecastPlanResult {
  const ForecastPlanResult({
    required this.kind,
    this.reachesDestination,
    this.missDistanceMeters,
  });

  final String kind;
  final bool? reachesDestination;
  final double? missDistanceMeters;

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (reachesDestination != null) 'reachesDestination': reachesDestination,
    if (missDistanceMeters != null) 'missDistanceMetres': missDistanceMeters,
  };
}

/// Versioned, bounded planner evidence retained beside its GPX fallback.
///
/// Unknown additive fields are discarded while decoding. An unknown schema
/// version rejects the complete document so partial geometry can never become
/// an active flight forecast.
class ForecastPlanDocument {
  const ForecastPlanDocument._({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.source,
    required this.launch,
    required this.launchElevationMetersMsl,
    required this.launchAltitudeDatum,
    required this.intendedLandingArea,
    required this.forecastLanding,
    required this.departure,
    required this.constraints,
    required this.altitudeStages,
    required this.plannedTrack,
    required this.landingEnvelope,
    required this.wind,
    required this.operationalBoundaries,
    required this.result,
    required this.gpxFallback,
    this.expiresAt,
    this.destination,
  });

  static const schemaVersion = 1;
  static const maximumDocumentBytes = 11 * 1024 * 1024;
  static const maximumTrackPoints = 20000;
  static const maximumEnvelopePoints = 512;
  static const maximumStages = 32;
  static const maximumBoundaries = 64;
  static const maximumBoundaryPoints = 512;

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String source;
  final GeoPoint launch;
  final double launchElevationMetersMsl;
  final String launchAltitudeDatum;
  final ForecastPlanDestination? destination;
  final ForecastPlanLandingArea intendedLandingArea;
  final GeoPoint forecastLanding;
  final ForecastPlanDeparture departure;
  final ForecastPlanConstraints constraints;
  final List<ForecastPlanStage> altitudeStages;
  final List<ForecastPlanTrackPoint> plannedTrack;
  final List<GeoPoint> landingEnvelope;
  final ForecastPlanWind wind;
  final List<OperationalBoundary> operationalBoundaries;
  final ForecastPlanResult result;
  final String gpxFallback;

  Duration get plannedDuration =>
      Duration(milliseconds: (plannedTrack.last.elapsedSeconds * 1000).round());

  factory ForecastPlanDocument.fromJson(Map<String, Object?> json) {
    final encodedBytes = utf8.encode(jsonEncode(json)).length;
    if (encodedBytes > maximumDocumentBytes) {
      throw const FormatException('Structured forecast plan is too large.');
    }
    if (json['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unsupported forecast plan schema version: ${json['schemaVersion']}.',
      );
    }
    final source = _string(json['source'], 'source', maximum: 120);
    if (source != 'Balloon Crumbs web planner') {
      throw const FormatException('Forecast plan source is not supported.');
    }
    final launch = _map(json['launch'], 'launch');
    final launchPoint = _point(launch['point'], 'launch point');
    final launchElevation = _number(
      launch['elevationMsl'],
      'launch elevation',
      minimum: -500,
      maximum: 20000,
    );
    final intended = _map(json['intendedLandingArea'], 'intended landing area');
    final polygon = _points(
      intended['polygon'] ?? const [],
      'intended landing polygon',
      maximum: maximumEnvelopePoints,
    );
    final radius = _optionalNumber(
      intended['radiusMetres'],
      'intended landing radius',
      minimumExclusive: 0,
      maximum: 100000,
    );
    if (radius == null && polygon.length < 3) {
      throw const FormatException(
        'Intended landing area needs a radius or polygon.',
      );
    }
    final departure = _map(json['departure'], 'departure');
    final windowStart = _optionalDate(
      departure['matchingWindowStart'],
      'matching window start',
    );
    final windowEnd = _optionalDate(
      departure['matchingWindowEnd'],
      'matching window end',
    );
    if (windowStart != null &&
        windowEnd != null &&
        windowEnd.isBefore(windowStart)) {
      throw const FormatException('Matching departure window is reversed.');
    }
    final constraintsJson = _map(json['constraints'], 'constraints');
    final minimumDuration = _number(
      constraintsJson['minimumDurationMinutes'],
      'minimum duration',
      minimumExclusive: 0,
      maximum: 1440,
    );
    final maximumDuration = _number(
      constraintsJson['maximumDurationMinutes'],
      'maximum duration',
      minimumExclusive: 0,
      maximum: 1440,
    );
    if (maximumDuration < minimumDuration) {
      throw const FormatException('Forecast duration limits are reversed.');
    }
    final rawStages = _list(
      json['altitudeStages'],
      'altitude stages',
      minimum: 2,
      maximum: maximumStages,
    );
    final stages = [
      for (final (index, value) in rawStages.indexed)
        _stage(_map(value, 'altitude stage ${index + 1}')),
    ];
    for (var index = 1; index < stages.length; index += 1) {
      if (stages[index].fraction <= stages[index - 1].fraction ||
          stages[index].plannedAt.isBefore(stages[index - 1].plannedAt)) {
        throw const FormatException('Forecast stages are not ordered.');
      }
    }
    final rawTrack = _list(
      json['plannedTrack'],
      'planned track',
      minimum: 2,
      maximum: maximumTrackPoints,
    );
    final track = [
      for (final (index, value) in rawTrack.indexed)
        _trackPoint(_map(value, 'planned track point ${index + 1}')),
    ];
    for (var index = 1; index < track.length; index += 1) {
      if (track[index].elapsedSeconds <= track[index - 1].elapsedSeconds) {
        throw const FormatException('Forecast track times are not ordered.');
      }
    }
    final windJson = _map(json['wind'], 'wind');
    if (windJson['forecastOnly'] != true) {
      throw const FormatException('Wind context must be marked forecast-only.');
    }
    final validFrom = _date(windJson['validFrom'], 'wind validity start');
    final validTo = _date(windJson['validTo'], 'wind validity end');
    if (validTo.isBefore(validFrom)) {
      throw const FormatException('Wind validity window is reversed.');
    }
    final rawBoundaries = _list(
      json['operationalBoundaries'] ?? const [],
      'operational boundaries',
      maximum: maximumBoundaries,
    );
    final boundaries = <OperationalBoundary>[];
    for (final (index, value) in rawBoundaries.indexed) {
      final boundaryJson = _map(value, 'operational boundary ${index + 1}');
      final points = _list(
        boundaryJson['points'] ?? const [],
        'operational boundary points',
        maximum: maximumBoundaryPoints,
      );
      boundaries.add(
        OperationalBoundary.fromJson({...boundaryJson, 'points': points}),
      );
    }
    final destinationJson = json['destination'];
    final resultJson = _map(json['result'], 'result');
    final reaches = resultJson['reachesDestination'];
    if (reaches != null && reaches is! bool) {
      throw const FormatException('Destination result must be true or false.');
    }
    final fallback = _string(
      json['gpxFallback'],
      'GPX fallback',
      maximum: maximumDocumentBytes,
    );
    return ForecastPlanDocument._(
      id: _string(json['id'], 'id', maximum: 128),
      name: _string(json['name'], 'name', maximum: 200),
      createdAt: _date(json['createdAt'], 'creation time'),
      expiresAt: _optionalDate(json['expiresAt'], 'expiry time'),
      source: source,
      launch: launchPoint,
      launchElevationMetersMsl: launchElevation,
      launchAltitudeDatum: _string(
        launch['datum'],
        'launch altitude datum',
        maximum: 64,
      ),
      destination: destinationJson == null
          ? null
          : _destination(_map(destinationJson, 'destination')),
      intendedLandingArea: ForecastPlanLandingArea(
        center: _point(intended['centre'], 'intended landing centre'),
        radiusMeters: radius,
        polygon: List.unmodifiable(polygon),
        updatedAt: _date(intended['updatedAt'], 'landing area update time'),
      ),
      forecastLanding: _point(json['forecastLanding'], 'forecast landing'),
      departure: ForecastPlanDeparture(
        selectedAt: _date(departure['selectedAt'], 'selected departure'),
        matchingWindowStart: windowStart,
        matchingWindowEnd: windowEnd,
      ),
      constraints: ForecastPlanConstraints(
        altitudeCeilingMetersMsl: _number(
          constraintsJson['altitudeCeilingMsl'],
          'altitude ceiling',
          minimum: -500,
          maximum: 20000,
        ),
        maximumAscentRateMetersPerSecond: _number(
          constraintsJson['maximumAscentRateMps'],
          'maximum ascent rate',
          minimumExclusive: 0,
          maximum: 30,
        ),
        maximumDescentRateMetersPerSecond: _number(
          constraintsJson['maximumDescentRateMps'],
          'maximum descent rate',
          minimumExclusive: 0,
          maximum: 30,
        ),
        minimumDurationMinutes: minimumDuration,
        maximumDurationMinutes: maximumDuration,
      ),
      altitudeStages: List.unmodifiable(stages),
      plannedTrack: List.unmodifiable(track),
      landingEnvelope: List.unmodifiable(
        _points(
          json['landingEnvelope'] ?? const [],
          'landing envelope',
          maximum: maximumEnvelopePoints,
        ),
      ),
      wind: ForecastPlanWind(
        provider: _string(windJson['provider'], 'wind provider', maximum: 120),
        model: _string(windJson['model'], 'wind model', maximum: 120),
        requestedAt: _date(windJson['requestedAt'], 'wind request time'),
        validFrom: validFrom,
        validTo: validTo,
        attribution: _string(
          windJson['attribution'],
          'wind attribution',
          maximum: 500,
        ),
        licence: _string(windJson['licence'], 'wind licence', maximum: 500),
        fieldDigest: _string(
          windJson['fieldDigest'],
          'wind field digest',
          maximum: 128,
        ),
      ),
      operationalBoundaries: List.unmodifiable(boundaries),
      result: ForecastPlanResult(
        kind: _string(resultJson['kind'], 'result kind', maximum: 80),
        reachesDestination: reaches as bool?,
        missDistanceMeters: _optionalNumber(
          resultJson['missDistanceMetres'],
          'miss distance',
          minimum: 0,
          maximum: 50000000,
        ),
      ),
      gpxFallback: fallback,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    'source': source,
    'launch': {
      'point': launch.toJson(),
      'elevationMsl': launchElevationMetersMsl,
      'datum': launchAltitudeDatum,
    },
    if (destination != null) 'destination': destination!.toJson(),
    'intendedLandingArea': intendedLandingArea.toJson(),
    'forecastLanding': forecastLanding.toJson(),
    'departure': departure.toJson(),
    'constraints': constraints.toJson(),
    'altitudeStages': altitudeStages
        .map((stage) => stage.toJson())
        .toList(growable: false),
    'plannedTrack': plannedTrack
        .map((point) => point.toJson())
        .toList(growable: false),
    'landingEnvelope': landingEnvelope
        .map((point) => point.toJson())
        .toList(growable: false),
    'wind': wind.toJson(),
    'operationalBoundaries': operationalBoundaries
        .map((boundary) => boundary.toJson())
        .toList(growable: false),
    'result': result.toJson(),
    'gpxFallback': gpxFallback,
  };
}

ForecastPlanDestination _destination(Map<String, Object?> json) =>
    ForecastPlanDestination(
      point: _point(json['point'], 'destination point'),
      toleranceMeters: _number(
        json['toleranceMetres'],
        'destination tolerance',
        minimumExclusive: 0,
        maximum: 100000,
      ),
    );

ForecastPlanStage _stage(Map<String, Object?> json) => ForecastPlanStage(
  fraction: _number(json['fraction'], 'stage fraction', minimum: 0, maximum: 1),
  plannedAt: _date(json['plannedAt'], 'stage time'),
  altitudeMetersMsl: _number(
    json['altitudeMsl'],
    'stage altitude',
    minimum: -500,
    maximum: 20000,
  ),
  changeRateMetersPerSecond: _number(
    json['changeRateMps'],
    'stage change rate',
    minimum: -30,
    maximum: 30,
  ),
);

ForecastPlanTrackPoint _trackPoint(Map<String, Object?> json) =>
    ForecastPlanTrackPoint(
      point: _point(json, 'track point'),
      altitudeMetersMsl: _number(
        json['altitudeMsl'],
        'track altitude',
        minimum: -500,
        maximum: 20000,
      ),
      elapsedSeconds: _number(
        json['elapsedSeconds'],
        'track elapsed time',
        minimum: 0,
        maximum: 86400,
      ),
    );

GeoPoint _point(Object? value, String label) {
  final json = _map(value, label);
  return GeoPoint(
    latitude: _number(
      json['latitude'],
      '$label latitude',
      minimum: -90,
      maximum: 90,
    ),
    longitude: _number(
      json['longitude'],
      '$label longitude',
      minimum: -180,
      maximum: 180,
    ),
  );
}

List<GeoPoint> _points(Object? value, String label, {required int maximum}) => [
  for (final (index, point) in _list(value, label, maximum: maximum).indexed)
    _point(point, '$label ${index + 1}'),
];

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return Map<String, Object?>.from(value);
}

List<Object?> _list(
  Object? value,
  String label, {
  int minimum = 0,
  required int maximum,
}) {
  if (value is! List || value.length < minimum || value.length > maximum) {
    throw FormatException('$label has an invalid number of entries.');
  }
  return List<Object?>.from(value);
}

String _string(Object? value, String label, {required int maximum}) {
  if (value is! String) throw FormatException('$label must be text.');
  final result = value.trim();
  if (result.isEmpty || result.length > maximum) {
    throw FormatException('$label has an invalid length.');
  }
  return result;
}

double _number(
  Object? value,
  String label, {
  double? minimum,
  double? minimumExclusive,
  double? maximum,
}) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$label must be a finite number.');
  }
  final result = value.toDouble();
  if ((minimum != null && result < minimum) ||
      (minimumExclusive != null && result <= minimumExclusive) ||
      (maximum != null && result > maximum)) {
    throw FormatException('$label is outside its supported range.');
  }
  return result;
}

double? _optionalNumber(
  Object? value,
  String label, {
  double? minimum,
  double? minimumExclusive,
  double? maximum,
}) => value == null
    ? null
    : _number(
        value,
        label,
        minimum: minimum,
        minimumExclusive: minimumExclusive,
        maximum: maximum,
      );

DateTime _date(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be a timestamp.');
  final result = DateTime.tryParse(value)?.toUtc();
  if (result == null) throw FormatException('$label is invalid.');
  return result;
}

DateTime? _optionalDate(Object? value, String label) =>
    value == null ? null : _date(value, label);
