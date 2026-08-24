import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/event_store.dart';
import '../domain/geo_point.dart';
import '../domain/hazard.dart';
import '../domain/ride_event.dart';
import '../domain/ride_role.dart';
import '../domain/ride_session.dart';
import '../domain/rider_location.dart';
import '../relay/live_presence.dart';
import '../services/external_hazard_provider.dart';
import '../services/hazard_deduplicator.dart';
import '../services/ride_event_authenticator.dart';
import '../services/situation_event_factory.dart';

typedef AuthenticatedSituationEventFactory =
    Future<RideEvent> Function({
      required RideEventType type,
      required Map<String, Object?> payload,
      EventPriority priority,
      DateTime? expiresAt,
    });

class SituationalAwarenessController extends ChangeNotifier {
  SituationalAwarenessController(
    this._eventStore,
    this._session, {
    required List<GeoPoint> route,
    List<ExternalHazardProvider> externalProviders = const [],
    SituationClock? clock,
    SituationIdFactory? idFactory,
    bool rideStarted = true,
    DateTime? rideStartedAt,
    bool rideEnded = false,
    this.expiryPolicy = const HazardExpiryPolicy(),
    this.deduplicator = const HazardDeduplicator(),
    this.freshnessPolicy = const PresenceFreshnessPolicy(),
    this.onEventStored,
    this.authenticatedEventFactory,
  }) : _route = List.unmodifiable(route),
       _externalProviders = List.unmodifiable(externalProviders),
       _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? const Uuid().v7 {
    _rideStarted = rideStarted;
    _rideStartedAt = rideStartedAt;
    _rideEnded = rideEnded;
    _eventFactory = SituationEventFactory(
      session: _session,
      clock: _clock,
      idFactory: _idFactory,
    );
  }

  final EventStore _eventStore;
  RideSession _session;
  final List<GeoPoint> _route;
  final List<ExternalHazardProvider> _externalProviders;
  final SituationClock _clock;
  final SituationIdFactory _idFactory;
  late bool _rideStarted;
  late DateTime? _rideStartedAt;
  late bool _rideEnded;
  bool get rideStarted => _rideStarted;
  DateTime? get rideStartedAt => _rideStartedAt;
  bool get rideEnded => _rideEnded;
  final HazardExpiryPolicy expiryPolicy;
  final HazardDeduplicator deduplicator;

  /// Documented age thresholds shared with the ephemeral presence channels, so
  /// the journal side and the presence side cannot disagree about whether a
  /// position is live, ageing or stale.
  final PresenceFreshnessPolicy freshnessPolicy;

  /// Receives an event after this controller has durably stored and applied it.
  ///
  /// The ride shell uses this to update the shared in-memory journal one event
  /// at a time instead of re-reading the complete SQLite ride after every
  /// position fix (#165).
  final ValueChanged<RideEvent>? onEventStored;
  final AuthenticatedSituationEventFactory? authenticatedEventFactory;
  late SituationEventFactory _eventFactory;

  final Map<String, RiderLocation> _locations = {};
  final Map<String, RiderLocationEvidence> _locationEvidence = {};
  final Map<String, HazardReport> _hazards = {};
  // Keep the complete fix here. Reducing this to position plus timestamp threw
  // away the balloon altitude before the map could colour or describe its
  // ground track.
  final List<LocationSample> _leaderTrail = [];
  bool _busy = false;
  bool _refreshingStaleness = false;
  bool _disposed = false;
  String? _errorMessage;

  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  List<GeoPoint> get route => _route;

  /// The current ride leader's own recorded path so far - the group's live
  /// ground truth when the planned line stops matching the road.
  List<GeoPoint> get leaderTrail => _leaderTrailPoints;

  /// The same durable leader trail with its fix times retained, so map
  /// rendering can break an unknown interval instead of inventing a straight
  /// line across it (#205).
  List<({DateTime recordedAt, GeoPoint position})> get leaderTrailSamples =>
      _leaderTrailSamplesCache ??= List.unmodifiable([
        for (final sample in _leaderTrail)
          (recordedAt: sample.recordedAt, position: sample.position),
      ]);

