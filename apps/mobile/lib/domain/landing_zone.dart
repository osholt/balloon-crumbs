import 'geo_point.dart';
import 'ride_event.dart';
import 'ride_role.dart';

/// An approximate area the pilot intends the crew to use as a rendezvous.
///
/// This is not a predicted touchdown and does not assert road access, landowner
/// permission, or suitability. Those limits travel with the event and are
/// repeated on the map surface.
class LandingZoneTarget {
  const LandingZoneTarget({
    required this.center,
    required this.radiusMeters,
    required this.label,
    required this.updatedAt,
  });

  static const minimumRadiusMeters = 100.0;
  static const maximumRadiusMeters = 5000.0;

  final GeoPoint center;
  final double radiusMeters;
  final String label;
  final DateTime updatedAt;

  Map<String, Object?> toEventPayload({required String leaderRiderId}) => {
    'leaderRiderId': leaderRiderId,
    'latitude': center.latitude,
    'longitude': center.longitude,
    'radiusMeters': radiusMeters,
    'label': label,
    'limitations':
        'Approximate rendezvous area; access, permission and landing suitability are unverified.',
  };

  Map<String, Object?> toJson() => {
    'latitude': center.latitude,
    'longitude': center.longitude,
    'radiusMeters': radiusMeters,
    'label': label,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LandingZoneTarget.fromJson(Map<String, Object?> json) {
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final radius = json['radiusMeters'];
    final label = json['label'];
    final updatedAt = json['updatedAt'];
    if (latitude is! num ||
        longitude is! num ||
        radius is! num ||
        label is! String ||
        updatedAt is! String) {
      throw const FormatException('Landing area is invalid.');
    }
    final result = LandingZoneTarget(
      center: GeoPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
      radiusMeters: radius.toDouble(),
      label: label.trim(),
      updatedAt: DateTime.parse(updatedAt).toLocal(),
    );
    if (!result.isValid) {
      throw const FormatException('Landing area is invalid.');
    }
    return result;
  }

  bool get isValid =>
      center.latitude.isFinite &&
      center.latitude >= -90 &&
      center.latitude <= 90 &&
      center.longitude.isFinite &&
      center.longitude >= -180 &&
      center.longitude <= 180 &&
      radiusMeters.isFinite &&
      radiusMeters >= minimumRadiusMeters &&
      radiusMeters <= maximumRadiusMeters &&
      label.isNotEmpty &&
      label.length <= 96;
}

/// Reduces the latest leader-authored landing-area event.
///
/// Every participant shares the operation secret, so a valid signature alone
/// cannot confer pilot authority. The role journal is replayed alongside the
/// target and only the current lead device may replace it.
class LandingZoneReducer {
  const LandingZoneReducer();

  LandingZoneTarget? fromEvents(Iterable<RideEvent> events) {
    final ordered = events.toList()
      ..sort((left, right) {
        final byTime = left.createdAt.compareTo(right.createdAt);
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
    final roles = <String, RideRole>{};
    LandingZoneTarget? latest;
    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.roleChanged:
          final roleName = event.payload['role'];
          if (roleName is String) {
            try {
              roles[event.deviceId] = RideRole.values.byName(roleName);
            } on ArgumentError {
              // A malformed membership event cannot grant target authority.
            }
          }
        case RideEventType.landingAreaNoted:
          if (roles[event.deviceId] != RideRole.lead ||
              event.payload['leaderRiderId'] != event.deviceId) {
            continue;
          }
          final candidate = _fromEvent(event);
          if (candidate != null) latest = candidate;
        case RideEventType.riderLeft:
        case RideEventType.rideStarted:
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
          break;
      }
    }
    return latest;
  }

  LandingZoneTarget? _fromEvent(RideEvent event) {
    final latitude = event.payload['latitude'];
    final longitude = event.payload['longitude'];
    final radius = event.payload['radiusMeters'];
    final label = event.payload['label'];
    if (latitude is! num ||
        longitude is! num ||
        radius is! num ||
        label is! String) {
      return null;
    }
    final target = LandingZoneTarget(
      center: GeoPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
      radiusMeters: radius.toDouble(),
      label: label.trim(),
      updatedAt: event.createdAt,
    );
    return target.isValid ? target : null;
  }
}
