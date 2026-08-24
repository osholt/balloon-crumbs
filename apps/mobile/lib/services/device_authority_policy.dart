import '../domain/flight_role.dart';
import '../domain/ride_event.dart';
import '../domain/ride_role.dart';
import '../domain/ride_session.dart';
import 'device_identity.dart';
import 'pilot_handover.dart';
import 'ride_event_authenticator.dart';
import 'ride_lifecycle.dart';

/// Projects the operation-scoped trust graph before any product reducer sees
/// an event. Possession of the shared flight secret remains enough to reach the
/// transport, but is no longer enough to impersonate a participant or exercise
/// pilot authority.
class DeviceAuthorityPolicy {
  DeviceAuthorityPolicy(this.session);

  final RideSession session;
  final Map<String, String> _currentPublicKeys = {};
  final Map<String, FlightRole> _roles = {};
  final Set<String> _revokedDeviceIds = {};
  final Map<String, PilotHandoverOffer> _offers = {};
  String? _pilotDeviceId;

  String? get pilotDeviceId => _pilotDeviceId;
  Set<String> get revokedDeviceIds => Set.unmodifiable(_revokedDeviceIds);

  bool authorizesDeviceKey(String deviceId, String publicKey) =>
      !_revokedDeviceIds.contains(deviceId) &&
      _currentPublicKeys[deviceId] == publicKey;

  List<RideEvent> filter(Iterable<RideEvent> events) {
    final ordered = events.toList(growable: false)
      ..sort(RideLifecycleReducer.compareEvents);
    return [
      for (final event in ordered)
        if (accept(event)) event,
    ];
  }

  bool accept(RideEvent event) {
    if (!session.usesDeviceAuthority) {
      return event.schemaVersion == 1 &&
          RideEventAuthenticator.verify(event, session.inviteSecret);
    }
    if (event.schemaVersion != 2 ||
        !RideEventAuthenticator.verify(event, session.inviteSecret)) {
      return false;
    }
    final publicKey = event.devicePublicKey;
    if (publicKey == null || _revokedDeviceIds.contains(event.deviceId)) {
      return false;
    }
    final knownKey = _currentPublicKeys[event.deviceId];
    if (knownKey == null) {
      if (!DeviceIdentity.matchesDeviceId(
        rideId: event.rideId,
        publicKey: publicKey,
        deviceId: event.deviceId,
      )) {
        return false;
      }
      if (!_acceptFirstEvent(event, publicKey)) return false;
      _currentPublicKeys[event.deviceId] = publicKey;
      return true;
    }
    if (knownKey != publicKey) return false;
    if (!_isActionAuthorized(event)) return false;
    _apply(event);
    return true;
  }

  bool _acceptFirstEvent(RideEvent event, String publicKey) {
    if (publicKey == session.authorityRootPublicKey) {
      if (_pilotDeviceId != null || event.type != RideEventType.rideCreated) {
        return false;
      }
      final role = flightRoleFromName(event.payload['flightRole']);
      if (role != FlightRole.pilot ||
          rideRoleFromName(event.payload['role']) != RideRole.lead) {
        return false;
      }
      _pilotDeviceId = event.deviceId;
      _roles[event.deviceId] = FlightRole.pilot;
      return true;
    }
    if (event.type != RideEventType.riderJoined) {
      return false;
    }
    final role = flightRoleFromName(
      event.payload['flightRole'],
      fallback: FlightRole.observer,
    );
    if (role == FlightRole.pilot || role == FlightRole.observer) return false;
    if (rideRoleFromName(event.payload['role']) == RideRole.lead) return false;
    _roles[event.deviceId] = role;
    return true;
  }