  /// Complete balloon/leader fixes for telemetry-aware map surfaces.
  ///
  /// The compatibility getters above intentionally remain position-only for
  /// route-alert callers. This is the path that retains altitude source, datum,
  /// accuracy and vertical speed for the balloon ground track.
  List<LocationSample> get leaderLocationSamples =>
      _leaderLocationSamplesCache ??= List.unmodifiable(_leaderTrail);

  List<RiderLocation> get riderLocations {
    final values = _locations.values.toList(growable: false);
    values.sort(
      (first, second) => first.displayName.compareTo(second.displayName),
    );
    return List.unmodifiable(values);
  }

  /// The journal's contribution to the reconciled live-position model.
  ///
  /// This controller owns the durable side only. Callers merge it with the
  /// ephemeral presence channels through [LivePresenceReconciler] so one model
  /// spans both ride phases and both transports; doing the merge here would
  /// make an ephemeral snapshot look like ride history.
  List<LiveRiderPresence> livePresenceAt(DateTime now) =>
      LivePresenceReconciler(policy: freshnessPolicy).reconcile(
        now: now,
        localRiderId: _session.localRiderId,
        journal: _locations.values,
      );

  List<HazardReport> get activeHazards {
    final now = _clock();
    final values = _hazards.values
        .where((hazard) => hazard.isActiveAt(now))
        .toList();
    values.sort((first, second) {
      final bySeverity = second.severity.index.compareTo(first.severity.index);
      return bySeverity != 0
          ? bySeverity
          : second.updatedAt.compareTo(first.updatedAt);
    });
    return List.unmodifiable(values);
  }

  List<ExternalHazardProvider> get externalProviders => _externalProviders;

  RiderLocation? get localLocation => _locations[_session.localRiderId];

  List<RiderLocationEvidence> get authenticatedLocationEvidence =>
      List.unmodifiable(
        _locationEvidence.values.where((evidence) => evidence.authenticated),
      );

  RiderLocationEvidence? locationEvidenceFor(String riderId) =>
      _locationEvidence[riderId];

  void updateLocalSession(RideSession session) {
    if (session.rideId != _session.rideId ||
        session.localRiderId != _session.localRiderId) {
      throw ArgumentError(
        'Cannot replace awareness with another flight session',
      );
    }
    _session = session;
    _eventFactory = SituationEventFactory(
      session: session,
      clock: _clock,
      idFactory: _idFactory,
    );
  }

  /// Keeps the durable position journal aligned with the shared flight phase.
  ///
  /// The native location stream is stopped when a flight ends, but a fix may
  /// already be queued. Gating again at the journal boundary prevents that late
  /// callback from creating post-flight location history.
  void updateFlightLifecycle({
    required bool started,
    required bool ended,
    DateTime? startedAt,
  }) {
    _rideStarted = started;
    _rideEnded = ended;
    _rideStartedAt = startedAt;
  }

  Future<void> initialize({Iterable<RideEvent>? restoredEvents}) async {
    if (_disposed) return;
    final events =
        restoredEvents ?? await _eventStore.eventsForRide(_session.rideId);
    var replayed = 0;
    for (final event in events) {
      _applyEvent(event, replaying: true);
      replayed += 1;
      // A restored group ride can contain tens of thousands of positions. The
      // reducer remains ordered, but yields between bounded batches so Android
      // can draw and respond while the journal is projected into map state
      // (#209).
      if (replayed % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (_disposed) return;
      }
    }
    _removeExpiredHazards();
    if (!_disposed) notifyListeners();
  }

