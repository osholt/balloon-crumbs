import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/geo_point.dart';
import '../domain/hazard.dart';
import '../domain/ride_event.dart';
import '../domain/ride_role.dart';
import '../domain/ride_session.dart';
import '../domain/rider_color.dart';
import '../domain/rider_location.dart';
import '../features/map/craft_icon.dart';
import '../services/fiesta_flight_loader.dart';
import '../services/geo_calculations.dart';
import '../services/situation_event_factory.dart';
import 'situational_awareness_controller.dart';

enum RideSimulationState { ready, running, paused, completed }

class SimulatedRiderSnapshot {
  const SimulatedRiderSnapshot({
    required this.id,
    required this.displayName,
    required this.role,
    required this.progress,
    required this.speedMetersPerSecond,
    required this.isLocal,
    required this.isOffRoute,
    required this.position,
    required this.headingDegrees,
    required this.offRouteTrail,
    required this.travelTrail,
    required this.motorcycleStyle,
    required this.riderColor,
    this.riderSymbol = riderSymbolDefault,
  });

  final String id;
  final String displayName;
  final RideRole role;
  final double progress;
  final double speedMetersPerSecond;
  final bool isLocal;
  final bool isOffRoute;
  final GeoPoint position;
  final double headingDegrees;
  final CraftIconStyle motorcycleStyle;
  final RiderSymbol riderSymbol;
  final RiderColor riderColor;

  /// Ephemeral visual trace for the current simulation run. Keeping this out
  /// of the durable awareness history prevents an older demo route from being
  /// connected to the current one after the bundled route changes.
  final List<GeoPoint> offRouteTrail;

  /// Recent on-road positions, used to show the actual path ridden by the
  /// current leader without altering the planned route geometry.
  final List<GeoPoint> travelTrail;
}

/// Drives the production awareness pipeline with synthetic, authenticated GPS
/// fixes. The owning shell deliberately disables internet, nearby and device
/// location services for simulation sessions.
class RideSimulationController extends ChangeNotifier {
  RideSimulationController(
    this._awarenessController, {
    required RideSession session,
    required List<GeoPoint> route,
    BalloonFlight? balloonFlight,
    this.tickInterval = const Duration(milliseconds: 100),
    this.eventInterval = const Duration(seconds: 2),
    this.riderCount = RideSession.defaultSimulationRiderCount,
    bool rideStarted = true,
  }) : assert(session.isSimulation),
       assert(route.length >= 2),
       assert(
         riderCount >= RideSession.minimumSimulationRiderCount &&
             riderCount <= RideSession.maximumSimulationRiderCount,
       ),
       _session = session,
       // Keep the public constructor argument usable outside this library.
       // ignore: prefer_initializing_formals
       _rideStarted = rideStarted,
       _routeSampler = _RouteSampler(route),
       // Keep the public constructor argument usable outside this library.
       // ignore: prefer_initializing_formals
       _balloonFlight = balloonFlight,
       _selectedLocalRole = session.role {
    _agents = _buildAgents(_routeSampler.totalDistanceMeters * 0.06);
  }

  /// Ashton Court's field is about 60 m above sea level, and a GNSS fix reports
  /// altitude above the ellipsoid, not above the launch field. The flight
  /// carries height above launch because that is what a pilot flies and what
  /// goes out over the radio, so this is added back to make the fix honest.
  static const _launchElevationMetres = 60.0;

  static const offRouteRiderId = 'ride-lab-alex';
  static const backRiderId = 'ride-lab-charlie';

  final SituationalAwarenessController _awarenessController;
  final RideSession _session;
  final _RouteSampler _routeSampler;

  /// The balloon's own flight, when one is bundled.
  ///
  /// The chase vehicles drive [_routeSampler], a road route, at a road speed.
  /// The balloon does not: it has no steering and no throttle, so it is played
  /// back against the clock from a track that was computed from measured winds.
  /// Advancing it along the road with everyone else was the thing that made the
  /// old demo a group ride with the labels changed.
  ///
  /// Null falls back to that older behaviour, which keeps the focused tests that
  /// only care about group mechanics from having to carry a flight.
  final BalloonFlight? _balloonFlight;
  final Duration tickInterval;
  final Duration eventInterval;
  final int riderCount;
  late final List<_SimulatedAgent> _agents;
  RideRole _selectedLocalRole;
  Timer? _timer;
  RideSimulationState _state = RideSimulationState.ready;
  Duration _simulatedElapsed = Duration.zero;
  double _timeScale = 8;
  double _baseSpeedMetersPerSecond = 13.4;
  bool _backRiderDelayed = false;
  bool _emitting = false;
  bool _rideStarted;
  Duration _eventElapsed = Duration.zero;
  int _eventSequence = 0;
  DateTime? _lastRecordedAt;

