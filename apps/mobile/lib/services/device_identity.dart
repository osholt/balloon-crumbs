import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../domain/device_identity_store.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.publicKey,
    required this.privateSeed,
  });

  final String deviceId;
  final String publicKey;
  final List<int> privateSeed;

  DeviceIdentity boundToDeviceId(String value) => DeviceIdentity(
    deviceId: value,
    publicKey: publicKey,
    privateSeed: List<int>.of(privateSeed),
  );

  static Future<DeviceIdentity> fromSeed({
    required String rideId,
    required List<int> seed,
  }) async {
    if (seed.length != 32) {
      throw ArgumentError.value(seed.length, 'seed', 'Must contain 32 bytes');
    }
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKeyBytes = (await keyPair.extractPublicKey()).bytes;
    final encodedPublicKey = _base64Url(publicKeyBytes);
    return DeviceIdentity(
      deviceId: deviceIdFor(rideId: rideId, publicKey: encodedPublicKey),
      publicKey: encodedPublicKey,
      privateSeed: List<int>.of(seed),
    );
  }

  static String deviceIdFor({
    required String rideId,
    required String publicKey,
  }) {
    final digest = sha256.convert(
      utf8.encode('balloon-crumbs-device-id-v1\n$rideId\n$publicKey'),
    );
    return 'bcd1_${_base64Url(digest.bytes)}';
  }

  static bool matchesDeviceId({
    required String rideId,
    required String publicKey,
    required String deviceId,
  }) => deviceIdFor(rideId: rideId, publicKey: publicKey) == deviceId;

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

class DeviceIdentityManager {
  DeviceIdentityManager(this._store, {Random? random})
    : _random = random ?? Random.secure();

  final DeviceIdentityStore _store;
  final Random _random;

  Future<DeviceIdentity> loadOrCreate(String rideId) async {
    var seed = await _store.readSeed(rideId);
    if (seed == null) {
      seed = List<int>.generate(32, (_) => _random.nextInt(256));
      await _store.writeSeed(rideId, seed);
    }
    return DeviceIdentity.fromSeed(rideId: rideId, seed: seed);
  }

  Future<DeviceIdentity> rotate(String rideId) async {
    final identity = await generateReplacement(rideId);
    await save(identity, rideId: rideId);
    return identity;
  }

  Future<DeviceIdentity> generateReplacement(String rideId) =>
      DeviceIdentity.fromSeed(
        rideId: rideId,
        seed: List<int>.generate(32, (_) => _random.nextInt(256)),
      );

  Future<void> save(DeviceIdentity identity, {required String rideId}) =>
      _store.writeSeed(rideId, identity.privateSeed);

  Future<void> delete(String rideId) => _store.delete(rideId);
}
