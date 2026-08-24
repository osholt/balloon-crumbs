import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../domain/rider_location.dart';
import 'device_identity.dart';

/// A short-lived author proof for a replace-only live position.
///
/// The shared flight secret still authenticates the transport. This proof binds
/// the update to one operation-scoped device key, so an invite holder cannot
/// publish a position under another crew member's device ID.
class PresenceAuthorityProof {
  const PresenceAuthorityProof({
    required this.signedAtMilliseconds,
    required this.devicePublicKey,
    required this.deviceSignature,
  });

  final int signedAtMilliseconds;
  final String devicePublicKey;
  final String deviceSignature;

  Map<String, Object?> toJson() => {
    'authorityVersion': 1,
    'signedAtMilliseconds': signedAtMilliseconds,
    'devicePublicKey': devicePublicKey,
    'deviceSignature': deviceSignature,
  };

  factory PresenceAuthorityProof.fromJson(Map<String, Object?> json) {
    final version = json['authorityVersion'];
    final signedAt = json['signedAtMilliseconds'];
    final publicKey = json['devicePublicKey'];
    final signature = json['deviceSignature'];
    if (version != 1 ||
        signedAt is! int ||
        publicKey is! String ||
        publicKey.length != 43 ||
        signature is! String ||
        signature.length != 86) {
      throw const FormatException('Invalid live-position authority proof.');
    }
    return PresenceAuthorityProof(
      signedAtMilliseconds: signedAt,
      devicePublicKey: publicKey,
      deviceSignature: signature,
    );
  }
}

class PresenceAuthenticator {
  const PresenceAuthenticator._();

  static const maximumAge = Duration(minutes: 5);
  static const maximumFutureSkew = Duration(minutes: 2);

  static Future<PresenceAuthorityProof> sign({
    required String rideId,
    required String riderId,
    required RiderLocation? position,
    required bool clear,
    required DateTime signedAt,
    required DeviceIdentity identity,
  }) async {
    if (clear != (position == null) ||
        (position != null && position.riderId != riderId)) {
      throw ArgumentError('Invalid live-position update.');
    }
    final milliseconds = signedAt.toUtc().millisecondsSinceEpoch;
    final keyPair = await Ed25519().newKeyPairFromSeed(identity.privateSeed);
    final signature = await Ed25519().sign(
      utf8.encode(
        challenge(
          rideId: rideId,
          riderId: riderId,
          position: position,
          clear: clear,
          signedAtMilliseconds: milliseconds,
        ),
      ),
      keyPair: keyPair,
    );
    return PresenceAuthorityProof(
      signedAtMilliseconds: milliseconds,
      devicePublicKey: identity.publicKey,
      deviceSignature: _base64Url(signature.bytes),
    );
  }

  static Future<bool> verify({
    required String rideId,
    required String riderId,
    required RiderLocation? position,
    required bool clear,
    required PresenceAuthorityProof proof,
    required DateTime now,
  }) async {
    if (clear != (position == null) ||
        (position != null && position.riderId != riderId)) {
      return false;
    }
    final signedAt = DateTime.fromMillisecondsSinceEpoch(
      proof.signedAtMilliseconds,
      isUtc: true,
    );
    final utcNow = now.toUtc();
    if (signedAt.isBefore(utcNow.subtract(maximumAge)) ||
        signedAt.isAfter(utcNow.add(maximumFutureSkew))) {
      return false;
    }
    try {
      final publicKey = _decodeBase64Url(proof.devicePublicKey);
      final signature = _decodeBase64Url(proof.deviceSignature);
      if (publicKey.length != 32 || signature.length != 64) return false;
      return Ed25519().verify(
        utf8.encode(
          challenge(
            rideId: rideId,
            riderId: riderId,
            position: position,
            clear: clear,
            signedAtMilliseconds: proof.signedAtMilliseconds,
          ),
        ),
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  static String challenge({
    required String rideId,
    required String riderId,
    required RiderLocation? position,
    required bool clear,
    required int signedAtMilliseconds,
  }) =>
      'balloon-crumbs-live-presence-v1\n'
      '${_canonicalJson({'rideId': rideId, 'riderId': riderId, 'signedAtMilliseconds': signedAtMilliseconds, 'clear': clear, 'position': position == null ? null : _positionJson(position)})}';

  /// The signed body excludes relay-owned arrival/expiry fields.
  static Map<String, Object?> _positionJson(RiderLocation position) => {
    'displayName': position.displayName,
    'role': position.role.name,
    'craftStyle': position.craftStyle.name,
    'riderSymbol': position.riderSymbol.storageValue,
    'motorcycleStyle': position.riderSymbol.wireValue(position.craftStyle),
    'riderColor': position.riderColor.name,
    'sample': position.sample.toJson(),
  };

  static String _canonicalJson(Object? value) {
    if (value is Map<Object?, Object?>) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List<Object?>) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _decodeBase64Url(String value) =>
      base64Url.decode(base64Url.normalize(value));
}
