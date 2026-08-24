import 'altitude.dart';
import 'geo_point.dart';

enum FlightReplayTrackKind { balloon, localChaser, chaser }

class FlightReplaySample {
  const FlightReplaySample({
    required this.position,
    required this.recordedAt,
    this.speedMetersPerSecond,
    this.headingDegrees,
    this.altitudeMeters,
    this.altitudeSource = AltitudeSource.unknown,
    this.altitudeDatum = AltitudeDatum.unknown,
    this.verticalSpeedMetersPerSecond,
  });

  final GeoPoint position;
  final DateTime recordedAt;
  final double? speedMetersPerSecond;
  final double? headingDegrees;
  final double? altitudeMeters;
  final AltitudeSource altitudeSource;
  final AltitudeDatum altitudeDatum;
  final double? verticalSpeedMetersPerSecond;

  Map<String, Object?> toJson() => {
    'latitude': position.latitude,
    'longitude': position.longitude,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    if (speedMetersPerSecond != null)
      'speedMetersPerSecond': speedMetersPerSecond,
    if (headingDegrees != null) 'headingDegrees': headingDegrees,
    if (altitudeMeters != null) 'altitudeMeters': altitudeMeters,
    'altitudeSource': altitudeSource.name,
    'altitudeDatum': altitudeDatum.name,
    if (verticalSpeedMetersPerSecond != null)
      'verticalSpeedMetersPerSecond': verticalSpeedMetersPerSecond,
  };

  factory FlightReplaySample.fromJson(Map<String, Object?> json) =>
      FlightReplaySample(
        position: GeoPoint(
          latitude: _finite(json['latitude'], 'latitude'),
          longitude: _finite(json['longitude'], 'longitude'),
        ),
        recordedAt: DateTime.parse(json['recordedAt']! as String).toUtc(),
        speedMetersPerSecond: _optionalFinite(json['speedMetersPerSecond']),
        headingDegrees: _optionalFinite(json['headingDegrees']),
        altitudeMeters: _optionalFinite(json['altitudeMeters']),
        altitudeSource: _enumByName(
          AltitudeSource.values,
          json['altitudeSource'],
          AltitudeSource.unknown,
        ),
        altitudeDatum: _enumByName(
          AltitudeDatum.values,
          json['altitudeDatum'],
          AltitudeDatum.unknown,
        ),
        verticalSpeedMetersPerSecond: _optionalFinite(
          json['verticalSpeedMetersPerSecond'],
        ),
      );
}

class FlightReplayTrack {
  const FlightReplayTrack({
    required this.id,
    required this.label,
    required this.kind,
    required this.samples,
  });

  final String id;
  final String label;
  final FlightReplayTrackKind kind;
  final List<FlightReplaySample> samples;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'samples': samples.map((sample) => sample.toJson()).toList(),
  };

  factory FlightReplayTrack.fromJson(Map<String, Object?> json) {
    final rawSamples = json['samples'];
    if (rawSamples is! List) {
      throw const FormatException('Replay track samples are invalid.');
    }
    return FlightReplayTrack(
      id: json['id']! as String,
      label: json['label']! as String,
      kind: _enumByName(
        FlightReplayTrackKind.values,
        json['kind'],
        FlightReplayTrackKind.chaser,
      ),
      samples: [
        for (final sample in rawSamples.whereType<Map>())
          FlightReplaySample.fromJson(Map<String, Object?>.from(sample)),
      ],
    );
  }
}

class FlightReplayWindVector {
  const FlightReplayWindVector({
    required this.altitudeMetersMsl,
    required this.fromDegrees,
    required this.speedKmh,
  });

  final double altitudeMetersMsl;
  final double fromDegrees;
  final double speedKmh;

  Map<String, Object?> toJson() => {
    'altitudeMetersMsl': altitudeMetersMsl,
    'fromDegrees': fromDegrees,
    'speedKmh': speedKmh,
  };

  factory FlightReplayWindVector.fromJson(Map<String, Object?> json) =>
      FlightReplayWindVector(
        altitudeMetersMsl: _finite(
          json['altitudeMetersMsl'],
          'altitudeMetersMsl',
        ),
        fromDegrees: _finite(json['fromDegrees'], 'fromDegrees'),
        speedKmh: _finite(json['speedKmh'], 'speedKmh'),
      );
}

class FlightReplayWindContext {
  const FlightReplayWindContext({
    required this.recordedAt,
    required this.validAt,
    required this.source,
    required this.isForecast,
    required this.position,
    required this.vectors,
  });

  final DateTime recordedAt;
  final DateTime validAt;
  final String source;
  final bool isForecast;
  final GeoPoint position;
  final List<FlightReplayWindVector> vectors;

  Map<String, Object?> toJson() => {
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'validAt': validAt.toUtc().toIso8601String(),
    'source': source,
    'isForecast': isForecast,
    'latitude': position.latitude,
    'longitude': position.longitude,
    'vectors': vectors.map((vector) => vector.toJson()).toList(),
  };

  factory FlightReplayWindContext.fromJson(Map<String, Object?> json) {
    final rawVectors = json['vectors'];
    if (rawVectors is! List) {
      throw const FormatException('Replay wind vectors are invalid.');
    }
    return FlightReplayWindContext(
      recordedAt: DateTime.parse(json['recordedAt']! as String).toUtc(),
      validAt: DateTime.parse(json['validAt']! as String).toUtc(),
      source: json['source']! as String,
      isForecast: json['isForecast']! as bool,
      position: GeoPoint(
        latitude: _finite(json['latitude'], 'latitude'),
        longitude: _finite(json['longitude'], 'longitude'),
      ),
      vectors: [
        for (final vector in rawVectors.whereType<Map>())
          FlightReplayWindVector.fromJson(Map<String, Object?>.from(vector)),
      ],
    );
  }
}

