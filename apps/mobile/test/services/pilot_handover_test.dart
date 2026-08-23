import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/services/pilot_handover.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 23, 12);

  test('authority changes only after the named balloon crew accepts', () {
    final events = _setup(now);
    const reducer = PilotAuthorityReducer();
    final offered = reducer.fromEvents(events: events, now: now);
    expect(offered.pilotDeviceId, 'pilot-a');
    expect(offered.hasAcceptedHandover, isFalse);
    expect(offered.pendingFor('crew-b')?.fromDeviceId, 'pilot-a');

    final accepted = reducer.fromEvents(
      events: [
        ...events,
        _event(
          id: 'accept',
          deviceId: 'crew-b',
          type: RideEventType.pilotHandoverAccepted,
          at: now.add(const Duration(minutes: 1)),
          payload: const {
            'transferId': 'transfer-1',
            'fromDeviceId': 'pilot-a',
            'toDeviceId': 'crew-b',
          },
        ),
      ],
      now: now.add(const Duration(minutes: 1)),
    );
    expect(accepted.pilotDeviceId, 'crew-b');
    expect(accepted.hasAcceptedHandover, isTrue);
    expect(accepted.pendingOffers, isEmpty);
  });

  test('wrong-device, expired and non-balloon acceptance are ignored', () {
    const reducer = PilotAuthorityReducer();
    for (final invalid in [
      _event(
        id: 'wrong-device',
        deviceId: 'crew-c',
        type: RideEventType.pilotHandoverAccepted,
        at: now.add(const Duration(minutes: 1)),
        payload: const {
          'transferId': 'transfer-1',
          'fromDeviceId': 'pilot-a',
          'toDeviceId': 'crew-b',
        },
      ),
      _event(
        id: 'expired',
        deviceId: 'crew-b',
        type: RideEventType.pilotHandoverAccepted,
        at: now.add(const Duration(minutes: 11)),
        payload: const {
          'transferId': 'transfer-1',
          'fromDeviceId': 'pilot-a',
          'toDeviceId': 'crew-b',
        },
      ),
    ]) {
      final state = reducer.fromEvents(
        events: [..._setup(now), invalid],
        now: invalid.createdAt,
      );
      expect(state.pilotDeviceId, 'pilot-a');
    }

    final groundTarget = [
      ..._setup(now),
      _event(
        id: 'vehicle',
        deviceId: 'pilot-a',
        type: RideEventType.craftRegistered,
        at: now.subtract(const Duration(minutes: 2)),
        payload: const {
          'craftId': 'vehicle-1',
          'kind': 'vehicle',
          'label': 'Land Rover',
        },
      ),
      _event(
        id: 'attach-ground',
        deviceId: 'crew-c',
        type: RideEventType.deviceAttachedToCraft,
        at: now.subtract(const Duration(minutes: 1)),
        payload: const {'deviceId': 'crew-c', 'craftId': 'vehicle-1'},
      ),
      _event(
        id: 'offer-ground',
        deviceId: 'pilot-a',
        type: RideEventType.pilotHandoverOffered,
        at: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        payload: {
          'transferId': 'ground-transfer',
          'fromDeviceId': 'pilot-a',
          'toDeviceId': 'crew-c',
          'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
        },
      ),
    ];
    expect(
      reducer.fromEvents(events: groundTarget, now: now).pendingFor('crew-c'),
      isNull,
    );
  });

  test(
    'a recipient clock slightly behind the pilot does not lose handover',
    () {
      const reducer = PilotAuthorityReducer();
      final state = reducer.fromEvents(
        events: [
          ..._setup(now),
          _event(
            id: 'accept-behind',
            deviceId: 'crew-b',
            type: RideEventType.pilotHandoverAccepted,
            at: now.subtract(const Duration(minutes: 1)),
            payload: const {
              'transferId': 'transfer-1',
              'fromDeviceId': 'pilot-a',
              'toDeviceId': 'crew-b',
            },
          ),
        ],
        now: now,
      );

      expect(state.pilotDeviceId, 'crew-b');
      expect(state.hasAcceptedHandover, isTrue);
    },
  );
}

List<RideEvent> _setup(DateTime now) => [
  _event(
    id: 'created',
    deviceId: 'pilot-a',
    type: RideEventType.rideCreated,
    at: now.subtract(const Duration(hours: 1)),
    payload: const {
      'displayName': 'Alice',
      'role': 'lead',
      'flightRole': 'pilot',
    },
  ),
  _event(
    id: 'balloon',
    deviceId: 'pilot-a',
    type: RideEventType.craftRegistered,
    at: now.subtract(const Duration(minutes: 59)),
    payload: const {
      'craftId': 'balloon-1',
      'kind': 'balloon',
      'label': 'Balloon',
    },
  ),
  for (final deviceId in const ['pilot-a', 'crew-b'])
    _event(
      id: 'attach-$deviceId',
      deviceId: deviceId,
      type: RideEventType.deviceAttachedToCraft,
      at: now.subtract(const Duration(minutes: 58)),
      payload: {'deviceId': deviceId, 'craftId': 'balloon-1'},
    ),
  _event(
    id: 'offer',
    deviceId: 'pilot-a',
    type: RideEventType.pilotHandoverOffered,
    at: now,
    expiresAt: now.add(const Duration(minutes: 10)),
    payload: {
      'transferId': 'transfer-1',
      'fromDeviceId': 'pilot-a',
      'toDeviceId': 'crew-b',
      'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
    },
  ),
];

RideEvent _event({
  required String id,
  required String deviceId,
  required RideEventType type,
  required DateTime at,
  required Map<String, Object?> payload,
  DateTime? expiresAt,
}) => RideEvent(
  id: id,
  rideId: 'flight-1',
  deviceId: deviceId,
  type: type,
  priority: EventPriority.important,
  createdAt: at,
  expiresAt: expiresAt,
  payload: payload,
  signature: '',
);