  Future<void> recordLocalLocation(LocationSample sample) async {
    if (!_rideStarted ||
        _rideEnded ||
        (_rideStartedAt != null &&
            sample.recordedAt.isBefore(_rideStartedAt!))) {
      return;
    }
    final location = RiderLocation(
      riderId: _session.localRiderId,
      displayName: _session.displayName,
      role: _session.role,
      sample: sample,
      receivedAt: _clock(),
      craftStyle: _session.craftStyle,
      riderSymbol: _session.riderSymbol,
      riderColor: _session.riderColor,
    );
    await _run(() async {
      await _appendAndApply(
        await _createEvent(
          type: RideEventType.riderLocationUpdated,
          payload: {'location': location.toJson()},
          expiresAt: _clock().add(const Duration(minutes: 30)),
        ),
      );
    });
  }

  Future<HazardReport?> reportHazard({
    required HazardType type,
    required HazardSeverity severity,
    GeoPoint? position,
    String? details,
  }) async {
    if (!type.isRiderReportable) {
      throw const FormatException('That hazard type cannot be reported.');
    }
    HazardReport? result;
    await _run(() async {
      final reportPosition = position ?? localLocation?.sample.position;
      if (reportPosition == null) {
        throw const FormatException(
          'A current location is required to report a hazard.',
        );
      }
      final now = _clock();
      final trimmedDetails = details?.trim();
      final incoming = HazardReport(
        id: _idFactory(),
        rideId: _session.rideId,
        type: type,
        severity: severity,
        position: reportPosition,
        reportedAt: now,
        updatedAt: now,
        expiresAt: now.add(expiryPolicy.durationFor(type, severity)),
        reporterId: _session.localRiderId,
        reporterName: _session.displayName,
        source: HazardSource.rider,
        details: trimmedDetails == null || trimmedDetails.isEmpty
            ? null
            : trimmedDetails.substring(
                0,
                trimmedDetails.length > 160 ? 160 : trimmedDetails.length,
              ),
      );
      result = deduplicator.mergeOrAdd(incoming, activeHazards);
      final event = await _createEvent(
        type: RideEventType.hazardReported,
        payload: {'hazard': result!.toJson()},
        priority: _priorityForSeverity(result!.severity),
        expiresAt: result!.expiresAt,
      );
      await _appendAndApply(event);
    });
    return result;
  }

  Future<void> clearHazard(String hazardId, {String reason = 'cleared'}) async {
    if (!_hazards.containsKey(hazardId)) {
      return;
    }
    await _run(() async {
      final event = await _createEvent(
        type: RideEventType.hazardCleared,
        payload: {'hazardId': hazardId, 'reason': reason},
        priority: EventPriority.important,
      );
      await _appendAndApply(event);
    });
  }

  Future<void> ingestRemoteEvent(RideEvent event) async {
    if (_disposed) return;
    if (event.rideId != _session.rideId ||
        !_supportedSituationalEventTypes.contains(event.type)) {
      throw const FormatException('Event is not valid for this flight.');
    }
    if (!await RideEventAuthenticator.verifyAsync(
      event,
      _session.inviteSecret,
    )) {
      throw const FormatException('Event signature is invalid.');
    }
    await _eventStore.append(event);
    if (_disposed) return;
    _applyEvent(event);
    onEventStored?.call(event);
    notifyListeners();
  }

  Future<void> refreshExternalHazards() async {
    if (_route.isEmpty) {
      return;
    }
    await _run(() async {
      for (final provider in _externalProviders) {
        if (!provider.status.canFetch) {
          continue;
        }
        final result = await provider.fetch(
          ExternalHazardQuery(
            rideId: _session.rideId,
            route: _route,
            requestedAt: _clock(),
          ),
        );
        for (final hazard in result.hazards) {
          if (hazard.source != HazardSource.externalProvider ||
              hazard.providerId != provider.id ||
              hazard.rideId != _session.rideId) {
            continue;
          }
          final existingProviderIncident = _hazards[hazard.id];
          final merged =
              existingProviderIncident?.source ==
                      HazardSource.externalProvider &&
                  existingProviderIncident?.providerId == provider.id
              ? hazard
              : deduplicator.mergeOrAdd(hazard, activeHazards);
          final event = await _createEvent(
            type: RideEventType.hazardReported,
            payload: {'hazard': merged.toJson()},
            priority: _priorityForSeverity(merged.severity),
            expiresAt: merged.expiresAt,
          );
          await _appendAndApply(event);
        }
      }
    });
  }

