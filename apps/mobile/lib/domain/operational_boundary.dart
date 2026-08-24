import 'altitude.dart';
import 'altitude_unit.dart';
import 'geo_point.dart';
import 'ride_event.dart';
import 'ride_role.dart';

enum OperationalBoundaryKind { line, area, altitudeBand }

/// Which transition should raise an alert.
///
/// For an area this has the ordinary inside/outside meaning. For an oriented
/// line, [entering] means right-to-left into the line's left side and [leaving]
/// means left-to-right. Altitude bands use [either]: either upper or lower
/// limit is a departure from the configured band.
enum OperationalBoundaryWarningDirection { entering, leaving, either }

class OperationalBoundary {
  const OperationalBoundary({
    required this.id,
    required this.label,
    required this.kind,
    required this.points,
    required this.source,
    required this.updatedAt,
    this.enabled = true,
    this.warningDirection = OperationalBoundaryWarningDirection.either,
    this.effectiveFrom,
    this.validUntil,
    this.limitations =
        'Advisory only; verify against current official information.',
    this.lowerAltitudeMeters,
    this.upperAltitudeMeters,
    this.altitudeDatum = AltitudeDatum.wgs84Geoid,
    this.altitudeUnit = AltitudeUnit.metres,
    this.acceptedAltitudeSources = const {
      AltitudeSource.gnss,
      AltitudeSource.barometric,
    },
  });

  final String id;
  final String label;
  final OperationalBoundaryKind kind;
  final List<GeoPoint> points;
  final String source;
  final DateTime updatedAt;
  final bool enabled;
  final OperationalBoundaryWarningDirection warningDirection;

  /// When this advisory starts applying; [updatedAt] for legacy definitions.
  final DateTime? effectiveFrom;
  final DateTime? validUntil;
  final String limitations;
  final double? lowerAltitudeMeters;
  final double? upperAltitudeMeters;
  final AltitudeDatum altitudeDatum;
  final AltitudeUnit altitudeUnit;
  final Set<AltitudeSource> acceptedAltitudeSources;

  DateTime get effectiveAt => effectiveFrom ?? updatedAt;

  bool appliesAt(DateTime value) {
    final utc = value.toUtc();
    return !utc.isBefore(effectiveAt.toUtc()) &&
        (validUntil == null || !utc.isAfter(validUntil!.toUtc()));
  }

  bool get hasAltitudeBand =>
      lowerAltitudeMeters != null || upperAltitudeMeters != null;

  bool get isValid {
    final pointCountValid = switch (kind) {
      OperationalBoundaryKind.line => points.length >= 2,
      OperationalBoundaryKind.area => points.length >= 3,
      OperationalBoundaryKind.altitudeBand => points.isEmpty && hasAltitudeBand,
    };
    final altitudeValid =
        !hasAltitudeBand ||
        ((lowerAltitudeMeters == null || lowerAltitudeMeters!.isFinite) &&
            (upperAltitudeMeters == null || upperAltitudeMeters!.isFinite) &&
            (lowerAltitudeMeters == null ||
                upperAltitudeMeters == null ||
                lowerAltitudeMeters! < upperAltitudeMeters!));
    final timeValid =
        validUntil == null || validUntil!.isAfter(effectiveAt.toUtc());
    final sourceRequirementsValid =
        !hasAltitudeBand ||
        (altitudeDatum != AltitudeDatum.unknown &&
            acceptedAltitudeSources.isNotEmpty &&
            !acceptedAltitudeSources.contains(AltitudeSource.unknown));
    final directionValid =
        kind != OperationalBoundaryKind.altitudeBand ||
        warningDirection == OperationalBoundaryWarningDirection.either;
    return id.trim().isNotEmpty &&
        id.length <= 96 &&
        label.trim().isNotEmpty &&
        label.length <= 96 &&
        source.trim().isNotEmpty &&
        source.length <= 160 &&
        limitations.trim().isNotEmpty &&
        limitations.length <= 500 &&
        pointCountValid &&
        altitudeValid &&
        timeValid &&
        sourceRequirementsValid &&
        directionValid &&
        points.every(
          (point) =>
              point.latitude.isFinite &&
              point.latitude >= -90 &&
              point.latitude <= 90 &&
              point.longitude.isFinite &&
              point.longitude >= -180 &&
              point.longitude <= 180,
        );
  }

  Map<String, Object?> toEventPayload({required String leaderRiderId}) => {
    'leaderRiderId': leaderRiderId,
    'boundary': toJson(),
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'points': [
      for (final point in points)
        {'latitude': point.latitude, 'longitude': point.longitude},
    ],
    'source': source,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'enabled': enabled,
    'warningDirection': warningDirection.name,
    'effectiveFrom': effectiveAt.toUtc().toIso8601String(),
    if (validUntil != null) 'validUntil': validUntil!.toUtc().toIso8601String(),
    'limitations': limitations,
    if (lowerAltitudeMeters != null) 'lowerAltitudeMeters': lowerAltitudeMeters,
    if (upperAltitudeMeters != null) 'upperAltitudeMeters': upperAltitudeMeters,
    'altitudeDatum': altitudeDatum.name,
    'altitudeUnit': altitudeUnit.name,
    'acceptedAltitudeSources': [
      for (final source in AltitudeSource.values)
        if (acceptedAltitudeSources.contains(source)) source.name,
    ],
  };

