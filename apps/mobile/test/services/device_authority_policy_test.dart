import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/services/device_authority_policy.dart';
import 'package:balloon_crumbs/services/device_identity.dart';
import 'package:balloon_crumbs/services/ride_event_authenticator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secret = 'operation-secret-with-enough-entropy';
  const rideId = 'ride-device-authority';
  late DeviceIdentity root;
  late DeviceIdentity crew;
  late RideSession session;

  setUp(() async {
    root = await DeviceIdentity.fromSeed(
      rideId: rideId,
      seed: List<int>.generate(32, (index) => index),
    );
    crew = await DeviceIdentity.fromSeed(
      rideId: rideId,
      seed: List<int>.generate(32, (index) => 255 - index),
    );
    session = RideSession(
      rideId: rideId,
      rideCode: '123456',
      inviteSecret: secret,
      joinToken: 'join-token-with-enough-entropy',
      localRiderId: root.deviceId,
      displayName: 'Pilot',
      role: RideRole.lead,
      flightRole: FlightRole.pilot,
      joinedAt: DateTime.utc(2026, 8, 24),
      authorizationVersion: 2,
      authorityRootPublicKey: root.publicKey,
      localDevicePublicKey: root.publicKey,
    );
  });

  Future<RideEvent> signed({
    required DeviceIdentity identity,
    required RideEventType type,
    required Map<String, Object?> payload,
    required int minute,
  }) {
    return RideEventAuthenticator.signForDevice(
      event: RideEvent(
        id: '${identity.deviceId}-$minute-${type.name}',
        rideId: rideId,
        deviceId: identity.deviceId,
        type: type,
        priority: EventPriority.important,
        createdAt: DateTime.utc(2026, 8, 24, 12, minute),
        payload: payload,
        signature: '',
        devicePublicKey: identity.publicKey,
        schemaVersion: 2,
      ),
      secret: secret,
      identity: identity,
    );
  }

  test(
    'shared secret cannot impersonate pilot or exercise pilot authority',
    () async {
      final policy = DeviceAuthorityPolicy(session);
      final created = await signed(
        identity: root,
        type: RideEventType.rideCreated,
        payload: const {'role': 'lead', 'flightRole': 'pilot'},
        minute: 0,
      );
      final joined = await signed(
        identity: crew,
        type: RideEventType.riderJoined,
        payload: const {
          'displayName': 'Crew',
          'role': 'rider',
          'flightRole': 'chaseCrew',
        },
        minute: 1,
      );
      final forgedPilotAction = await signed(
        identity: crew,
        type: RideEventType.landingAreaNoted,
        payload: const {'landingZoneId': 'forged'},
        minute: 2,
      );
      final realPilotAction = await signed(
        identity: root,
        type: RideEventType.landingAreaNoted,
        payload: const {'landingZoneId': 'pilot'},
        minute: 3,
      );

      expect(policy.accept(created), isTrue);
      expect(policy.accept(joined), isTrue);
      expect(policy.accept(forgedPilotAction), isFalse);
      expect(policy.accept(realPilotAction), isTrue);
    },
  );

  test('pilot revocation makes all later device events inert', () async {
    final events = <RideEvent>[
      await signed(
        identity: root,
        type: RideEventType.rideCreated,
        payload: const {'role': 'lead', 'flightRole': 'pilot'},
        minute: 0,
      ),
      await signed(
        identity: crew,
        type: RideEventType.riderJoined,
        payload: const {
          'displayName': 'Crew',
          'role': 'rider',
          'flightRole': 'chaseCrew',
        },
        minute: 1,
      ),
      await signed(
        identity: root,
        type: RideEventType.deviceAuthorityRevoked,
        payload: {'targetDeviceId': crew.deviceId},
        minute: 2,
      ),
      await signed(
        identity: crew,
        type: RideEventType.statusMessage,
        payload: const {'message': 'should not be visible'},
        minute: 3,
      ),
    ];

    final policy = DeviceAuthorityPolicy(session);
    expect(policy.filter(events).map((event) => event.type), [
      RideEventType.rideCreated,
      RideEventType.riderJoined,
      RideEventType.deviceAuthorityRevoked,
    ]);
    expect(policy.revokedDeviceIds, contains(crew.deviceId));
  });
}