  Future<void> refreshStaleness() async {
    if (_disposed || _refreshingStaleness) return;
    _refreshingStaleness = true;
    try {
      _removeExpiredHazards();
      if (!_disposed) notifyListeners();
    } finally {
      _refreshingStaleness = false;
    }
  }

  void clearError() {
    if (_disposed) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _appendAndApply(RideEvent event) async {
    await _eventStore.append(event);
    if (_disposed) return;
    _applyEvent(event);
    onEventStored?.call(event);
  }

  Future<RideEvent> _createEvent({
    required RideEventType type,
    required Map<String, Object?> payload,
    EventPriority priority = EventPriority.routine,
    DateTime? expiresAt,
  }) {
    final authenticated = authenticatedEventFactory;
    if (authenticated != null) {
      return authenticated(
        type: type,
        payload: payload,
        priority: priority,
        expiresAt: expiresAt,
      );
    }
    return Future.value(
      _eventFactory.create(
        type: type,
        payload: payload,
        priority: priority,
        expiresAt: expiresAt,
      ),
    );
  }

  void _applyEvent(RideEvent event, {bool replaying = false}) {
    if (event.rideId != _session.rideId) {
      return;
    }
    if (_isRideActivityEvent(event.type) && !_isWithinRideActivity(event)) {
      return;
    }
    switch (event.type) {
      case RideEventType.riderLocationUpdated:
        final location = RiderLocation.fromJson(
          _mapPayload(event.payload['location']),
        );
        if (rideStartedAt != null &&
            location.sample.recordedAt.isBefore(rideStartedAt!)) {
          break;
        }
        final previous = _locations[location.riderId];
        if (previous == null ||
            !location.sample.recordedAt.isBefore(previous.sample.recordedAt)) {
          _locations[location.riderId] = location;
          _locationEvidence[location.riderId] = RiderLocationEvidence(
            location: location,
            eventId: event.id,
            eventCreatedAt: event.createdAt,
            authenticated:
                event.deviceId == location.riderId &&
                SituationEventFactory.verify(event, _session.inviteSecret),
          );
          _evaluateLocation(location);
        }
        break;
      case RideEventType.hazardReported:
        final hazard = HazardReport.fromJson(
          _mapPayload(event.payload['hazard']),
        );
        if (hazard.rideId == _session.rideId && hazard.isActiveAt(_clock())) {
          _hazards[hazard.id] = hazard;
        }
        break;
      case RideEventType.hazardCleared:
        _hazards.remove(event.payload['hazardId']);
        break;
      case RideEventType.routeRevisionChunk:
      case RideEventType.routeRevisionPublished:
      case RideEventType.routeCleared:
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
      case RideEventType.ridePaused:
      case RideEventType.rideResumed:
      case RideEventType.rideEnded:
      case RideEventType.rideReopened:
      case RideEventType.iceInfoShared:
      case RideEventType.iceInfoViewed:
      // Shared rider contact details are reconciled by their own reducer from
      // the durable journal, not by this controller. Listed rather than
      // defaulted so a future event type still has to be considered here.
      case RideEventType.riderContactShared:
      case RideEventType.craftRegistered:
      case RideEventType.deviceAttachedToCraft:
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
    if (!replaying) {
      _removeExpiredHazards();
    }
  }

  bool _isWithinRideActivity(RideEvent event) {
    if (!rideStarted) return false;
    final startedAt = rideStartedAt;
    return startedAt == null || !event.createdAt.isBefore(startedAt);
  }

  static bool _isRideActivityEvent(RideEventType type) =>
      type == RideEventType.riderLocationUpdated;

  void _evaluateLocation(RiderLocation location) {
    if (location.role == RideRole.lead) {
      _recordLeaderTrailPoint(location.sample);
    }
  }

  /// Inserts in chronological order (by [LocationSample.recordedAt], not
  /// arrival order) since relayed and replayed events are not guaranteed to
  /// arrive in the order they were recorded. Duplicate/older-or-equal
  /// timestamps are dropped rather than reordering an already-recorded point.
  void _recordLeaderTrailPoint(LocationSample sample) {
    var index = _leaderTrail.length;
    while (index > 0 &&
        _leaderTrail[index - 1].recordedAt.isAfter(sample.recordedAt)) {
      index -= 1;
    }
    if (index > 0 &&
        !_leaderTrail[index - 1].recordedAt.isBefore(sample.recordedAt)) {
      return;
    }
    _leaderTrail.insert(index, sample);
    _leaderTrailPointsCache = null;
    _leaderTrailSamplesCache = null;
    _leaderLocationSamplesCache = null;
    // A runaway guard, not a display policy. The trail used to be truncated to
    // a 600-point recent-track limit here, which cost a
    // tester the tail of a 6 h 4 m, 112 mile ride: 600 points is roughly the
    // last 40 minutes, so everything before that was deleted and could never be
    // drawn, exported or recapped again. This bound exists only so a pathological
    // session cannot grow without limit - at one fix per second it is over 27
    // hours, which no ride reaches.
    if (_leaderTrail.length > maximumRetainedTrailPoints) {
      _leaderTrail.removeRange(
        0,
        _leaderTrail.length - maximumRetainedTrailPoints,
      );
    }
  }

  /// Memory backstop for the retained leader trail. Deliberately far above any
  /// real ride; see [_recordLeaderTrailPoint].
  static const maximumRetainedTrailPoints = 100000;

  List<GeoPoint>? _leaderTrailPointsCache;
  List<({DateTime recordedAt, GeoPoint position})>? _leaderTrailSamplesCache;
  List<LocationSample>? _leaderLocationSamplesCache;

  /// Built once per change rather than per read.
  ///
  /// This is what makes retaining the whole trail affordable. The 600-point
  /// truncation was guarding a real cost, but the wrong one: it was not the
  /// renderer, which already simplifies once per change through
  /// `TrailDisplaySimplifier` (#165). It was this projection, which rebuilt the
  /// entire list on every call - and [_applyLeaderFollowExemption] calls it on
  /// every follower position update. Caching it removes the per-update cost
  /// without deleting any history.
  List<GeoPoint> get _leaderTrailPoints => _leaderTrailPointsCache ??=
      List.unmodifiable([for (final sample in _leaderTrail) sample.position]);

  void _removeExpiredHazards() {
    final now = _clock();
    _hazards.removeWhere((_, hazard) => !hazard.isActiveAt(now));
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_disposed || _busy) {
      return;
    }
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } on FormatException catch (error) {
      _errorMessage = error.message;
    } on Object catch (error, stackTrace) {
      _errorMessage = 'Situational awareness could not be updated.';
      if (kDebugMode) {
        debugPrint(
          'Situational awareness failed (${error.runtimeType})\n$stackTrace',
        );
      }
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static Map<String, Object?> _mapPayload(Object? value) =>
      Map<String, Object?>.from(value! as Map);

  static EventPriority _priorityForSeverity(HazardSeverity severity) =>
      switch (severity) {
        HazardSeverity.advisory => EventPriority.routine,
        HazardSeverity.caution ||
        HazardSeverity.serious => EventPriority.important,
        HazardSeverity.critical => EventPriority.critical,
      };

  static const _supportedSituationalEventTypes = {
    RideEventType.riderLocationUpdated,
    RideEventType.hazardReported,
    RideEventType.hazardCleared,
  };
}
