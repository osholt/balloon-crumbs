import '../domain/flight_role.dart';
import '../domain/ride_event.dart';
import '../domain/ride_role.dart';
import 'ride_lifecycle.dart';

class PilotHandoverOffer {
  const PilotHandoverOffer({
    required this.transferId,
    required this.fromDeviceId,
    required this.toDeviceId,
    required this.offeredAt,
    required this.expiresAt,
  });

  final String transferId;
  final String fromDeviceId;
  final String toDeviceId;
  final DateTime offeredAt;
  final DateTime expiresAt;
}

class PilotAuthorityState {
  const PilotAuthorityState({
    required this.pilotDeviceId,
    required this.pendingOffers,
    required this.hasAcceptedHandover,
  });

  final String? pilotDeviceId;
  final List<PilotHandoverOffer> pendingOffers;
  final bool hasAcceptedHandover;

  PilotHandoverOffer? pendingFor(String deviceId) =>
      pendingOffers.where((offer) => offer.toDeviceId == deviceId).lastOrNull;
}

/// Replays pilot authority without trusting a visible role label on its own.
///
/// A transfer is effective only when the current pilot offered it to a device
/// already attached to the balloon and that same target device accepted before
/// expiry. A partial, stale or out-of-order pair leaves authority unchanged.
class PilotAuthorityReducer {
  const PilotAuthorityReducer();

  static const maximumClockSkew = Duration(minutes: 2);

  PilotAuthorityState fromEvents({
    required Iterable<RideEvent> events,
    required DateTime now,
  }) {
    final ordered = events.toList(growable: false)
      ..sort(RideLifecycleReducer.compareEvents);
    final balloonCraftIds = <String>{};
    final deviceCraft = <String, String>{};
    // Craft assignment is journal state, not wall-clock authority. Build it
    // before replaying offers so a harmless difference between two phones'
    // clocks cannot make a valid handover disappear merely because the offer
    // sorts just before the target's already-observed attachment event.
    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.craftRegistered:
          final craftId = event.payload['craftId'];
          if (craftId is String && event.payload['kind'] == 'balloon') {
            balloonCraftIds.add(craftId);
          }
        case RideEventType.deviceAttachedToCraft:
          final deviceId = event.payload['deviceId'];
          final craftId = event.payload['craftId'];
          if (deviceId is String && craftId is String) {
            deviceCraft[deviceId] = craftId;
          }
        default:
          break;
      }
    }
    final offers = <String, PilotHandoverOffer>{};
    final acceptances = <String, RideEvent>{};
    String? pilotDeviceId;

    for (final event in ordered) {
      switch (event.type) {
        case RideEventType.rideCreated:
          final flightRole = flightRoleFromName(event.payload['flightRole']);
          final legacyRole = rideRoleFromName(event.payload['role']);
          if (pilotDeviceId == null &&
              (flightRole == FlightRole.pilot || legacyRole == RideRole.lead)) {
            pilotDeviceId = event.deviceId;
          }
        case RideEventType.craftRegistered:
        case RideEventType.deviceAttachedToCraft:
          break;
        case RideEventType.pilotHandoverOffered:
          final offer = _offer(event);
          if (offer == null ||
              event.deviceId != offer.fromDeviceId ||
              !balloonCraftIds.contains(deviceCraft[offer.toDeviceId])) {
            break;
          }
          offers[offer.transferId] = offer;
        case RideEventType.pilotHandoverAccepted:
          final transferId = event.payload['transferId'];
          if (transferId is String) {
            final existing = acceptances[transferId];
            if (existing == null ||
                RideLifecycleReducer.compareEvents(event, existing) < 0) {
              acceptances[transferId] = event;
            }
          }
        default:
          break;
      }
    }

    final applied = <String>{};
    while (pilotDeviceId != null) {
      final candidates =
          offers.values
              .where(
                (offer) =>
                    !applied.contains(offer.transferId) &&
                    offer.fromDeviceId == pilotDeviceId &&
                    _acceptanceMatches(acceptances[offer.transferId], offer),
              )
              .toList(growable: false)
            ..sort((left, right) {
              final leftAccepted = acceptances[left.transferId]!;
              final rightAccepted = acceptances[right.transferId]!;
              final byAcceptance = RideLifecycleReducer.compareEvents(
                leftAccepted,
                rightAccepted,
              );
              if (byAcceptance != 0) return byAcceptance;
              return left.transferId.compareTo(right.transferId);
            });
      if (candidates.isEmpty) break;
      final accepted = candidates.first;
      applied.add(accepted.transferId);
      pilotDeviceId = accepted.toDeviceId;
    }

    final pending =
        offers.values
            .where(
              (offer) =>
                  offer.fromDeviceId == pilotDeviceId &&
                  !applied.contains(offer.transferId) &&
                  offer.expiresAt.isAfter(now),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byTime = left.offeredAt.compareTo(right.offeredAt);
            return byTime != 0
                ? byTime
                : left.transferId.compareTo(right.transferId);
          });

    return PilotAuthorityState(
      pilotDeviceId: pilotDeviceId,
      hasAcceptedHandover: applied.isNotEmpty,
      pendingOffers: List.unmodifiable(pending),
    );
  }

  static bool _acceptanceMatches(
    RideEvent? acceptance,
    PilotHandoverOffer offer,
  ) {
    if (acceptance == null ||
        acceptance.payload['fromDeviceId'] != offer.fromDeviceId ||
        acceptance.payload['toDeviceId'] != offer.toDeviceId ||
        acceptance.deviceId != offer.toDeviceId ||
        acceptance.createdAt.isAfter(offer.expiresAt)) {
      return false;
    }
    return !acceptance.createdAt.isBefore(
      offer.offeredAt.subtract(maximumClockSkew),
    );
  }

  static PilotHandoverOffer? _offer(RideEvent event) {
    final transferId = event.payload['transferId'];
    final fromDeviceId = event.payload['fromDeviceId'];
    final toDeviceId = event.payload['toDeviceId'];
    final expiresAtValue = event.payload['expiresAt'];
    final expiresAt = expiresAtValue is String
        ? DateTime.tryParse(expiresAtValue)?.toUtc()
        : event.expiresAt?.toUtc();
    if (transferId is! String ||
        transferId.isEmpty ||
        fromDeviceId is! String ||
        toDeviceId is! String ||
        fromDeviceId == toDeviceId ||
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
