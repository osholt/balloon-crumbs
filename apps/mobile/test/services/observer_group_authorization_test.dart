import 'dart:convert';

import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/internet/observer_access_client.dart';
import 'package:balloon_crumbs/services/device_identity.dart';
import 'package:balloon_crumbs/services/observer_group_authorization.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'builds the relay canonical challenge and signs it with the pilot key',
    () async {
      final identity = await DeviceIdentity.fromSeed(
        rideId: 'flight-1',
        seed: List<int>.generate(32, (index) => index),
      );
      final session = RideSession(
        rideId: 'flight-1',
        rideCode: 'TUCKER',
        inviteSecret: 'invite-secret-long-enough',
        joinToken: 'join-token-0123456789',
        localRiderId: identity.deviceId,
        displayName: 'Pilot',
        role: RideRole.lead,
        joinedAt: DateTime.utc(2026, 8, 24, 6),
      );
      final signedAt = DateTime.utc(2026, 8, 24, 6, 30);

      final proof = await ObserverGroupAuthorization.sign(
        session: session,
        identity: identity,
        label: '  Home   contact ',
        duration: const Duration(minutes: 60),
        precision: ObserverPositionPrecision.reduced,
        signedAt: signedAt,
      );
      final challenge = ObserverGroupAuthorization.buildChallenge(
        rideId: session.rideId,
        deviceId: identity.deviceId,
        devicePublicKey: identity.publicKey,
        signedAtMilliseconds: signedAt.millisecondsSinceEpoch,
        label: '  Home   contact ',
        durationMinutes: 60,
        precision: ObserverPositionPrecision.reduced,
      );

      expect(
        challenge,
        'balloon-crumbs-observer-group-grant-v1\n'
        '{"deviceId":"${identity.deviceId}",'
        '"devicePublicKey":"${identity.publicKey}",'
        '"durationMinutes":60,"label":"Home contact",'
        '"precision":"reduced","rideId":"flight-1","scope":"group",'
        '"signedAtMilliseconds":1787553000000}',
      );
      final signature = Signature(
        base64Url.decode(base64Url.normalize(proof.signature)),
        publicKey: SimplePublicKey(
          base64Url.decode(base64Url.normalize(identity.publicKey)),
          type: KeyPairType.ed25519,
        ),
      );
      expect(
        await Ed25519().verify(utf8.encode(challenge), signature: signature),
        isTrue,
      );
    },
  );
}
