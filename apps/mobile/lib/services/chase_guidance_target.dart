import 'dart:math' as math;

import '../domain/craft.dart';
import '../domain/flight_landing.dart';
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
    required this.evidencePoint,
    required this.label,
    required this.maximumRoadSeparationMeters,
    required this.uncertaintyRadiusMeters,
    required this.observedAt,
    required this.limitations,
    this.preferredBearingDegrees,
  });

  final ChaseGuidanceTarget kind;

  /// Bounded motion estimate or intended-area centre used to place candidate
  /// road endpoints. This point is never sent directly as a driving endpoint.
  final GeoPoint point;
  final GeoPoint evidencePoint;
  final String label;
  final double maximumRoadSeparationMeters;
  final double uncertaintyRadiusMeters;
  final DateTime observedAt;
  final String limitations;
  final double? preferredBearingDegrees;

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
    this.balloonMotionLookahead = const Duration(seconds: 60),
  });

  final Duration maximumBalloonFixAge;
  final double maximumBalloonRoadSeparationMeters;
  final double landingAreaRoadMarginMeters;
  final Duration balloonMotionLookahead;

  ChaseGuidanceDestination? resolve({
    required ChaseGuidanceTarget target,
    required DateTime now,
    LandingZoneTarget? landingZone,
    LocationSample? balloonFix,
    FlightLanding? landing,
  }) => switch (target) {
    ChaseGuidanceTarget.landingArea => _landingArea(landingZone),
    ChaseGuidanceTarget.balloon => _balloon(balloonFix, now, landing),
  };

  ChaseGuidanceDestination? _landingArea(LandingZoneTarget? target) {
    if (target == null || !target.isValid) return null;
    return ChaseGuidanceDestination(
      kind: ChaseGuidanceTarget.landingArea,
      point: target.center,
      evidencePoint: target.center,
      label: target.label,
      maximumRoadSeparationMeters:
          target.radiusMeters + landingAreaRoadMarginMeters,
      uncertaintyRadiusMeters: target.radiusMeters,
      observedAt: target.updatedAt,
      limitations:
          'Pilot intent only; landing suitability, field permission, road access and safe stopping are unverified.',
    );
  }

  ChaseGuidanceDestination? _balloon(
    LocationSample? fix,
    DateTime now,
    FlightLanding? landing,
  ) {
    if (landing?.location case final landedFix?) {
      return ChaseGuidanceDestination(
        kind: ChaseGuidanceTarget.balloon,
        point: landedFix.position,
        evidencePoint: landedFix.position,
        label:
            '${landing!.locationConfidence?.label ?? 'Best-known landing'} · LANDED',
        maximumRoadSeparationMeters: landing.hasConfirmedLocation
            ? 800
            : maximumBalloonRoadSeparationMeters,
        uncertaintyRadiusMeters: math.max(
          landedFix.accuracyMeters,
          landing.hasConfirmedLocation ? 100 : 300,
        ),
        observedAt: landing.declaredAt,
        limitations:
            'Landing evidence is preserved, but road access, field permission and safe stopping remain unverified.',
      );
    }
    if (fix == null || fix.ageAt(now) > maximumBalloonFixAge) return null;
    final speed = fix.speedMetersPerSecond;
    final heading = fix.headingDegrees;
    final hasMotion =
        speed != null &&
        speed.isFinite &&
        speed >= 0.5 &&
        heading != null &&
        heading.isFinite;
    final projectedDistance = hasMotion
        ? math.min(
            speed * balloonMotionLookahead.inMilliseconds / 1000,
            maximumBalloonRoadSeparationMeters * 0.75,
          )
        : 0.0;
    final projected = hasMotion
        ? _offset(
            fix.position,
            bearingDegrees: heading,
            distanceMeters: projectedDistance,
          )
        : fix.position;
    final fixAge = fix.ageAt(now);
    return ChaseGuidanceDestination(
      kind: ChaseGuidanceTarget.balloon,
      point: projected,
      evidencePoint: fix.position,
      label: hasMotion
          ? 'Balloon motion estimate · fix ${fixAge.inSeconds}s ago'
          : 'Balloon vicinity · fix ${fixAge.inSeconds}s ago',
      maximumRoadSeparationMeters: maximumBalloonRoadSeparationMeters,
      uncertaintyRadiusMeters: math.max(
        150,
        fix.accuracyMeters + (speed ?? 0) * (fixAge.inSeconds + 20),
      ),
      observedAt: fix.recordedAt,
      preferredBearingDegrees: hasMotion ? heading : null,
      limitations: hasMotion
          ? '${balloonMotionLookahead.inSeconds}s constant-motion estimate from a measured fix; wind, altitude changes, private access and safe stopping remain unverified.'
          : 'No usable direction and speed; candidates surround the measured fix. Private access and safe stopping remain unverified.',
    );
  }

  static GeoPoint _offset(
    GeoPoint point, {
    required double bearingDegrees,
    required double distanceMeters,
  }) {
    final angularDistance = distanceMeters / GeoCalculations.earthRadiusMeters;
    final bearing = bearingDegrees * math.pi / 180;
    final latitude = point.latitude * math.pi / 180;
    final longitude = point.longitude * math.pi / 180;
    final destinationLatitude = math.asin(
      math.sin(latitude) * math.cos(angularDistance) +
          math.cos(latitude) * math.sin(angularDistance) * math.cos(bearing),
    );
    final destinationLongitude =
        longitude +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(latitude),
          math.cos(angularDistance) -
              math.sin(latitude) * math.sin(destinationLatitude),
        );
    return GeoPoint(
      latitude: destinationLatitude * 180 / math.pi,
      longitude: ((destinationLongitude * 180 / math.pi + 540) % 360) - 180,
    );
  }
}

/// Keeps moving-target routing bounded instead of requesting on every GPS fix.
class ChaseGuidanceReroutePolicy {
  const ChaseGuidanceReroutePolicy({
    this.minimumInterval = const Duration(minutes: 2),
    this.minimumTargetMovementMeters = 300,
    this.maximumRouteAge = const Duration(minutes: 10),
  });

  final Duration minimumInterval;
  final double minimumTargetMovementMeters;
  final Duration maximumRouteAge;

  bool shouldReroute({
    required DateTime now,
    required GeoPoint target,
    DateTime? lastRoutedAt,
    GeoPoint? lastTarget,
    bool force = false,
  }) {
    if (force || lastRoutedAt == null || lastTarget == null) return true;
    final age = now.difference(lastRoutedAt);
    if (age < minimumInterval) return false;
    if (age >= maximumRouteAge) return true;
    return GeoCalculations.distanceMeters(lastTarget, target) >=
        minimumTargetMovementMeters;
  }
}
