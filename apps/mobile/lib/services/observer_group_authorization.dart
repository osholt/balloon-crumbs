import 'dart:collection';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../domain/ride_session.dart';
import '../internet/observer_access_client.dart';
import 'device_identity.dart';

class ObserverGroupAuthorization {
  const ObserverGroupAuthorization._();

  static Future<ObserverPilotAuthorization> sign({
    required RideSession session,
    required DeviceIdentity identity,
    required String label,
    required Duration duration,
    required ObserverPositionPrecision precision,
    required DateTime signedAt,
  }) async {
    final signedAtMilliseconds = signedAt.toUtc().millisecondsSinceEpoch;
    final challenge = buildChallenge(
      rideId: session.rideId,
      deviceId: session.localRiderId,
      devicePublicKey: identity.publicKey,
      signedAtMilliseconds: signedAtMilliseconds,
      label: label,
      durationMinutes: duration.inMinutes,
      precision: precision,
    );
    final keyPair = await Ed25519().newKeyPairFromSeed(identity.privateSeed);
    final signature = await Ed25519().sign(
      utf8.encode(challenge),
      keyPair: keyPair,
    );
    return ObserverPilotAuthorization(
      deviceId: session.localRiderId,
      devicePublicKey: identity.publicKey,
      signedAtMilliseconds: signedAtMilliseconds,
      signature: base64Url.encode(signature.bytes).replaceAll('=', ''),
    );
  }

  static String buildChallenge({
    required String rideId,
    required String deviceId,
    required String devicePublicKey,
    required int signedAtMilliseconds,
    required String label,
    required int durationMinutes,
    required ObserverPositionPrecision precision,
  }) {
    final body = SplayTreeMap<String, Object?>.from({
      'deviceId': deviceId,
      'devicePublicKey': devicePublicKey,
      'durationMinutes': durationMinutes,
      'label': label.trim().replaceAll(RegExp(r'\s+'), ' '),
      'precision': precision.name,
      'rideId': rideId,
      'scope': ObserverAccessScope.group.name,
      'signedAtMilliseconds': signedAtMilliseconds,
    });
    return 'balloon-crumbs-observer-group-grant-v1\n${jsonEncode(body)}';
  }
}