  RideSimulationState get state => _state;
  Duration get simulatedElapsed => _simulatedElapsed;
  double get timeScale => _timeScale;
  double get baseSpeedMetersPerSecond => _baseSpeedMetersPerSecond;
  bool get backRiderDelayed => _backRiderDelayed;
  bool get rideStarted => _rideStarted;
  RideRole get localRole => _selectedLocalRole;
  bool get alexOffRoute => _agent(offRouteRiderId).isOffRoute;
  bool get isRunning => _state == RideSimulationState.running;
  double get routeDistanceMeters => _routeSampler.totalDistanceMeters;
  double get progress =>
      (_agents.first.progressMeters / routeDistanceMeters).clamp(0, 1);

  List<SimulatedRiderSnapshot> get riders => List.unmodifiable(
    _agents.map((agent) {
      final sampled = _sampleAgent(agent);
      return SimulatedRiderSnapshot(
        id: agent.id,
        displayName: agent.isLocal ? _localPerspectiveName : agent.displayName,
        role: agent.role,
        progress: (agent.progressMeters / routeDistanceMeters).clamp(0, 1),
        speedMetersPerSecond: _speedFor(agent),
        isLocal: agent.isLocal,
        isOffRoute: agent.isOffRoute,
        position: sampled.position,
        headingDegrees: sampled.headingDegrees,
        offRouteTrail: List.unmodifiable(agent.offRouteTrail),
        travelTrail: List.unmodifiable(_displayTrailFor(agent)),
        motorcycleStyle: agent.motorcycleStyle,
        riderSymbol: agent.riderSymbol,
        riderColor: agent.riderColor,
      );
    }),
  );

  List<_SimulatedAgent> _buildAgents(double leadStart) {
    final trailingSpan = math.min(860, math.max(160, leadStart * 0.82));
    double initialProgress(int index) =>
        math.max(0, leadStart - trailingSpan * index / (riderCount - 1));
    // Cycles through the catalogues so a full Ride Lab group shows a variety
    // of silhouettes and colours without repeating the local rider's own
    // choices. Lead/TEC roles still override to their reserved colour when
    // rendered, so this only ever shows for plain riders.
    CraftIconStyle demoStyleFor(int index) =>
        CraftIconStyle.values[(index + 1) % CraftIconStyle.values.length];
    RiderColor demoColorFor(int index) =>
        RiderColor.values[(index + 1) % RiderColor.values.length];
    _SimulatedAgent rider({
      required String id,
      required String displayName,
      required int index,
      required RideRole role,
      bool isLocal = false,
    }) => _SimulatedAgent(
      id: id,
      displayName: displayName,
      role: role,
      progressMeters: initialProgress(index),
      speedFactor: 1 - (0.2 * index / (riderCount - 1)),
      trafficPhaseSeconds: (3 + index * 12) % 58,
      isLocal: isLocal,
      motorcycleStyle: isLocal ? _session.motorcycleStyle : demoStyleFor(index),
      riderSymbol: isLocal ? _session.riderSymbol : riderSymbolDefault,
      riderColor: isLocal ? _session.riderColor : demoColorFor(index),
    );

    final agents = <_SimulatedAgent>[
      rider(
        id: _session.localRiderId,
        displayName: _session.displayName,
        index: 0,
        role: _selectedLocalRole,
        isLocal: true,
      ),
      rider(
        id: 'ride-lab-maya',
        displayName: 'Maya',
        index: 1,
        role: _selectedLocalRole == RideRole.lead
            ? RideRole.rider
            : RideRole.lead,
      ),
      rider(
        id: offRouteRiderId,
        displayName: 'Alex',
        index: 2,
        role: RideRole.rider,
      ),
    ];
    var nextIndex = 3;
    if (riderCount >= 5) {
      agents.add(
        rider(
          id: 'ride-lab-jordan',
          displayName: 'Jordan',
          index: nextIndex++,
          role: RideRole.rider,
        ),
      );
    }
    var riderNumber = 1;
    while (agents.length < riderCount - 1) {
      agents.add(
        rider(
          id: 'ride-lab-rider-$riderNumber',
          displayName: 'Rider $riderNumber',
          index: nextIndex++,
          role: RideRole.rider,
        ),
      );
      riderNumber += 1;
    }
    agents.add(
      rider(
        id: backRiderId,
        displayName: 'Charlie',
        index: riderCount - 1,
        role: RideRole.rider,
      ),
    );
    return agents;
  }

