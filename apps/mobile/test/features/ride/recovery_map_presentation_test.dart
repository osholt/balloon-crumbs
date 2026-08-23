import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/features/ride/active_ride_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all operational roles receive the live recovery projection', () {
    for (final role in [
      FlightRole.pilot,
      FlightRole.balloonCrew,
      FlightRole.chaseDriver,
      FlightRole.chaseCrew,
    ]) {
      expect(roleShowsLiveRecoveryProjection(role), isTrue, reason: role.name);
    }
    expect(roleShowsLiveRecoveryProjection(FlightRole.observer), isFalse);
    expect(roleShowsLiveRecoveryProjection(null), isFalse);
  });

  test('craft motion is rendered in metric speed and compass direction', () {
    expect(
      craftGroundMotionLabel(speedMetersPerSecond: 10, headingDegrees: 280),
      '36 km/h · W 280°',
    );
    expect(
      craftGroundMotionLabel(speedMetersPerSecond: null, headingDegrees: null),
      isNull,
    );
  });
}
