import 'flight_role.dart';
import 'ride_event.dart';
import 'rider_location.dart';
import '../services/ride_event_authenticator.dart';
import '../services/ride_lifecycle.dart';

enum FlightLandingEvidence { aboard, witnessed, radioConfirmed, manuallyMarked }

extension FlightLandingEvidenceLabel on FlightLandingEvidence {
  String get label => switch (this) {
    FlightLandingEvidence.aboard => 'Device in balloon',
    FlightLandingEvidence.witnessed => 'Witnessed by ground crew',
    FlightLandingEvidence.radioConfirmed => 'Confirmed over radio',
    FlightLandingEvidence.manuallyMarked => 'Manually marked location',
  };
}

FlightLandingEvidence? flightLandingEvidenceFromName(Object? value) =>
    value is String
    ? FlightLandingEvidence.values
          .where((evidence) => evidence.name == value)
          .firstOrNull
    : null;

enum FlightLandingLocationConfidence { confirmed, manuallyMarked, bestKnown }

extension FlightLandingLocationConfidenceLabel
    on FlightLandingLocationConfidence {
  String get label => switch (this) {
    FlightLandingLocationConfidence.confirmed => 'Confirmed balloon fix',
    FlightLandingLocationConfidence.manuallyMarked =>
      'Crew-marked landing point',
    FlightLandingLocationConfidence.bestKnown => 'Best-known balloon position',
  };
}

class FlightLanding {
  const FlightLanding({
    required this.eventId,
    required this.declaredAt,
    required this.declaredByDeviceId,
    required this.declaredByDisplayName,
    required this.declaredByRole,
    required this.evidence,
    this.location,
    this.locationConfidence,
  });

  final String eventId;
  final DateTime declaredAt;
  final String declaredByDeviceId;
  final String declaredByDisplayName;
  final FlightRole declaredByRole;
  final FlightLandingEvidence evidence;
  final LocationSample? location;
  final FlightLandingLocationConfidence? locationConfidence;

  bool get hasConfirmedLocation =>
      locationConfidence == FlightLandingLocationConfidence.confirmed ||
      locationConfidence == FlightLandingLocationConfidence.manuallyMarked;
}

class FlightLandingState {
  const FlightLandingState({this.landing, this.retractedAt});

  final FlightLanding? landing;
  final DateTime? retractedAt;

  bool get isLanded => landing != null;
}

/// Reconstructs the latest valid landing declaration from the signed journal.
///
/// Only an operational role may declare or retract landing. Retractions name
/// the exact declaration they undo, so delayed/offline delivery cannot erase a
/// newer declaration merely because its clock sorts later.
class FlightLandingReducer {
  const FlightLandingReducer({
    this.maximumConfirmedFixAge = const Duration(seconds: 45),
    this.maximumConfirmedAccuracyMeters = 100,
  });

  final Duration maximumConfirmedFixAge;
  final double maximumConfirmedAccuracyMeters;

  FlightLandingState fromEvents({
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
          ..sort(RideLifecycleReducer.compareEvents);
    final roles = <String, FlightRole>{};
    FlightLanding? landing;
    DateTime? retractedAt;

    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.roleChanged:
          final role = _role(event.payload['flightRole']);
          if (role != null) roles[event.deviceId] = role;
        case RideEventType.flightLanded:
          final role = roles[event.deviceId];
          final parsed = role == null || role == FlightRole.observer
              ? null
              : _landing(event, role);
          if (parsed != null) {
            landing = parsed;
            retractedAt = null;
          }
        case RideEventType.flightLandingRetracted:
          final role = roles[event.deviceId];
          if (role == null ||
              role == FlightRole.observer ||
              event.payload['landingEventId'] != landing?.eventId) {
            break;
          }
          landing = null;
          retractedAt = event.createdAt;
        default:
          break;
      }
    }
    return FlightLandingState(landing: landing, retractedAt: retractedAt);
  }

  FlightLanding? _landing(RideEvent event, FlightRole role) {
    final evidence = flightLandingEvidenceFromName(event.payload['evidence']);
    if (evidence == null ||
        event.payload['declaredByDeviceId'] != event.deviceId) {
      return null;
    }
    final rawLocation = event.payload['location'];
    LocationSample? location;
    if (rawLocation is Map<Object?, Object?>) {
      try {
        location = LocationSample.fromJson(
          Map<String, Object?>.from(rawLocation),
        );
      } on Object {
        return null;
      }
    } else if (rawLocation != null) {
      return null;
    }

    final confidence = _confidence(
      evidence: evidence,
      role: role,
      event: event,
      location: location,
    );
    final displayName = event.payload['declaredByDisplayName'];
    return FlightLanding(
      eventId: event.id,
      declaredAt: event.createdAt,
      declaredByDeviceId: event.deviceId,
      declaredByDisplayName: displayName is String && displayName.isNotEmpty
          ? displayName
          : 'Crew member',
      declaredByRole: role,
      evidence: evidence,
      location: location,
      locationConfidence: location == null ? null : confidence,
    );
  }

  FlightLandingLocationConfidence _confidence({
    required FlightLandingEvidence evidence,
    required FlightRole role,
    required RideEvent event,
    required LocationSample? location,
  }) {
    if (evidence == FlightLandingEvidence.manuallyMarked) {
      return FlightLandingLocationConfidence.manuallyMarked;
    }
    if (location != null &&
        evidence == FlightLandingEvidence.aboard &&
        role.isAboardBalloon &&
        location.ageAt(event.createdAt) <= maximumConfirmedFixAge &&
        location.accuracyMeters <= maximumConfirmedAccuracyMeters) {
      return FlightLandingLocationConfidence.confirmed;
    }
    return FlightLandingLocationConfidence.bestKnown;
  }

  static FlightRole? _role(Object? value) {
    if (value is! String) return null;
    return FlightRole.values.where((role) => role.name == value).firstOrNull;
  }
}
