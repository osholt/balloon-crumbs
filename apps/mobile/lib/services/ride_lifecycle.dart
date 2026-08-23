import '../domain/ride_event.dart';
import '../domain/flight_role.dart';
import '../domain/ride_role.dart';
import 'ride_event_authenticator.dart';

enum RidePhase { open, started, ended }

class RideLifecycle {
  const RideLifecycle({this.startEvent});

  final RideEvent? startEvent;

  bool get started => startEvent != null;
  DateTime? get startedAt => startEvent?.createdAt;
}

/// Reconstructs the authoritative ride start from the signed event journal.
///
/// Events are ordered by timestamp and then ID so every device chooses the
/// same start after offline delivery, retries, or duplicate start taps. A
/// legacy pilot start is accepted only from a rider whose latest signed role at
/// that point is lead. The additive ground-crew start is accepted only when the
/// same journal already identifies its author as chase driver or chase crew.
class RideLifecycleReducer {
  const RideLifecycleReducer._();

  static RideLifecycle fromEvents({
    required String rideId,
    required String inviteSecret,
    required Iterable<RideEvent> events,
  }) {
    final ordered =
        events
            .where(
              (event) =>
                  event.rideId == rideId &&
                  RideEventAuthenticator.verify(event, inviteSecret),
            )
            .toList(growable: false)
          ..sort(compareEvents);
    final roles = <String, RideRole>{};
    final flightRoles = <String, FlightRole>{};
    final vehicleCraftIds = <String>{};
    final craftByDevice = <String, String>{};

    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.roleChanged:
          final role = _roleFromPayload(event.payload['role']);
          if (role != null) roles[event.deviceId] = role;
          final flightRole = _flightRoleFromPayload(
            event.payload['flightRole'],
          );
          if (flightRole != null) flightRoles[event.deviceId] = flightRole;
          break;
        case RideEventType.rideStarted:
          if (roles[event.deviceId] == RideRole.lead &&
              event.payload['leaderRiderId'] == event.deviceId) {
            return RideLifecycle(startEvent: event);
          }
        case RideEventType.flightStartedByCrew:
          final recordedRole = flightRoles[event.deviceId];
          if (recordedRole != null &&
              recordedRole.isChasing &&
              vehicleCraftIds.contains(craftByDevice[event.deviceId]) &&
              event.payload['crewRiderId'] == event.deviceId &&
              event.payload['flightRole'] == recordedRole.name) {
            return RideLifecycle(startEvent: event);
          }
        case RideEventType.craftRegistered:
          final craftId = event.payload['craftId'];
          if (craftId is String && event.payload['kind'] == 'vehicle') {
            vehicleCraftIds.add(craftId);
          }
        case RideEventType.deviceAttachedToCraft:
          final deviceId = event.payload['deviceId'];
          final craftId = event.payload['craftId'];
          if (deviceId is String && craftId is String) {
            craftByDevice[deviceId] = craftId;
          }
        case RideEventType.riderLeft:
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
        case RideEventType.rideReopened:
        case RideEventType.iceInfoShared:
        case RideEventType.iceInfoViewed:
        case RideEventType.riderContactShared:
        case RideEventType.craftPrimaryDeviceNominated:
        case RideEventType.craftChaseAssigned:
        case RideEventType.landingAreaNoted:
        case RideEventType.windContextNoted:
        case RideEventType.operationalBoundaryUpserted:
        case RideEventType.operationalBoundaryRemoved:
        case RideEventType.chaseGuidanceTargetSelected:
        case RideEventType.pilotHandoverOffered:
        case RideEventType.pilotHandoverAccepted:
          break;
      }
    }
    return const RideLifecycle();
  }

  static int compareEvents(RideEvent left, RideEvent right) {
    final byTime = left.createdAt.compareTo(right.createdAt);
    return byTime != 0 ? byTime : left.id.compareTo(right.id);
  }

  static RideRole? _roleFromPayload(Object? value) {
    if (value is! String) return null;
    try {
      return RideRole.values.byName(value);
    } on ArgumentError {
      return null;
    }
  }

  static FlightRole? _flightRoleFromPayload(Object? value) {
    if (value is! String) return null;
    try {
      return FlightRole.values.byName(value);
    } on ArgumentError {
      return null;
    }
  }
}
