import '../domain/craft.dart';
import '../domain/ride_event.dart';
import '../domain/rider_location.dart';
import 'craft_telemetry_election.dart';
import 'balloon_telemetry_plausibility.dart';

class RejectedCraftTrackSample {
  const RejectedCraftTrackSample({
    required this.sample,
    required this.reason,
    required this.observedRate,
  });

  final LocationSample sample;
  final BalloonTelemetryRejectionReason reason;
  final double observedRate;
}

class CraftTrack {
  const CraftTrack({
    required this.craftId,
    required this.label,
    required this.kind,
    required this.samples,
    this.rejectedSamples = const [],
  });

  final String craftId;
  final String label;
  final CraftKind kind;
  final List<LocationSample> samples;
  final List<RejectedCraftTrackSample> rejectedSamples;

  bool get isBalloon => kind == CraftKind.balloon;
}

/// Reduces device fixes into one deterministic measured track per craft.
///
/// Several phones may report from the same basket or vehicle. Replaying those
/// fixes as separate lines creates movement that did not happen, so the same
/// election used for the current craft fix is replayed through measurement
/// time. Out-of-order and duplicate fixes cannot regress the result.
class CraftTrackReducer {
  const CraftTrackReducer({
    this.election = const CraftTelemetryElection(),
    this.plausibility = const BalloonTelemetryPlausibilityPolicy(),
  });

  final CraftTelemetryElection election;
  final BalloonTelemetryPlausibilityPolicy plausibility;

  List<CraftTrack> fromEvents(Iterable<RideEvent> events) {
    final crafts = <String, Craft>{};
    final deviceToCraft = <String, String>{};
    final primaryByCraft = <String, String>{};
    final candidatesByCraft = <String, List<_TimedCandidate>>{};
    final ordered = events.toList()
      ..sort((first, second) {
        final byTime = first.createdAt.compareTo(second.createdAt);
        return byTime != 0 ? byTime : first.id.compareTo(second.id);
      });

    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.craftRegistered:
          final craft = _craft(event.payload);
          if (craft != null) crafts[craft.id] = craft;
        case RideEventType.deviceAttachedToCraft:
          final deviceId = event.payload['deviceId'];
          final craftId = event.payload['craftId'];
          if (deviceId is String && craftId is String) {
            deviceToCraft[deviceId] = craftId;
          }
        case RideEventType.craftPrimaryDeviceNominated:
          final craftId = event.payload['craftId'];
          final deviceId = event.payload['deviceId'];
          if (craftId is String && deviceId is String) {
            primaryByCraft[craftId] = deviceId;
          }
        case RideEventType.riderLocationUpdated:
          final craftId = deviceToCraft[event.deviceId];
          final sample = _sample(event.payload);
          if (craftId == null || sample == null) break;
          candidatesByCraft
              .putIfAbsent(craftId, () => [])
              .add(
                _TimedCandidate(
                  deviceId: event.deviceId,
                  sample: sample,
                  isNominatedPrimary: primaryByCraft[craftId] == event.deviceId,
                  eventId: event.id,
                ),
              );
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.riderLeft:
        case RideEventType.roleChanged:
        case RideEventType.rideStarted:
        case RideEventType.flightStartedByCrew:
        case RideEventType.flightLanded:
        case RideEventType.flightLandingRetracted:
        case RideEventType.statusMessage:
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

    final tracks = <CraftTrack>[];
    for (final craft in crafts.values) {
      final candidates = [...?candidatesByCraft[craft.id]]
        ..sort((first, second) {
          final byMeasurement = first.sample.recordedAt.compareTo(
            second.sample.recordedAt,
          );
          return byMeasurement != 0
              ? byMeasurement
              : first.eventId.compareTo(second.eventId);
        });
      final latestByDevice = <String, _TimedCandidate>{};
      final samples = <LocationSample>[];
      final rejectedSamples = <RejectedCraftTrackSample>[];
      String? incumbentDeviceId;
      for (final candidate in candidates) {
        final previous = latestByDevice[candidate.deviceId];
        if (previous != null &&
            !candidate.sample.recordedAt.isAfter(previous.sample.recordedAt)) {
          continue;
        }
        latestByDevice[candidate.deviceId] = candidate;
        final fix = election.elect(
          candidates: [
            for (final current in latestByDevice.values)
              CraftFixCandidate(
                deviceId: current.deviceId,
                sample: current.sample,
                isNominatedPrimary: current.isNominatedPrimary,
              ),
          ],
          now: candidate.sample.recordedAt,
          incumbentDeviceId: incumbentDeviceId,
        );
        final elected = fix.sample;
        if (elected == null) continue;
        incumbentDeviceId = fix.deviceId;
        if (samples.isNotEmpty &&
            !elected.recordedAt.isAfter(samples.last.recordedAt)) {
          continue;
        }
        if (craft.isBalloon && samples.isNotEmpty) {
          final decision = plausibility.assess(
            previous: samples.last,
            candidate: elected,
          );
          if (!decision.accepted) {
            rejectedSamples.add(
              RejectedCraftTrackSample(
                sample: elected,
                reason: decision.rejectionReason!,
                observedRate: decision.observedRate!,
              ),
            );
            continue;
          }
        }
        samples.add(elected);
      }
      tracks.add(
        CraftTrack(
          craftId: craft.id,
          label: craft.label,
          kind: craft.kind,
          samples: List.unmodifiable(samples),
          rejectedSamples: List.unmodifiable(rejectedSamples),
        ),
      );
    }
    tracks.sort((first, second) {
      if (first.isBalloon != second.isBalloon) {
        return first.isBalloon ? -1 : 1;
      }
      return first.label.compareTo(second.label);
    });
    return List.unmodifiable(tracks);
  }

  static Craft? _craft(Map<String, Object?> payload) {
    final id = payload['craftId'] ?? payload['id'];
    if (id is! String || id.isEmpty) return null;
    final kind = craftKindFromName(payload['kind']);
    final requestedStyle = craftIconStyleFromName(
      payload['craftStyle'] as String?,
    );
    return Craft(
      id: id,
      kind: kind,
      label: payload['label'] as String? ?? id,
      iconStyle: requestedStyle.kind == kind
          ? requestedStyle
          : defaultCraftIconStyleFor(kind),
    );
  }

  static LocationSample? _sample(Map<String, Object?> payload) {
    final raw = payload['sample'];
    if (raw is! Map) return null;
    try {
      return LocationSample.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      return null;
    }
  }
}

class _TimedCandidate {
  const _TimedCandidate({
    required this.deviceId,
    required this.sample,
    required this.isNominatedPrimary,
    required this.eventId,
  });

  final String deviceId;
  final LocationSample sample;
  final bool isNominatedPrimary;
  final String eventId;
}
