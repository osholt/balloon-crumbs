import '../domain/device_identity_store.dart';

class InMemoryDeviceIdentityStore implements DeviceIdentityStore {
  final Map<String, List<int>> _seeds = {};

  @override
  Future<void> delete(String rideId) async {
    final removed = _seeds.remove(rideId);
    if (removed != null) {
      removed.fillRange(0, removed.length, 0);
    }
  }

  @override
  Future<List<int>?> readSeed(String rideId) async {
    final seed = _seeds[rideId];
    return seed == null ? null : List<int>.of(seed);
  }

  @override
  Future<void> writeSeed(String rideId, List<int> seed) async {
    _seeds[rideId] = List<int>.of(seed);
  }
}