  factory OperationalBoundary.fromJson(Map<String, Object?> json) {
    final rawPoints = json['points'];
    if (rawPoints is! List) {
      throw const FormatException('Boundary points are invalid.');
    }
    final kind = OperationalBoundaryKind.values
        .where((kind) => kind.name == json['kind'])
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('Boundary kind is invalid.');
    }
    final updatedAt = DateTime.parse(json['updatedAt']! as String).toUtc();
    final warningDirection = OperationalBoundaryWarningDirection.values
        .where((direction) => direction.name == json['warningDirection'])
        .firstOrNull;
    final rawAcceptedSources = json['acceptedAltitudeSources'];
    final acceptedSources = rawAcceptedSources is List
        ? {
            for (final value in rawAcceptedSources.whereType<String>())
              ...AltitudeSource.values.where((source) => source.name == value),
          }
        : const {AltitudeSource.gnss, AltitudeSource.barometric};
    final boundary = OperationalBoundary(
      id: json['id']! as String,
      label: json['label']! as String,
      kind: kind,
      points: [
        for (final point in rawPoints.whereType<Map>())
          GeoPoint(
            latitude: (point['latitude'] as num).toDouble(),
            longitude: (point['longitude'] as num).toDouble(),
          ),
      ],
      source: json['source']! as String,
      updatedAt: updatedAt,
      enabled: json['enabled'] as bool? ?? true,
      warningDirection:
          warningDirection ?? OperationalBoundaryWarningDirection.either,
      effectiveFrom: DateTime.tryParse(
        json['effectiveFrom'] as String? ?? '',
      )?.toUtc(),
      validUntil: DateTime.tryParse(
        json['validUntil'] as String? ?? '',
      )?.toUtc(),
      limitations:
          json['limitations'] as String? ??
          'Advisory only; verify against current official information.',
      lowerAltitudeMeters: (json['lowerAltitudeMeters'] as num?)?.toDouble(),
      upperAltitudeMeters: (json['upperAltitudeMeters'] as num?)?.toDouble(),
      altitudeDatum:
          AltitudeDatum.values
              .where((datum) => datum.name == json['altitudeDatum'])
              .firstOrNull ??
          AltitudeDatum.unknown,
      altitudeUnit:
          AltitudeUnit.values
              .where((unit) => unit.name == json['altitudeUnit'])
              .firstOrNull ??
          AltitudeUnit.metres,
      acceptedAltitudeSources: acceptedSources,
    );
    if (!boundary.isValid) {
      throw const FormatException('Boundary is invalid.');
    }
    return boundary;
  }
}

class OperationalBoundaryReducer {
  const OperationalBoundaryReducer();

  List<OperationalBoundary> fromEvents(Iterable<RideEvent> events) {
    final ordered = events.toList()
      ..sort((left, right) {
        final time = left.createdAt.compareTo(right.createdAt);
        return time != 0 ? time : left.id.compareTo(right.id);
      });
    final roles = <String, RideRole>{};
    final boundaries = <String, OperationalBoundary>{};
    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.roleChanged:
          final role = event.payload['role'];
          if (role is String) {
            roles[event.deviceId] =
                RideRole.values
                    .where((candidate) => candidate.name == role)
                    .firstOrNull ??
                RideRole.rider;
          }
        case RideEventType.operationalBoundaryUpserted:
          if (roles[event.deviceId] != RideRole.lead ||
              event.payload['leaderRiderId'] != event.deviceId) {
            break;
          }
          final raw = event.payload['boundary'];
          if (raw is! Map) break;
          try {
            final boundary = OperationalBoundary.fromJson(
              Map<String, Object?>.from(raw),
            );
            boundaries[boundary.id] = boundary;
          } on Object {
            // One malformed boundary cannot hide the valid set.
          }
        case RideEventType.operationalBoundaryRemoved:
          if (roles[event.deviceId] != RideRole.lead ||
              event.payload['leaderRiderId'] != event.deviceId) {
            break;
          }
          final id = event.payload['boundaryId'];
          if (id is String) boundaries.remove(id);
        case RideEventType.operationalBoundaryAlerted:
        case RideEventType.riderLeft:
        case RideEventType.rideStarted:
        case RideEventType.flightStartedByCrew:
        case RideEventType.flightLanded:
        case RideEventType.flightLandingRetracted:
        case RideEventType.deviceAuthorityRevoked:
        case RideEventType.deviceAuthorityRotated:
        case RideEventType.statusMessage:
        case RideEventType.riderLocationUpdated:
        case RideEventType.hazardReported:
        case RideEventType.hazardCleared:
        case RideEventType.routeRevisionChunk:
        case RideEventType.routeRevisionPublished:
        case RideEventType.routeCleared:
        case RideEventType.ridePaused:
        case RideEventType.rideResumed:
        case RideEventType.rideEnded:
        case RideEventType.iceInfoShared:
        case RideEventType.iceInfoViewed:
        case RideEventType.riderContactShared:
        case RideEventType.rideReopened:
        case RideEventType.craftRegistered:
        case RideEventType.deviceAttachedToCraft:
        case RideEventType.craftPrimaryDeviceNominated:
        case RideEventType.craftChaseAssigned:
        case RideEventType.landingAreaNoted:
        case RideEventType.windContextNoted:
        case RideEventType.chaseGuidanceTargetSelected:
        case RideEventType.pilotHandoverOffered:
        case RideEventType.pilotHandoverAccepted:
          break;
      }
    }
    final result = boundaries.values.toList()
      ..sort((left, right) => left.label.compareTo(right.label));
    return List.unmodifiable(result);
  }
}
