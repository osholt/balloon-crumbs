import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/device_identity.dart';
import 'package:balloon_crumbs/services/presence_authenticator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 12);

  test('live position proof binds the device, coordinates and time', () async {
    final identity = await DeviceIdentity.fromSeed(
      rideId: 'ride-1',
      seed: List<int>.generate(32, (index) => index),
    );
    final position = RiderLocation(
      riderId: identity.deviceId,
      displayName: 'Alex',
      role: RideRole.rider,
      sample: LocationSample(
        position: const GeoPoint(latitude: 51.25, longitude: -2.35),
        recordedAt: now,
        accuracyMeters: 4,
        speedMetersPerSecond: 12,
        headingDegrees: 90,
      ),
      receivedAt: now,
    );
    final proof = await PresenceAuthenticator.sign(
      rideId: 'ride-1',
      riderId: identity.deviceId,
      position: position,
      clear: false,
      signedAt: now,
      identity: identity,
    );

    expect(
      await PresenceAuthenticator.verify(
        rideId: 'ride-1',
        riderId: identity.deviceId,
        position: position,
        clear: false,
        proof: proof,
        now: now,
      ),
      isTrue,
    );
    expect(
      await PresenceAuthenticator.verify(
        rideId: 'ride-1',
        riderId: identity.deviceId,
        position: RiderLocation(
          riderId: identity.deviceId,
          displayName: 'Alex',
          role: RideRole.rider,
          sample: LocationSample(
            position: const GeoPoint(latitude: 51.26, longitude: -2.35),
            recordedAt: now,
            accuracyMeters: 4,
          ),
          receivedAt: now,
        ),
        clear: false,
        proof: proof,
        now: now,
      ),
      isFalse,
    );
    expect(
      await PresenceAuthenticator.verify(
        rideId: 'ride-1',
        riderId: identity.deviceId,
        position: position,
        clear: false,
        proof: proof,
        now: now.add(const Duration(minutes: 6)),
      ),
      isFalse,
    );
  });
}
