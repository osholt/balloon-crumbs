import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:meta/meta.dart';

import '../domain/ride_event.dart';
import 'device_identity.dart';

/// Signs the current event schema and verifies both it and the development
/// alpha's earlier event body so stored rides remain readable after upgrade.
class RideEventAuthenticator {
  const RideEventAuthenticator._();

  static String sign(RideEvent event, String secret) =>
      _digest(_canonicalBody(event), secret);

  /// Creates a schema-two event with an operation-scoped Ed25519 author proof
  /// as well as the group HMAC retained by the transport layer.
  static Future<RideEvent> signForDevice({
    required RideEvent event,
    required String secret,
    required DeviceIdentity identity,
  }) async {
    if (event.schemaVersion != 2 ||
        event.deviceId != identity.deviceId ||
        event.devicePublicKey != identity.publicKey) {
      throw ArgumentError('Event does not match its device identity.');
    }
    final groupSignature = sign(event, secret);
    final keyPair = await Ed25519().newKeyPairFromSeed(identity.privateSeed);
    final signature = await Ed25519().sign(
      utf8.encode(_canonicalBody(event)),
      keyPair: keyPair,
    );
    final signed = RideEvent(
      id: event.id,
      rideId: event.rideId,
      deviceId: event.deviceId,
      type: event.type,
      priority: event.priority,
      createdAt: event.createdAt,
      expiresAt: event.expiresAt,
      payload: event.payload,
      signature: groupSignature,
      devicePublicKey: identity.publicKey,
      deviceSignature: _base64Url(signature.bytes),
      acknowledged: event.acknowledged,
      schemaVersion: 2,
    );
    _deviceVerdicts[signed] = true;
    _verdicts[signed] = _Verdict(secret, true);
    if (signed.type == RideEventType.deviceAuthorityRotated) {
      final rotationVerdict = await _verifyRotationProof(signed);
      _rotationVerdicts[signed] = rotationVerdict;
      if (!rotationVerdict) {
        throw ArgumentError('Device rotation proof is invalid.');
      }
    }
    return signed;
  }

  static Future<String> signRotationProof({
    required String rideId,
    required String deviceId,
    required String oldPublicKey,
    required DeviceIdentity replacement,
  }) async {
    final keyPair = await Ed25519().newKeyPairFromSeed(replacement.privateSeed);
    final signature = await Ed25519().sign(
      utf8.encode(
        rotationChallenge(
          rideId: rideId,
          deviceId: deviceId,
          oldPublicKey: oldPublicKey,
          newPublicKey: replacement.publicKey,
        ),
      ),
      keyPair: keyPair,
    );
    return _base64Url(signature.bytes);
  }

  static String rotationChallenge({
    required String rideId,
    required String deviceId,
    required String oldPublicKey,
    required String newPublicKey,
  }) =>
      'balloon-crumbs-device-rotation-v1\n'
      '$rideId\n$deviceId\n$oldPublicKey\n$newPublicKey';

  /// Verdicts already reached, keyed by event identity.
  ///
  /// A [RideEvent] is immutable, so its verdict under a given secret never
  /// changes - but a ride journal is re-verified constantly: every reducer
  /// pass, every dashboard build. On a two-hour ride that is tens of thousands
  /// of events walked tens of thousands of times, which is what made the app
  /// unresponsive at the end of a ride (#165). Identity keying is what makes
  /// the memo safe: a forged event is a different object and is verified from
  /// scratch, so nothing can inherit another event's verdict. An [Expando]
  /// also releases its entry when the event is collected, so a removed ride
  /// leaves nothing behind.
  static final Expando<_Verdict> _verdicts = Expando<_Verdict>(
    'flight event signature verdict',
  );

  /// How many events have actually been authenticated, as opposed to answered
  /// from [_verdicts].
  ///
  /// Exposed because the cost this guards is invisible to a timing assertion on
  /// a shared CI machine but exact as a count: a journal walked ten times must
  /// authenticate each event once, not ten times.
  @visibleForTesting
  static int verificationsComputed = 0;

  static bool verify(RideEvent event, String secret) {
    if (!_verifyGroup(event, secret)) return false;
    if (event.schemaVersion == 1) return true;
    if (_deviceVerdicts[event] != true) return false;
    return event.type != RideEventType.deviceAuthorityRotated ||
        _rotationVerdicts[event] == true;
  }

