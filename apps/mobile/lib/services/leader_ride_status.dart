import '../domain/geo_point.dart';
import '../domain/ride_role.dart';
import '../domain/rider_location.dart';
import '../domain/route_alert.dart';
import 'leader_track_exemption.dart';

class LeaderOffCourseAlert {
  const LeaderOffCourseAlert({
    required this.riderId,
    required this.displayName,
    required this.level,
    this.distanceFromRouteMeters,
  });

  final String riderId;
  final String displayName;
  final RouteAlertLevel level;
  final double? distanceFromRouteMeters;
}

/// What the ride leader needs to know about riders who have left the route.
///
/// This also reported on the back-marker role until that role was removed with
/// the Tail End Charlie migration: a balloon has no sweep rider, so there is no
/// equivalent target to measure a gap to. See `docs/delivery-plan.md` WP1.
class LeaderRideStatus {
  const LeaderRideStatus({required this.offCourseAlerts});

  final List<LeaderOffCourseAlert> offCourseAlerts;
}

class LeaderRideStatusCalculator {
  const LeaderRideStatusCalculator({
    this.maximumOnRouteDistanceMeters = 250,
    this.staleAfter = const Duration(minutes: 2),
    this.leaderTrackCorridorMeters = 120,
  });

  final double maximumOnRouteDistanceMeters;
  final Duration staleAfter;

  /// Corridor around the leader's own recorded track inside which a rider is
  /// following the leader rather than off course. See [LeaderTrackExemption].
  final double leaderTrackCorridorMeters;

  /// [leaderTrail] is the leader's own recorded track. A rider inside its
  /// corridor is following the leader and is never counted as off course, even
  /// if a deviation alert for them arrived from a device that had not yet seen
  /// the leader leave the GPX.
  LeaderRideStatus? calculate({
    required RideRole localRole,
    required String localRiderId,
    required List<RiderLocation> riderLocations,
    required List<RiderRouteAlert> routeAlerts,
    required List<GeoPoint> route,
    List<GeoPoint> leaderTrail = const [],
    DateTime? now,
  }) {
    if (localRole != RideRole.lead) return null;
    final currentRiderIds = riderLocations
        .map((location) => location.riderId)
        .toSet();
    final locationsById = {
      for (final location in riderLocations) location.riderId: location,
    };
    final currentOffCourseAlerts = <String, RiderRouteAlert>{};
    for (final alert in routeAlerts) {
      if (alert.riderId == localRiderId ||
          !currentRiderIds.contains(alert.riderId) ||
          alert.acknowledged ||
          alert.assessment.state != RouteTrackingState.offRoute ||
          !alert.assessment.coordinatorActionRequired) {
        continue;
      }
      final location = locationsById[alert.riderId];
      if (location != null &&
          LeaderTrackExemption.isFollowingLeaderTrack(
            position: location.sample.position,
            accuracyMeters: location.sample.accuracyMeters,
            leaderTrack: leaderTrail,
            corridorMeters: leaderTrackCorridorMeters,
          )) {
        continue;
      }
      final previous = currentOffCourseAlerts[alert.riderId];
      if (previous == null ||
          alert.assessment.evaluatedAt.isAfter(
            previous.assessment.evaluatedAt,
          )) {
        currentOffCourseAlerts[alert.riderId] = alert;
      }
    }
    final offCourseAlerts =
        currentOffCourseAlerts.values
            .map(
              (alert) => LeaderOffCourseAlert(
                riderId: alert.riderId,
                displayName: alert.displayName,
                level: alert.assessment.alertLevel,
                distanceFromRouteMeters:
                    alert.assessment.distanceFromRouteMeters,
              ),
            )
            .toList(growable: false)
          ..sort((first, second) {
            final byLevel = second.level.index.compareTo(first.level.index);
            return byLevel != 0
                ? byLevel
                : first.displayName.compareTo(second.displayName);
          });

    return LeaderRideStatus(offCourseAlerts: offCourseAlerts);
  }
}