  List<GeoPoint> _displayTrailFor(_SimulatedAgent agent) {
    if (agent.role != RideRole.lead) return agent.travelTrail;
    final backRider = _agent(backRiderId);
    final routeTrail = _routeSampler.pointsBetween(
      math.min(backRider.progressMeters, agent.progressMeters),
      agent.progressMeters,
    );
    if (!agent.isOffRoute || agent.offRouteTrail.length < 2) {
      return routeTrail;
    }
    // Keep the planned path back to TEC, then show the actual deviation beyond
    // it so the leader trail remains useful during a prolonged off-course run.
    return [...routeTrail, ...agent.offRouteTrail];
  }

  Future<void> initialize() async {
    for (final agent in _agents) {
      _recordTravelTrail(agent);
    }
    await _emitPositions();
  }

  void setRideStarted(bool value) {
    if (_rideStarted == value) return;
    _rideStarted = value;
    if (!value && _state != RideSimulationState.completed) {
      _state = RideSimulationState.ready;
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  void start() {
    if (!_rideStarted || _state == RideSimulationState.completed || isRunning) {
      return;
    }
    _state = RideSimulationState.running;
    _timer ??= Timer.periodic(tickInterval, (_) {
      if (isRunning) unawaited(_tick(tickInterval));
    });
    notifyListeners();
  }

  void pause() {
    if (!isRunning) return;
    _state = RideSimulationState.paused;
    notifyListeners();
  }

  void setTimeScale(double value) {
    final next = value.clamp(1, 16).toDouble();
    if (next == _timeScale) return;
    _timeScale = next;
    notifyListeners();
  }

  void setBaseSpeedMetersPerSecond(double value) {
    final next = value.clamp(4, 25).toDouble();
    if (next == _baseSpeedMetersPerSecond) return;
    _baseSpeedMetersPerSecond = next;
    notifyListeners();
  }

  void setAlexOffRoute(bool value) {
    final alex = _agent(offRouteRiderId);
    if (alex.isOffRoute == value) return;
    alex.isOffRoute = value;
    alex.offRouteTrail.clear();
    if (value) _recordOffRouteTrail(alex);
    notifyListeners();
  }

  void setBackRiderDelayed(bool value) {
    if (_backRiderDelayed == value) return;
    _backRiderDelayed = value;
    notifyListeners();
  }

  void setLocalRole(RideRole role) {
    if (role == _selectedLocalRole) return;
    _selectedLocalRole = role;
    _assignPerspectiveRoles();
    _positionFleetForPerspective();
    for (final agent in _agents) {
      agent.travelTrail.clear();
      _recordTravelTrail(agent);
    }
    notifyListeners();
  }

  Future<void> reportRoadworks() async {
    final lead = _agents.firstWhere(
      (agent) => agent.role == RideRole.lead,
      orElse: () => _agents.first,
    );
    final hazardPoint = _routeSampler
        .sampleAt(math.min(routeDistanceMeters, lead.progressMeters + 450))
        .point;
    await _awarenessController.reportHazard(
      type: HazardType.roadworks,
      severity: HazardSeverity.caution,
      position: hazardPoint,
      details: 'Synthetic Ride Lab hazard',
    );
  }

  Future<void> _tick(Duration realElapsed) async {
    if (_state == RideSimulationState.completed) return;
    _advanceMotion(realElapsed);
    _eventElapsed += realElapsed;
    notifyListeners();
    if (_eventElapsed < eventInterval || _emitting) return;
    _eventElapsed = Duration.zero;
    await _emitPositions();
  }

  /// Advances virtual time and emits one GPS fix per rider. Public so tests and
  /// scripted demos can progress deterministically without waiting for timers.
  Future<void> advance(Duration realElapsed) async {
    if (!_rideStarted || _state == RideSimulationState.completed || _emitting) {
      return;
    }
    _advanceMotion(realElapsed);
    _eventElapsed = Duration.zero;
    await _emitPositions();
    notifyListeners();
  }

  void _advanceMotion(Duration realElapsed) {
    final simulatedMicroseconds = (realElapsed.inMicroseconds * _timeScale)
        .round();
    final simulatedDelta = Duration(microseconds: simulatedMicroseconds);
    _simulatedElapsed += simulatedDelta;
    final seconds =
        simulatedDelta.inMicroseconds / Duration.microsecondsPerSecond;
    for (final agent in _agents) {
      agent.progressMeters = math.min(
        routeDistanceMeters,
        agent.progressMeters + _speedFor(agent) * seconds,
      );
    }
    _keepFollowerBehindLeader();
    for (final agent in _agents) {
      _recordTravelTrail(agent);
      if (agent.isOffRoute) _recordOffRouteTrail(agent);
    }
    final completed = _agents.every(
      (agent) => agent.progressMeters >= routeDistanceMeters,
    );
    if (completed) _state = RideSimulationState.completed;
    if (completed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _emitPositions() async {
    if (_emitting) return;
    _emitting = true;
    try {
      final recordedAt = _nextRecordedAt();
      final samples = [
        for (final agent in _agents)
          (agent: agent, sampled: _sampleAgent(agent)),
      ];
      for (final entry in samples) {
        final agent = entry.agent;
        final sampled = entry.sampled;
        final flight = _balloonFlightAt(agent);
        final sample = LocationSample(
          position: sampled.position,
          recordedAt: recordedAt,
          accuracyMeters: 4,
          speedMetersPerSecond: _speedFor(agent),
          headingDegrees: sampled.headingDegrees,
          altitudeMeters: flight?.altitudeMeters,
          altitudeSource: flight == null
              ? AltitudeSource.unknown
              : AltitudeSource.gnss,
          altitudeDatum: flight == null
              ? AltitudeDatum.unknown
              : AltitudeDatum.relativeToLaunch,
          altitudeAccuracyMeters: flight == null ? null : 6,
          verticalSpeedMetersPerSecond: flight?.verticalSpeedMetersPerSecond,
        );
        if (agent.isLocal) {
          await _awarenessController.recordLocalLocation(sample);
        } else {
          await _emitRemoteLocation(agent, sample, recordedAt);
        }
      }
    } finally {
      _emitting = false;
    }
  }

  Future<void> _emitRemoteLocation(
    _SimulatedAgent agent,
    LocationSample sample,
    DateTime recordedAt,
  ) async {
    final remoteSession = RideSession(
      rideId: _session.rideId,
      rideCode: _session.rideCode,
      inviteSecret: _session.inviteSecret,
      joinToken: _session.joinToken,
      localRiderId: agent.id,
      displayName: agent.displayName,
      role: agent.role,
      joinedAt: _session.joinedAt,
      isSimulation: true,
      motorcycleStyle: agent.motorcycleStyle,
      riderSymbol: agent.riderSymbol,
      riderColor: agent.riderColor,
    );
    final location = RiderLocation(
      riderId: agent.id,
      displayName: agent.displayName,
      role: agent.role,
      sample: sample,
      receivedAt: recordedAt,
      motorcycleStyle: agent.motorcycleStyle,
      riderSymbol: agent.riderSymbol,
      riderColor: agent.riderColor,
    );
    final event =
        SituationEventFactory(
          session: remoteSession,
          clock: () => recordedAt,
          idFactory: () =>
              'ride-lab-${agent.id}-${recordedAt.microsecondsSinceEpoch}-${_eventSequence++}',
        ).create(
          type: RideEventType.riderLocationUpdated,
          payload: {'location': location.toJson()},
          expiresAt: recordedAt.add(const Duration(minutes: 30)),
        );
    await _awarenessController.ingestRemoteEvent(event);
  }

  /// Where the balloon is now, played back against the simulated clock.
  ///
  /// Null for a chase vehicle, and null when no flight is bundled. Heading is
  /// the direction of drift between neighbouring samples rather than anything
  /// the pilot chose - which is why it wanders while the balloon crosses a wind
  /// layer and holds steady while it sits in one.
  _SimulatedPosition? _flightPlayback(_SimulatedAgent agent) {
    final flight = _balloonFlight;
    if (flight == null || agent.role != RideRole.lead) return null;
    if (!_rideStarted) {
      return _SimulatedPosition(position: flight.launch, headingDegrees: 0);
    }
    final (before, after, fraction) = _flightWindow(flight);
    final position = GeoPoint(
      latitude:
          before.position.latitude +
          (after.position.latitude - before.position.latitude) * fraction,
      longitude:
          before.position.longitude +
          (after.position.longitude - before.position.longitude) * fraction,
    );
    return _SimulatedPosition(
      position: position,
      headingDegrees: _RouteSampler._bearingDegrees(
        before.position,
        after.position,
      ),
    );
  }

  /// The two flight samples the clock currently sits between, and how far.
  ///
  /// Clamps at the end rather than wrapping: once the balloon is down it stays
  /// down. The chase vehicles keep driving, which is the ordinary case - a crew
  /// arriving after the envelope is on the ground is a normal retrieve, not a
  /// missed rendezvous, so nothing here treats it as one.
  (BalloonFlightSample, BalloonFlightSample, double) _flightWindow(
    BalloonFlight flight,
  ) {
    final samples = flight.samples;
    final elapsed = _simulatedElapsed;
    if (elapsed >= flight.duration) {
      return (samples.last, samples.last, 0);
    }
    var index = 0;
    while (index < samples.length - 2 &&
        samples[index + 1].elapsed <= elapsed) {
      index += 1;
    }
    final before = samples[index];
    final after = samples[index + 1];
    final span = (after.elapsed - before.elapsed).inMicroseconds.toDouble();
    final into = (elapsed - before.elapsed).inMicroseconds.toDouble();
    return (before, after, span <= 0 ? 0.0 : (into / span).clamp(0.0, 1.0));
  }

  /// The balloon's height and climb rate at its current point in the flight.
  ///
  /// Only the lead agent flies: it stands in for the balloon while the rest of
  /// the fleet are chase vehicles on the road. Null for everyone else, and null
  /// before the ride starts, so Ride Lab exercises the "this fix carries no
  /// altitude" path as well as the flying one — the two have to look different
  /// on every surface, and a demo that only ever shows a number would never
  /// prove it.
  ///
  /// The shape is a short UK flight: climb out, ride the wind for most of the
  /// track, then a long descent onto the landing field. Deliberately not a
  /// smooth arc — a balloon holds a level while the pilot looks for a layer,
  /// which is what makes an altitude trail worth colouring.
  ({double altitudeMeters, double verticalSpeedMetersPerSecond})?
  _balloonFlightAt(_SimulatedAgent agent) {
    if (agent.role != RideRole.lead) return null;
    if (_balloonFlight case final flight?) {
      if (!_rideStarted) return null;
      final (before, after, fraction) = _flightWindow(flight);
      final height =
          before.heightMetres +
          (after.heightMetres - before.heightMetres) * fraction;
      final seconds =
          (after.elapsed - before.elapsed).inMicroseconds /
          Duration.microsecondsPerSecond;
      return (
        altitudeMeters: height + _launchElevationMetres,
        // Measured from the flight rather than asserted: a climb rate the
        // track does not actually show would put a number on screen that the
        // altitude trail contradicts.
        verticalSpeedMetersPerSecond: seconds <= 0
            ? 0
            : (after.heightMetres - before.heightMetres) / seconds,
      );
    }
    if (routeDistanceMeters <= 0) return null;
    final progress = (agent.progressMeters / routeDistanceMeters).clamp(
      0.0,
      1.0,
    );
    const groundMeters = 100.0;
    const cruiseMeters = 640.0;
    const climbRate = 2.4;
    const descentRate = -1.6;

    return switch (progress) {
      // Climb out of the launch field.
      < 0.18 => (
        altitudeMeters:
            groundMeters + (cruiseMeters - groundMeters) * (progress / 0.18),
        verticalSpeedMetersPerSecond: climbRate,
      ),
      // Holding a layer, with the small drift a burner actually produces.
      < 0.68 => (
        altitudeMeters:
            cruiseMeters + 40 * math.sin((progress - 0.18) * math.pi * 3),
        verticalSpeedMetersPerSecond:
            0.6 * math.cos((progress - 0.18) * math.pi * 3),
      ),
      // Long descent onto the field.
      _ => (
        altitudeMeters:
            cruiseMeters -
            (cruiseMeters - groundMeters) * ((progress - 0.68) / 0.32),
        verticalSpeedMetersPerSecond: descentRate,
      ),
    };
  }

  double _speedFor(_SimulatedAgent agent) {
    if (!_rideStarted) return 0;
    if (_state == RideSimulationState.completed) return 0;
    if (agent.id == backRiderId && _backRiderDelayed) {
      return _baseSpeedMetersPerSecond * 0.45;
    }
    final elapsedSeconds =
        _simulatedElapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final trafficCycle = (elapsedSeconds + agent.trafficPhaseSeconds) % 58;
    // Staggered traffic-light waits let the virtual group spread naturally
    // rather than moving as a rigid five-bike line.
    final trafficFactor = trafficCycle < 4
        ? 0.08
        : 0.74 +
              0.22 *
                  ((math.sin(elapsedSeconds / 8 + agent.trafficPhaseSeconds) +
                          1) /
                      2);
    return _baseSpeedMetersPerSecond * agent.speedFactor * trafficFactor;
  }

  _SimulatedAgent _agent(String id) =>
      _agents.firstWhere((agent) => agent.id == id);

  void _recordOffRouteTrail(_SimulatedAgent agent) {
    final point = _sampleAgent(agent).position;
    final trail = agent.offRouteTrail;
    if (trail.isEmpty ||
        GeoCalculations.distanceMeters(trail.last, point) >= 2) {
      trail.add(point);
      if (trail.length > 600) trail.removeRange(0, trail.length - 600);
    }
  }

  void _recordTravelTrail(_SimulatedAgent agent) {
    final point = _sampleAgent(agent).position;
    final trail = agent.travelTrail;
    if (trail.isEmpty ||
        GeoCalculations.distanceMeters(trail.last, point) >= 2) {
      trail.add(point);
      if (trail.length > 180) trail.removeRange(0, trail.length - 180);
    }
  }

  void _positionFleetForPerspective() {
    final local = _agents.first;
    if (_selectedLocalRole != RideRole.rider) return;
    final maya = _agent('ride-lab-maya');
    maya.progressMeters = math.min(
      routeDistanceMeters,
      math.max(maya.progressMeters, local.progressMeters + _followerGapMeters),
    );
  }

  void _keepFollowerBehindLeader() {
    if (_selectedLocalRole != RideRole.rider) return;
    final local = _agents.first;
    final lead = _leadAgent();
    if (lead.id == local.id) return;
    local.progressMeters = math.min(
      local.progressMeters,
      math.max(0, lead.progressMeters - _followerGapMeters),
    );
  }

  _SimulatedPosition _sampleAgent(_SimulatedAgent agent) {
    if (_flightPlayback(agent) case final flown?) return flown;
    final sampled = _routeSampler.sampleAt(agent.progressMeters);
    // The synthetic off-route scenario must recover at the destination so the
    // same completion rule used by a live ride can end the demo naturally.
    final recoveredAtDestination =
        agent.progressMeters >= routeDistanceMeters - 45;
    return _SimulatedPosition(
      position: agent.isOffRoute && !recoveredAtDestination
          ? _offsetPoint(sampled.point, sampled.headingDegrees, 220)
          : sampled.point,
      headingDegrees: sampled.headingDegrees,
    );
  }

  void _assignPerspectiveRoles() {
    for (final agent in _agents) {
      agent.role = RideRole.rider;
    }
    _agents.first.role = _selectedLocalRole;
    if (_selectedLocalRole != RideRole.lead) {
      _agent('ride-lab-maya').role = RideRole.lead;
    }
  }

  static const _followerGapMeters = 180.0;

  _SimulatedAgent _leadAgent() => _agents.firstWhere(
    (agent) => agent.role == RideRole.lead,
    orElse: () => _agents.first,
  );

  String get _localPerspectiveName => switch (_selectedLocalRole) {
    RideRole.lead => _session.displayName,
    RideRole.rider => 'You · Follower',
  };

  DateTime _nextRecordedAt() {
    final now = DateTime.now();
    final previous = _lastRecordedAt;
    final result = previous == null || now.isAfter(previous)
        ? now
        : previous.add(const Duration(milliseconds: 1));
    _lastRecordedAt = result;
    return result;
  }

  static GeoPoint _offsetPoint(
    GeoPoint point,
    double headingDegrees,
    double offsetMeters,
  ) {
    final direction = (headingDegrees + 90) * math.pi / 180;
    final northMeters = math.cos(direction) * offsetMeters;
    final eastMeters = math.sin(direction) * offsetMeters;
    final latitude = point.latitude + northMeters / 111320;
    final longitude =
        point.longitude +
        eastMeters / (111320 * math.cos(point.latitude * math.pi / 180).abs());
    return GeoPoint(latitude: latitude, longitude: longitude);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _SimulatedAgent {
  _SimulatedAgent({
    required this.id,
    required this.displayName,
    required this.role,
    required this.progressMeters,
    required this.speedFactor,
    required this.trafficPhaseSeconds,
    required this.motorcycleStyle,
    required this.riderColor,
    this.isLocal = false,
    this.riderSymbol = riderSymbolDefault,
  });

  final String id;
  final String displayName;
  RideRole role;
  double progressMeters;
  final double speedFactor;
  final double trafficPhaseSeconds;
  final CraftIconStyle motorcycleStyle;
  final RiderSymbol riderSymbol;
  final RiderColor riderColor;
  final bool isLocal;
  bool isOffRoute = false;
  final List<GeoPoint> offRouteTrail = [];
  final List<GeoPoint> travelTrail = [];
}

class _SimulatedPosition {
  const _SimulatedPosition({
    required this.position,
    required this.headingDegrees,
  });

  final GeoPoint position;
  final double headingDegrees;
}

class _RouteSampler {
  _RouteSampler(List<GeoPoint> route) : _route = List.unmodifiable(route) {
    _cumulativeDistances = [0];
    for (var index = 1; index < _route.length; index += 1) {
      _cumulativeDistances.add(
        _cumulativeDistances.last +
            GeoCalculations.distanceMeters(_route[index - 1], _route[index]),
      );
    }
    totalDistanceMeters = _cumulativeDistances.last;
    if (totalDistanceMeters <= 0) {
      throw ArgumentError('Simulation route must contain distinct points.');
    }
  }

  final List<GeoPoint> _route;
  late final List<double> _cumulativeDistances;
  late final double totalDistanceMeters;

  List<GeoPoint> pointsBetween(double fromMeters, double toMeters) {
    final start = fromMeters.clamp(0, totalDistanceMeters).toDouble();
    final end = toMeters.clamp(0, totalDistanceMeters).toDouble();
    if (end <= start) return [sampleAt(start).point];
    // Keep the leader trace continuous enough to read on the map without
    // sending every GPS tick through the overlay source.
    final stepMeters = math.max(20, (end - start) / 750);
    final segmentCount = ((end - start) / stepMeters).ceil();
    return List.unmodifiable([
      for (var index = 0; index <= segmentCount; index += 1)
        sampleAt(start + (end - start) * index / segmentCount).point,
    ]);
  }

  _SampledRoutePoint sampleAt(double distanceMeters) {
    final target = distanceMeters.clamp(0, totalDistanceMeters).toDouble();
    var index = 0;
    while (index < _route.length - 2 &&
        _cumulativeDistances[index + 1] < target) {
      index += 1;
    }
    final start = _route[index];
    final end = _route[index + 1];
    final segmentLength =
        _cumulativeDistances[index + 1] - _cumulativeDistances[index];
    final fraction = segmentLength == 0
        ? 0.0
        : ((target - _cumulativeDistances[index]) / segmentLength).clamp(
            0.0,
            1.0,
          );
    return _SampledRoutePoint(
      point: GeoPoint(
        latitude: start.latitude + (end.latitude - start.latitude) * fraction,
        longitude:
            start.longitude + (end.longitude - start.longitude) * fraction,
      ),
      headingDegrees: _bearingDegrees(start, end),
    );
  }

  static double _bearingDegrees(GeoPoint start, GeoPoint end) {
    final latitude1 = start.latitude * math.pi / 180;
    final latitude2 = end.latitude * math.pi / 180;
    final longitudeDelta = (end.longitude - start.longitude) * math.pi / 180;
    final y = math.sin(longitudeDelta) * math.cos(latitude2);
    final x =
        math.cos(latitude1) * math.sin(latitude2) -
        math.sin(latitude1) * math.cos(latitude2) * math.cos(longitudeDelta);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

class _SampledRoutePoint {
  const _SampledRoutePoint({required this.point, required this.headingDegrees});

  final GeoPoint point;
  final double headingDegrees;
}
