import '../domain/craft.dart';
import '../domain/geo_point.dart';
import '../domain/landing_zone.dart';
import '../domain/ride_event.dart';
import '../domain/rider_location.dart';
import 'geo_calculations.dart';

/// The moving or intended target a chase vehicle wants road guidance towards.
enum ChaseGuidanceTarget { landingArea, balloon }

extension ChaseGuidanceTargetLabel on ChaseGuidanceTarget {
  String get label => switch (this) {
    ChaseGuidanceTarget.landingArea => 'Intended landing area',
    ChaseGuidanceTarget.balloon => 'Road rendezvous near balloon',
  };
}

ChaseGuidanceTarget? chaseGuidanceTargetFromName(Object? name) => name is String
    ? ChaseGuidanceTarget.values
          .where((target) => target.name == name)
          .firstOrNull
    : null;

class ChaseGuidanceSelection {
  const ChaseGuidanceSelection({
    required this.craftId,
    required this.target,
    required this.changedAt,
    required this.changedByDeviceId,
  });

  final String craftId;
  final ChaseGuidanceTarget target;
  final DateTime changedAt;
  final String changedByDeviceId;
}

/// Replays one shared guidance choice per chase vehicle.
///
/// A selection is accepted only when its author was attached to that vehicle
/// at the time. A phone cannot redirect another vehicle by naming its craft id.
class ChaseGuidanceSelectionReducer {
  const ChaseGuidanceSelectionReducer();

  Map<String, ChaseGuidanceSelection> fromEvents(Iterable<RideEvent> events) {
    final craftKinds = <String, CraftKind>{};
    final deviceToCraft = <String, String>{};
    final selections = <String, ChaseGuidanceSelection>{};
    final ordered = events.toList()
      ..sort((first, second) {
        final byTime = first.createdAt.compareTo(second.createdAt);
        return byTime != 0 ? byTime : first.id.compareTo(second.id);
      });

    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.craftRegistered:
          final craftId = event.payload['craftId'] ?? event.payload['id'];
          if (craftId is String && craftId.isNotEmpty) {
            craftKinds[craftId] = craftKindFromName(event.payload['kind']);
          }
        case RideEventType.deviceAttachedToCraft:
          final deviceId = event.payload['deviceId'];
          final craftId = event.payload['craftId'];
          if (deviceId is String && craftId is String) {
            deviceToCraft[deviceId] = craftId;
          }
        case RideEventType.chaseGuidanceTargetSelected:
          final craftId = event.payload['craftId'];
          final target = chaseGuidanceTargetFromName(event.payload['target']);
          if (craftId is! String ||
              target == null ||
              craftKinds[craftId] != CraftKind.vehicle ||
              deviceToCraft[event.deviceId] != craftId) {
            break;
          }
          selections[craftId] = ChaseGuidanceSelection(
            craftId: craftId,
            target: target,
            changedAt: event.createdAt,
            changedByDeviceId: event.deviceId,
          );
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.riderLeft:
        case RideEventType.roleChanged:
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
        case RideEventType.craftPrimaryDeviceNominated:
        case RideEventType.craftChaseAssigned:
        case RideEventType.landingAreaNoted:
        case RideEventType.windContextNoted:
        case RideEventType.operationalBoundaryUpserted:
        case RideEventType.operationalBoundaryRemoved:
        case RideEventType.pilotHandoverOffered:
        case RideEventType.pilotHandoverAccepted:
          break;
      }
    }
    return Map.unmodifiable(selections);
  }
}

/// A target suitable for asking a road-routing engine for a personal route.
///
/// The coordinate remains an airborne or approximate target. The route engine
/// may snap it to a nearby road, so callers must validate the returned endpoint
/// with [acceptsRoadEndpoint] and keep the distinction visible in the UI.
class ChaseGuidanceDestination {
  const ChaseGuidanceDestination({
    required this.kind,
    required this.point,
    required this.label,
    required this.maximumRoadSeparationMeters,
    required this.observedAt,
  });

  final ChaseGuidanceTarget kind;
  final GeoPoint point;
  final String label;
  final double maximumRoadSeparationMeters;
  final DateTime observedAt;

  bool acceptsRoadEndpoint(GeoPoint endpoint) =>
      GeoCalculations.distanceMeters(endpoint, point) <=
      maximumRoadSeparationMeters;
}

/// Resolves honest chase targets from the latest shared flight evidence.
class ChaseGuidanceTargetResolver {
  const ChaseGuidanceTargetResolver({
    this.maximumBalloonFixAge = const Duration(seconds: 45),
    this.maximumBalloonRoadSeparationMeters = 1200,
    this.landingAreaRoadMarginMeters = 500,
  });

  final Duration maximumBalloonFixAge;
  final double maximumBalloonRoadSeparationMeters;
  final double landingAreaRoadMarginMeters;

  ChaseGuidanceDestination? resolve({
    required ChaseGuidanceTarget target,
    required DateTime now,
    LandingZoneTarget? landingZone,
    LocationSample? balloonFix,
  }) => switch (target) {
    ChaseGuidanceTarget.landingArea => _landingArea(landingZone),
    ChaseGuidanceTarget.balloon => _balloon(balloonFix, now),
  };

  ChaseGuidanceDestination? _landingArea(LandingZoneTarget? target) {
    if (target == null || !target.isValid) return null;
    return ChaseGuidanceDestination(
      kind: ChaseGuidanceTarget.landingArea,
      point: target.center,
      label: target.label,
      maximumRoadSeparationMeters:
          target.radiusMeters + landingAreaRoadMarginMeters,
      observedAt: target.updatedAt,
    );
  }

  ChaseGuidanceDestination? _balloon(LocationSample? fix, DateTime now) {
    if (fix == null || fix.ageAt(now) > maximumBalloonFixAge) return null;
    return ChaseGuidanceDestination(
      kind: ChaseGuidanceTarget.balloon,
      point: fix.position,
      label: 'Balloon · fix ${fix.ageAt(now).inSeconds}s ago',
      maximumRoadSeparationMeters: maximumBalloonRoadSeparationMeters,
      observedAt: fix.recordedAt,
    );
  }
}

/// Keeps moving-target routing bounded instead of requesting on every GPS fix.
class ChaseGuidanceReroutePolicy {
  const ChaseGuidanceReroutePolicy({
    this.minimumInterval = const Duration(minutes: 2),
    this.minimumTargetMovementMeters = 300,
  });

  final Duration minimumInterval;
  final double minimumTargetMovementMeters;

  bool shouldReroute({
    required DateTime now,
    required GeoPoint target,
    DateTime? lastRoutedAt,
    GeoPoint? lastTarget,
    bool force = false,
  }) {
    if (force || lastRoutedAt == null || lastTarget == null) return true;
    if (now.difference(lastRoutedAt) < minimumInterval) return false;
    return GeoCalculations.distanceMeters(lastTarget, target) >=
        minimumTargetMovementMeters;
  }
}
