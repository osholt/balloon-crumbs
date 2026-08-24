abstract interface class DeviceIdentityStore {
  Future<void> delete(String rideId);

  Future<List<int>?> readSeed(String rideId);

  Future<void> writeSeed(String rideId, List<int> seed);
}