  bool _isActionAuthorized(RideEvent event) {
    final role = _roles[event.deviceId];
    if (role == null) return false;
    if (_pilotDeviceId == null && event.type != RideEventType.riderLeft) {
      return false;
    }
    final isPilot = event.deviceId == _pilotDeviceId;
    return switch (event.type) {
      RideEventType.rideCreated || RideEventType.riderJoined => false,
      RideEventType.riderLeft =>
        event.payload['riderId'] == null ||
            event.payload['riderId'] == event.deviceId,
      RideEventType.roleChanged => _validSelfRoleChange(event),
      RideEventType.rideStarted ||
      RideEventType.ridePaused ||
      RideEventType.rideResumed ||
      RideEventType.rideReopened ||
      RideEventType.routeRevisionChunk ||
      RideEventType.routeRevisionPublished ||
      RideEventType.routeCleared ||
      RideEventType.craftPrimaryDeviceNominated ||
      RideEventType.landingAreaNoted ||
      RideEventType.operationalBoundaryUpserted ||
      RideEventType.operationalBoundaryRemoved ||
      RideEventType.pilotHandoverOffered ||
      RideEventType.deviceAuthorityRevoked => isPilot,
      RideEventType.windContextNoted =>
        isPilot || role == FlightRole.balloonCrew,
      RideEventType.flightStartedByCrew => role.isChasing,
      RideEventType.flightLanded ||
      RideEventType.flightLandingRetracted ||
      RideEventType.rideEnded => role != FlightRole.observer,
      RideEventType.pilotHandoverAccepted =>
        event.payload['toDeviceId'] == event.deviceId,
      RideEventType.deviceAttachedToCraft =>
        event.payload['deviceId'] == event.deviceId,
      RideEventType.craftChaseAssigned ||
      RideEventType.chaseGuidanceTargetSelected => role.isChasing,
      RideEventType.deviceAuthorityRotated => true,
      _ => true,
    };
  }

  bool _validSelfRoleChange(RideEvent event) {
    final role = flightRoleFromName(
      event.payload['flightRole'],
      fallback: _roles[event.deviceId] ?? FlightRole.observer,
    );
    return role != FlightRole.pilot &&
        rideRoleFromName(event.payload['role']) != RideRole.lead;
  }

  void _apply(RideEvent event) {
    switch (event.type) {
      case RideEventType.roleChanged:
        _roles[event.deviceId] = flightRoleFromName(
          event.payload['flightRole'],
          fallback: _roles[event.deviceId]!,
        );
      case RideEventType.pilotHandoverOffered:
        final offer = _handoverOffer(event);
        if (offer != null && offer.fromDeviceId == _pilotDeviceId) {
          _offers[offer.transferId] = offer;
        }
      case RideEventType.pilotHandoverAccepted:
        final transferId = event.payload['transferId'];
        final offer = transferId is String ? _offers[transferId] : null;
        if (offer != null &&
            offer.fromDeviceId == _pilotDeviceId &&
            offer.toDeviceId == event.deviceId &&
            !event.createdAt.isAfter(offer.expiresAt) &&
            !event.createdAt.isBefore(
              offer.offeredAt.subtract(PilotAuthorityReducer.maximumClockSkew),
            )) {
          final previousPilot = _pilotDeviceId!;
          _roles[previousPilot] = FlightRole.balloonCrew;
          _roles[event.deviceId] = FlightRole.pilot;
          _pilotDeviceId = event.deviceId;
        }
      case RideEventType.deviceAuthorityRevoked:
        final target = event.payload['targetDeviceId'];
        if (target is String && target != _pilotDeviceId) {
          _revokedDeviceIds.add(target);
        }
      case RideEventType.deviceAuthorityRotated:
        final replacement = event.payload['newPublicKey'];
        if (replacement is String) {
          _currentPublicKeys[event.deviceId] = replacement;
        }
      default:
        break;
    }
  }

  static PilotHandoverOffer? _handoverOffer(RideEvent event) {
    final transferId = event.payload['transferId'];
    final fromDeviceId = event.payload['fromDeviceId'];
    final toDeviceId = event.payload['toDeviceId'];
    final expiresAtValue = event.payload['expiresAt'];
    final expiresAt = expiresAtValue is String
        ? DateTime.tryParse(expiresAtValue)?.toUtc()
        : event.expiresAt?.toUtc();
    if (transferId is! String ||
        fromDeviceId is! String ||
        toDeviceId is! String ||
        expiresAt == null) {
      return null;
    }
    return PilotHandoverOffer(
      transferId: transferId,
      fromDeviceId: fromDeviceId,
      toDeviceId: toDeviceId,
      offeredAt: event.createdAt,
      expiresAt: expiresAt,
    );
  }
}
