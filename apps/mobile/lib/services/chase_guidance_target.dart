import '../domain/geo_point.dart';
import '../domain/landing_zone.dart';
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