  /// Verifies the group envelope and, for schema two, the author's Ed25519
  /// proof. Call this once at an ingress or cold-load boundary; synchronous
  /// reducers then consume the memoized verdict through [verify].
  static Future<bool> verifyAsync(RideEvent event, String secret) async {
    if (!_verifyGroup(event, secret)) return false;
    if (event.schemaVersion == 1) return true;
    final cached = _deviceVerdicts[event];
    if (cached != null) return cached;
    final publicKeyText = event.devicePublicKey;
    final signatureText = event.deviceSignature;
    if (publicKeyText == null || signatureText == null) {
      _deviceVerdicts[event] = false;
      return false;
    }
    try {
      final publicKeyBytes = _decodeBase64Url(publicKeyText);
      final signatureBytes = _decodeBase64Url(signatureText);
      if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
        _deviceVerdicts[event] = false;
        return false;
      }
      final verdict = await Ed25519().verify(
        utf8.encode(_canonicalBody(event)),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
      _deviceVerdicts[event] = verdict;
      if (!verdict) return false;
      if (event.type != RideEventType.deviceAuthorityRotated) return true;
      final rotationVerdict = await _verifyRotationProof(event);
      _rotationVerdicts[event] = rotationVerdict;
      return rotationVerdict;
    } on Object {
      _deviceVerdicts[event] = false;
      return false;
    }
  }

  static bool _verifyGroup(RideEvent event, String secret) {
    final cached = _verdicts[event];
    if (cached != null && cached.secret == secret) return cached.verdict;
    verificationsComputed += 1;
    final verdict = _verifyUncached(event, secret);
    _verdicts[event] = _Verdict(secret, verdict);
    return verdict;
  }

  static bool _verifyUncached(RideEvent event, String secret) {
    if (_constantTimeMatch(
          event.signature,
          _digest(_canonicalBody(event), secret),
        ) ==
        1) {
      return true;
    }
    // Builds released before canonical ordering signed the same complete
    // envelope with insertion-ordered JSON. Keep those events readable during
    // the development-alpha migration.
    //
    // Stopping at the first body that matches costs a third as much for the
    // events almost every journal is made of. It reveals only which schema
    // version signed the event, which the event states in the clear anyway;
    // the comparison against each candidate digest stays constant-time, which
    // is the part that must not leak.
    if (_constantTimeMatch(
          event.signature,
          _digest(_transitionalV1Body(event), secret),
        ) ==
        1) {
      return true;
    }
    return _constantTimeMatch(
          event.signature,
          _digest(_legacyBody(event), secret),
        ) ==
        1;
  }

  static int _constantTimeMatch(String actual, String expected) {
    if (actual.length != expected.length) return 0;
    var difference = 0;
    for (var index = 0; index < expected.length; index += 1) {
      difference |= actual.codeUnitAt(index) ^ expected.codeUnitAt(index);
    }
    return difference == 0 ? 1 : 0;
  }

  static String _digest(String body, String secret) =>
      Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(body)).toString();

  static String _canonicalBody(RideEvent event) =>
      _canonicalJson(_signedMap(event));

  static String _transitionalV1Body(RideEvent event) =>
      jsonEncode(_signedMap(event));

  static Map<String, Object?> _signedMap(RideEvent event) => {
    'schemaVersion': event.schemaVersion,
    'id': event.id,
    'rideId': event.rideId,
    'deviceId': event.deviceId,
    'type': event.type.name,
    'priority': event.priority.name,
    'createdAt': event.createdAt.toUtc().toIso8601String(),
    'expiresAt': event.expiresAt?.toUtc().toIso8601String(),
    'payload': event.payload,
    if (event.schemaVersion >= 2) 'devicePublicKey': event.devicePublicKey,
  };

  static String _legacyBody(RideEvent event) => jsonEncode({
    'id': event.id,
    'rideId': event.rideId,
    'deviceId': event.deviceId,
    'type': event.type.name,
    'priority': event.priority.name,
    'createdAt': event.createdAt.toUtc().toIso8601String(),
    'payload': event.payload,
  });

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

  static final Expando<bool> _deviceVerdicts = Expando<bool>(
    'flight event device signature verdict',
  );
  static final Expando<bool> _rotationVerdicts = Expando<bool>(
    'flight event replacement-key proof verdict',
  );

  static Future<bool> _verifyRotationProof(RideEvent event) async {
    final cached = _rotationVerdicts[event];
    if (cached != null) return cached;
    final oldPublicKey = event.devicePublicKey;
    final newPublicKey = event.payload['newPublicKey'];
    final proof = event.payload['newDeviceSignature'];
    if (oldPublicKey == null || newPublicKey is! String || proof is! String) {
      return false;
    }
    try {
      final publicKeyBytes = _decodeBase64Url(newPublicKey);
      final signatureBytes = _decodeBase64Url(proof);
      if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
        return false;
      }
      return Ed25519().verify(
        utf8.encode(
          rotationChallenge(
            rideId: event.rideId,
            deviceId: event.deviceId,
            oldPublicKey: oldPublicKey,
            newPublicKey: newPublicKey,
          ),
        ),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _decodeBase64Url(String value) =>
      base64Url.decode(base64Url.normalize(value));
}

class _Verdict {
  const _Verdict(this.secret, this.verdict);

  final String secret;
  final bool verdict;
}
