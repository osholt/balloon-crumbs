import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/rider_location.dart';
import '../domain/ride_event.dart';
import '../domain/ride_session.dart';
import '../relay/relay_engine.dart';
import '../relay/relay_presence.dart';

/// Narrow UI integration seam; it does not couple the ride controller to a
/// particular radio SDK.
class NearbyRelayController extends ChangeNotifier
    implements RelayPresenceGateway {
  NearbyRelayController(
    this._engine, {
    RelayPresenceFactory? presenceFactory,
    RelayPresenceVerifier? presenceVerifier,
  }) : // Public constructor names stay free of library-private underscores.
       // ignore: prefer_initializing_formals
       _presenceFactory = presenceFactory,
       // ignore: prefer_initializing_formals
       _presenceVerifier = presenceVerifier {
    _subscription = _engine.statuses.listen((status) {
      _status = status;
      notifyListeners();
    });
  }

  final RelayEngine _engine;
  final RelayPresenceFactory? _presenceFactory;
  final RelayPresenceVerifier? _presenceVerifier;
  late final StreamSubscription<RelayStatus> _subscription;
  RelayStatus _status = const RelayStatus.stopped();

  RelayStatus get status => _status;
  int get peerCount => _status.peerIds.length;
  Stream<RideEvent> get receivedEvents => _engine.receivedEvents;
  @override
  Stream<RelayPresenceUpdate> get presenceUpdates => _engine.receivedPresence;

  Future<void> start(RideSession session) => _engine.start(
    RelayEngineConfig(
      rideId: session.rideId,
      rideSecret: session.inviteSecret,
      localDeviceId: session.localRiderId,
      endpointName: session.displayName,
      presenceFactory: _presenceFactory,
      presenceVerifier: _presenceVerifier,
    ),
  );

  Future<void> publish(RideEvent event) => _engine.enqueueLocal(event);

  @override
  Future<void> publishPresence(
    RiderLocation? position, {
    bool clear = false,
    Duration ttl = const Duration(seconds: 45),
  }) => _engine.publishPresence(position, clear: clear, ttl: ttl);

  @Deprecated('Use publish')
  Future<void> relay(RideEvent event) => publish(event);

  Future<void> stop() => _engine.stop();

  Future<void> close() async {
    await _subscription.cancel();
    await _engine.dispose();
    dispose();
  }
}
