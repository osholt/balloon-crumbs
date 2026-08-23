import '../domain/craft.dart';
import '../domain/ride_event.dart';
import '../domain/rider_location.dart';
import 'craft_telemetry_election.dart';

/// One craft, its crew, and the single position it reports.
class CraftState {
  const CraftState({
    required this.craft,
    required this.deviceIds,
    required this.fix,
    this.primaryDeviceId,
  });

  final Craft craft;

  /// Every device aboard, whether or not its fix won the election. Three crew in
  /// a basket is worth showing even though one phone publishes the position.
  final List<String> deviceIds;

  /// The craft's elected position, or a stated reason there is none.
  final CraftFix fix;

  /// The device the pilot nominated to report for this craft, if any.
  final String? primaryDeviceId;

  String get id => craft.id;
  bool get isBalloon => craft.isBalloon;
  int get crewCount => deviceIds.length;
}

/// Every craft in a ride, reconciled from the journal.
///
/// Replaces the inherited flat rider list. Callers ask for a craft and get one
/// position, however many phones are aboard it.
class CraftRoster {
  const CraftRoster({required this.crafts, required this.evaluatedAt});

  final List<CraftState> crafts;
  final DateTime evaluatedAt;

  /// Balloons as a list, not a single field.
  ///
  /// One balloon is a cardinality the UI enforces, not an assumption the read
  /// model bakes in — which is what keeps a multi-balloon event (backlog 22, 23)
  /// from needing this re-cut. Callers wanting "the balloon" should use
  /// [balloon] and handle null; callers that will one day handle several should
  /// iterate this.
  Iterable<CraftState> get balloons => crafts.where((c) => c.isBalloon);

  /// The single balloon, while there is only one. Null if none has registered.
  CraftState? get balloon => balloons.firstOrNull;

  Iterable<CraftState> get vehicles => crafts.where((c) => !c.isBalloon);

  CraftState? byId(String craftId) =>
      crafts.where((c) => c.id == craftId).firstOrNull;

  /// The craft a device is aboard, if the journal says.
  CraftState? forDevice(String deviceId) =>
      crafts.where((c) => c.deviceIds.contains(deviceId)).firstOrNull;

  /// Vehicles currently chasing [craftId].
  ///
  /// With one balloon, a vehicle with no explicit assignment is treated as
  /// chasing it — otherwise every vehicle would read as unassigned until someone
  /// pressed something, which is a worse default than the obvious one. With
  /// several balloons an unassigned vehicle is genuinely unassigned, and this is
  /// the line that changes.
  Iterable<CraftState> chasing(String craftId) {
    final onlyBalloon = balloons.length == 1 ? balloon!.id : null;
    return vehicles.where(
      (v) =>
          v.craft.chasing == craftId ||
          (v.craft.chasing == null && craftId == onlyBalloon),
    );
  }
}

/// Builds a [CraftRoster] from the durable journal.
///
/// Deterministic and replayable: same events plus same evaluation time gives the
/// same roster on every device, which is what lets two phones agree about where
/// the balloon is without exchanging a word about it.
class CraftRosterReducer {
  const CraftRosterReducer({this.election = const CraftTelemetryElection()});

  final CraftTelemetryElection election;

  /// [previousReporters] maps craft id to the device that last spoke for it, so
  /// the election's hysteresis has an incumbent to hold onto. Pass the previous
  /// roster's reporters; an empty map simply means no incumbent yet.
  CraftRoster fromEvents({
    required Iterable<RideEvent> events,
    required DateTime now,
    Map<String, String> previousReporters = const {},
  }) {
    final crafts = <String, Craft>{};
    final deviceToCraft = <String, String>{};
    final primaryByCraft = <String, String>{};
    final latestFix = <String, LocationSample>{};

    // Single ordered pass, last write wins. The journal is append-only, so a
    // correction is a later event rather than an edit.
    final ordered = events.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.craftRegistered:
          final craft = _craft(event.payload);
          if (craft != null) crafts[craft.id] = craft;
        case RideEventType.craftChaseAssigned:
          final craftId = event.payload['craftId'];
          final target = event.payload['chasing'];
          if (craftId is! String) break;
          final existing = crafts[craftId];
          // Only a vehicle chases. An assignment naming a balloon is dropped
          // rather than applied: it would trip the Craft constructor and take
          // out the whole roster for every device that replayed it.
          if (existing == null || existing.isBalloon) break;
          crafts[craftId] = existing.copyWith(
            chasing: target is String ? target : null,
            clearChasing: target is! String,
          );
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
          final sample = _sample(event.payload);
          if (sample == null) break;
          final previous = latestFix[event.deviceId];
          // Guard against out-of-order relay delivery: a fix that arrives late
          // must not replace a newer one already seen.
          if (previous == null ||
              sample.recordedAt.isAfter(previous.recordedAt)) {
            latestFix[event.deviceId] = sample;
          }
        // Every other type belongs to another reducer. Listed rather than
        // defaulted so a new event type has to be considered here too.
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.riderLeft:
        case RideEventType.roleChanged:
        case RideEventType.rideStarted:
        case RideEventType.statusMessage:
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

    final devicesByCraft = <String, List<String>>{};
    for (final entry in deviceToCraft.entries) {
      // A device attached to a craft nobody registered is dropped: putting it in
      // a synthetic craft would invent an aircraft on the map.
      if (!crafts.containsKey(entry.value)) continue;
      devicesByCraft.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    final states = <CraftState>[];
    for (final craft in crafts.values) {
      // Copied before sorting: a craft with nobody aboard would otherwise sort
      // the shared const empty list and throw.
      final devices = [...?devicesByCraft[craft.id]]..sort();
      final primary = primaryByCraft[craft.id];
      final candidates = [
        for (final deviceId in devices)
          if (latestFix[deviceId] case final sample?)
            CraftFixCandidate(
              deviceId: deviceId,
              sample: sample,
              isNominatedPrimary: deviceId == primary,
            ),
      ];
      states.add(
        CraftState(
          craft: craft,
          deviceIds: List.unmodifiable(devices),
          primaryDeviceId: primary,
          fix: election.elect(
            candidates: candidates,
            now: now,
            incumbentDeviceId: previousReporters[craft.id],
          ),
        ),
      );
    }

    // Balloons first, then by label: a stable order so the roster does not
    // reshuffle between frames.
    states.sort((a, b) {
      if (a.isBalloon != b.isBalloon) return a.isBalloon ? -1 : 1;
      return a.craft.label.compareTo(b.craft.label);
    });

    return CraftRoster(crafts: List.unmodifiable(states), evaluatedAt: now);
  }

  /// The reporters this roster elected, to feed back as the next call's
  /// incumbents so hysteresis persists across frames.
  static Map<String, String> reportersOf(CraftRoster roster) => {
    for (final craft in roster.crafts) craft.id: ?craft.fix.deviceId,
  };

  static Craft? _craft(Map<String, Object?> payload) {
    final id = payload['craftId'] ?? payload['id'];
    if (id is! String || id.isEmpty) return null;
    final kind = craftKindFromName(payload['kind']);
    final chasing = payload['chasing'];
    return Craft(
      id: id,
      kind: kind,
      label: payload['label'] as String? ?? id,
      chasing: kind == CraftKind.vehicle && chasing is String ? chasing : null,
    );
  }

  static LocationSample? _sample(Map<String, Object?> payload) {
    final raw = payload['sample'];
    if (raw is! Map) return null;
    try {
      return LocationSample.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      // A malformed fix from one peer must not stop the roster reconciling for
      // every other craft.
      return null;
    }
  }
}
