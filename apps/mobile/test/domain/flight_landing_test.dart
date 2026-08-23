import 'package:balloon_crumbs/domain/flight_landing.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/services/ride_event_authenticator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secret = '0123456789abcdef0123456789abcdef';
  final start = DateTime.utc(2026, 8, 23, 9);

  test('a late retraction cannot erase a newer landing declaration', () {
    final events = [
      _signed(
        id: 'join',
        type: RideEventType.riderJoined,
        at: start,
        secret: secret,
        payload: const {
          'displayName': 'Alex',
          'role': 'rider',
          'flightRole': 'chaseCrew',
        },
      ),
      _signed(
        id: 'landing-old',
        type: RideEventType.flightLanded,
        at: start.add(const Duration(minutes: 1)),
        secret: secret,
        payload: const {
          'declaredByDeviceId': 'crew',
          'declaredByDisplayName': 'Alex',
          'declaredByRole': 'chaseCrew',
          'evidence': 'radioConfirmed',
        },
      ),
      _signed(
        id: 'landing-new',
        type: RideEventType.flightLanded,
        at: start.add(const Duration(minutes: 2)),
        secret: secret,
        payload: const {
          'declaredByDeviceId': 'crew',
          'declaredByDisplayName': 'Alex',
          'declaredByRole': 'chaseCrew',
          'evidence': 'witnessed',
        },
      ),
      _signed(
        id: 'late-retraction',
        type: RideEventType.flightLandingRetracted,
        at: start.add(const Duration(minutes: 3)),
        secret: secret,
        payload: const {
          'landingEventId': 'landing-old',
          'retractedByDeviceId': 'crew',
        },
      ),
    ];

    final state = const FlightLandingReducer().fromEvents(
      rideId: 'flight',
      inviteSecret: secret,
      events: events.reversed,
    );

    expect(state.landing?.eventId, 'landing-new');
    expect(state.landing?.evidence, FlightLandingEvidence.witnessed);
  });

  test('observer declarations and invalid signatures are ignored', () {
    final observer = _signed(
      id: 'observer-join',
      deviceId: 'watcher',
      type: RideEventType.riderJoined,
      at: start,
      secret: secret,
      payload: const {
        'displayName': 'Watcher',
        'role': 'rider',
        'flightRole': 'observer',
      },
    );
    final declaration = _signed(
      id: 'observer-landing',
      deviceId: 'watcher',
      type: RideEventType.flightLanded,
      at: start.add(const Duration(minutes: 1)),
      secret: secret,
      payload: const {
        'declaredByDeviceId': 'watcher',
        'declaredByDisplayName': 'Watcher',
        'declaredByRole': 'observer',
        'evidence': 'witnessed',
      },
    );
    final forged = RideEvent(
      id: 'forged',
      rideId: 'flight',
      deviceId: 'crew',
      type: RideEventType.flightLanded,
      priority: EventPriority.important,
      createdAt: start.add(const Duration(minutes: 2)),
      payload: const {'declaredByDeviceId': 'crew', 'evidence': 'witnessed'},
      signature: '0' * 64,
    );

    final state = const FlightLandingReducer().fromEvents(
      rideId: 'flight',
      inviteSecret: secret,
      events: [observer, declaration, forged],
    );

    expect(state.isLanded, isFalse);
  });
}

RideEvent _signed({
  required String id,
  required RideEventType type,
  required DateTime at,
  required String secret,
  required Map<String, Object?> payload,
  String deviceId = 'crew',
}) {
  final unsigned = RideEvent(
    id: id,
    rideId: 'flight',
    deviceId: deviceId,
    type: type,
    priority: EventPriority.important,
    createdAt: at,
    payload: payload,
    signature: '',
  );
  return RideEvent(
    id: unsigned.id,
    rideId: unsigned.rideId,
    deviceId: unsigned.deviceId,
    type: unsigned.type,
    priority: unsigned.priority,
    createdAt: unsigned.createdAt,
    payload: unsigned.payload,
    signature: RideEventAuthenticator.sign(unsigned, secret),
  );
}
