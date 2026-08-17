import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/completed_ride.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';

/// The sweep-rider role was removed with the Tail End Charlie migration
/// (`docs/delivery-plan.md` WP1). A peer on an older build still publishes
/// `tailEndCharlie`, and an install that predates the removal still has it in
/// its stored session, so every reader has to survive the name rather than
/// throw on it. `RideRole.values.byName` throws, which is why these paths go
/// through [rideRoleFromName].
void main() {
  test('a role name this build does not know reads as an ordinary rider', () {
    expect(rideRoleFromName('tailEndCharlie'), RideRole.rider);
    expect(rideRoleFromName('somethingNewer'), RideRole.rider);
    expect(rideRoleFromName(null), RideRole.rider);
    expect(rideRoleFromName(42), RideRole.rider);
  });

  test('known role names still round-trip', () {
    for (final role in RideRole.values) {
      expect(rideRoleFromName(role.name), role);
    }
  });

  test('a caller can choose its own fallback', () {
    expect(
      rideRoleFromName('tailEndCharlie', fallback: RideRole.lead),
      RideRole.lead,
    );
  });

  test("a peer's relayed location carrying the removed role still parses", () {
    final location = RiderLocation.fromJson({
      'riderId': 'charlie',
      'displayName': 'Charlie',
      'role': 'tailEndCharlie',
      'sample': {
        'position': {'latitude': 51.45, 'longitude': -2.59},
        'recordedAt': '2026-07-17T10:00:00.000Z',
        'accuracyMeters': 5.0,
        'speedMetersPerSecond': 12.0,
        'headingDegrees': 90.0,
      },
      'receivedAt': '2026-07-17T10:00:01.000Z',
      'motorcycleStyle': null,
      'riderColor': null,
    });

    expect(location.role, RideRole.rider);
    expect(location.displayName, 'Charlie');
  });

  test('a stored session saved under the removed role still restores', () {
    final session = RideSession.fromJson({
      ...RideSession(
        rideId: 'ride-1',
        rideCode: '123456',
        inviteSecret: '0123456789abcdef0123456789abcdef',
        joinToken: 'fedcba9876543210fedcba9876543210',
        localRiderId: 'device-1',
        displayName: 'Oliver',
        role: RideRole.rider,
        joinedAt: DateTime.utc(2026, 7, 17, 10),
      ).toJson(),
      'role': 'tailEndCharlie',
    });

    expect(session.role, RideRole.rider);
    expect(session.displayName, 'Oliver');
  });

  test('a filed ride saved under the removed role still opens', () {
    final ride = CompletedRide.fromJson({
      ...CompletedRide(
        rideId: 'ride-1',
        rideCode: '123456',
        rideName: 'Sunday',
        localDisplayName: 'Oliver',
        localRole: RideRole.rider,
        startedAt: DateTime.utc(2026, 7, 17, 10),
        endedAt: DateTime.utc(2026, 7, 17, 12),
        archivedAt: DateTime.utc(2026, 7, 17, 12, 5),
        riderCount: 3,
        eventCount: 12,
        totalDistanceMeters: 4200,
              plannedRoute: null,
        traveledRoute: null,
      ).toJson(),
      'localRole': 'tailEndCharlie',
    });

    expect(ride.localRole, RideRole.rider);
  });
}