class FlightReplayLandingArea {
  const FlightReplayLandingArea({
    required this.recordedAt,
    required this.center,
    required this.radiusMeters,
    required this.label,
  });

  final DateTime recordedAt;
  final GeoPoint center;
  final double radiusMeters;
  final String label;

  Map<String, Object?> toJson() => {
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'latitude': center.latitude,
    'longitude': center.longitude,
    'radiusMeters': radiusMeters,
    'label': label,
  };

  factory FlightReplayLandingArea.fromJson(Map<String, Object?> json) =>
      FlightReplayLandingArea(
        recordedAt: DateTime.parse(json['recordedAt']! as String).toUtc(),
        center: GeoPoint(
          latitude: _finite(json['latitude'], 'latitude'),
          longitude: _finite(json['longitude'], 'longitude'),
        ),
        radiusMeters: _finite(json['radiusMeters'], 'radiusMeters'),
        label: json['label']! as String,
      );
}

class FlightReplayBoundaryAlert {
  const FlightReplayBoundaryAlert({
    required this.recordedAt,
    required this.boundaryId,
    required this.boundaryLabel,
    required this.kind,
    required this.assessment,
    required this.confirmed,
    required this.message,
    this.position,
    this.altitudeMeters,
  });

  final DateTime recordedAt;
  final String boundaryId;
  final String boundaryLabel;
  final String kind;
  final String assessment;
  final bool confirmed;
  final String message;
  final GeoPoint? position;
  final double? altitudeMeters;

  Map<String, Object?> toJson() => {
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'boundaryId': boundaryId,
    'boundaryLabel': boundaryLabel,
    'kind': kind,
    'assessment': assessment,
    'confirmed': confirmed,
    'message': message,
    if (position != null) 'latitude': position!.latitude,
    if (position != null) 'longitude': position!.longitude,
    if (altitudeMeters != null) 'altitudeMeters': altitudeMeters,
  };

  factory FlightReplayBoundaryAlert.fromJson(Map<String, Object?> json) {
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    return FlightReplayBoundaryAlert(
      recordedAt: DateTime.parse(json['recordedAt']! as String).toUtc(),
      boundaryId: json['boundaryId']! as String,
      boundaryLabel: json['boundaryLabel']! as String,
      kind: json['kind']! as String,
      assessment: json['assessment']! as String,
      confirmed: json['confirmed']! as bool,
      message: json['message']! as String,
      position: latitude is num && longitude is num
          ? GeoPoint(
              latitude: latitude.toDouble(),
              longitude: longitude.toDouble(),
            )
          : null,
      altitudeMeters: _optionalFinite(json['altitudeMeters']),
    );
  }
}

class FlightReplay {
  const FlightReplay({
    required this.startedAt,
    required this.endedAt,
    required this.tracks,
    required this.windContexts,
    required this.landingAreas,
    required this.peerTracksIncluded,
    this.boundaryAlerts = const [],
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final List<FlightReplayTrack> tracks;
  final List<FlightReplayWindContext> windContexts;
  final List<FlightReplayLandingArea> landingAreas;
  final List<FlightReplayBoundaryAlert> boundaryAlerts;
  final bool peerTracksIncluded;

  Duration get duration => endedAt.difference(startedAt).abs();
  bool get canReplay => tracks.any((track) => track.samples.length >= 2);

  Map<String, Object?> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'peerTracksIncluded': peerTracksIncluded,
    'tracks': tracks.map((track) => track.toJson()).toList(),
    'windContexts': windContexts.map((wind) => wind.toJson()).toList(),
    'landingAreas': landingAreas.map((area) => area.toJson()).toList(),
    'boundaryAlerts': boundaryAlerts.map((alert) => alert.toJson()).toList(),
  };

  factory FlightReplay.fromJson(Map<String, Object?> json) => FlightReplay(
    startedAt: DateTime.parse(json['startedAt']! as String).toUtc(),
    endedAt: DateTime.parse(json['endedAt']! as String).toUtc(),
    peerTracksIncluded: json['peerTracksIncluded'] as bool? ?? false,
    tracks: _objects(json['tracks'], FlightReplayTrack.fromJson),
    windContexts: _objects(
      json['windContexts'],
      FlightReplayWindContext.fromJson,
    ),
    landingAreas: _objects(
      json['landingAreas'],
      FlightReplayLandingArea.fromJson,
    ),
    boundaryAlerts: _objects(
      json['boundaryAlerts'],
      FlightReplayBoundaryAlert.fromJson,
    ),
  );
}

List<T> _objects<T>(Object? value, T Function(Map<String, Object?>) parse) {
  if (value is! List) return const [];
  return [
    for (final item in value.whereType<Map>())
      parse(Map<String, Object?>.from(item)),
  ];
}

double _finite(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('Replay $field is invalid.');
  }
  return value.toDouble();
}

double? _optionalFinite(Object? value) => value == null
    ? null
    : value is num && value.isFinite
    ? value.toDouble()
    : throw const FormatException('Replay value is invalid.');

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((value) => value.name == name).firstOrNull ?? fallback;
