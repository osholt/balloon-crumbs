import '../domain/rider_location.dart';
import '../services/presence_authenticator.dart';

/// One authenticated, replace-only presence update carried by Nearby.
///
/// These updates are never appended to the event journal or relay queue.
class RelayPresenceUpdate {
  const RelayPresenceUpdate({
    required this.riderId,
    required this.sentAt,
    required this.expiresAt,
    required this.clear,
    this.position,
    this.authorityProof,
  });

  final String riderId;
  final DateTime sentAt;
  final DateTime expiresAt;
  final bool clear;
  final RiderLocation? position;
  final PresenceAuthorityProof? authorityProof;
}

abstract interface class RelayPresenceGateway {
  Stream<RelayPresenceUpdate> get presenceUpdates;

  Future<void> publishPresence(
    RiderLocation? position, {
    bool clear = false,
    Duration ttl = const Duration(seconds: 45),
  });
}
