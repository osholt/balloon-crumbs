import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/device_identity_store.dart';

class SecureDeviceIdentityStore implements DeviceIdentityStore {
  const SecureDeviceIdentityStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'balloon_crumbs_device_signing_seed_v1_';
  final FlutterSecureStorage _storage;

  String _key(String rideId) =>
      '$_prefix${sha256.convert(utf8.encode(rideId)).toString()}';

  @override
  Future<void> delete(String rideId) => _storage.delete(key: _key(rideId));

  @override
  Future<List<int>?> readSeed(String rideId) async {
    final encoded = await _storage.read(key: _key(rideId));
    if (encoded == null) return null;
    try {
      final seed = base64Url.decode(base64Url.normalize(encoded));
      return seed.length == 32 ? seed : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeSeed(String rideId, List<int> seed) {
    if (seed.length != 32) {
      throw ArgumentError.value(seed.length, 'seed', 'Must contain 32 bytes');
    }
    return _storage.write(
      key: _key(rideId),
      value: base64Url.encode(seed).replaceAll('=', ''),
    );
  }
}
