import 'package:balloon_crumbs/domain/craft.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/landing_zone.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/chase_guidance_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 22, 8);
  const resolver = ChaseGuidanceTargetResolver();

  test('landing guidance includes its radius plus a road-access margin', () {
    final target = resolver.resolve(
      target: ChaseGuidanceTarget.landingArea,
      now: now,
      landingZone: LandingZoneTarget(
        center: const GeoPoint(latitude: 51.45, longitude: -2.61),
        radiusMeters: 500,
        label: 'North field',
        updatedAt: now,
      ),
    );

    expect(target, isNotNull);
    expect(target!.maximumRoadSeparationMeters, 1000);
    expect(
      target.acceptsRoadEndpoint(
        const GeoPoint(latitude: 51.451, longitude: -2.61),
      ),
      isTrue,
    );
  });

  test('stale balloon fixes cannot become a live navigation target', () {
    final target = resolver.resolve(
      target: ChaseGuidanceTarget.balloon,
      now: now,
      balloonFix: _fix(now.subtract(const Duration(seconds: 46))),
    );

    expect(target, isNull);
  });

  test('balloon guidance rejects a road endpoint too far from the craft', () {
    final target = resolver.resolve(
      target: ChaseGuidanceTarget.balloon,
      now: now,
      balloonFix: _fix(now.subtract(const Duration(seconds: 4))),
    );

    expect(target, isNotNull);
    expect(
      target!.acceptsRoadEndpoint(
        const GeoPoint(latitude: 51.47, longitude: -2.61),
      ),
      isFalse,
    );
  });

  test('moving-target reroutes are time and movement bounded', () {
    const policy = ChaseGuidanceReroutePolicy();
    const previous = GeoPoint(latitude: 51.45, longitude: -2.61);

    expect(
      policy.shouldReroute(
        now: now,
        target: const GeoPoint(latitude: 51.454, longitude: -2.61),
        lastRoutedAt: now.subtract(const Duration(minutes: 1)),
        lastTarget: previous,
      ),
      isFalse,
    );
    expect(
      policy.shouldReroute(
        now: now,
        target: const GeoPoint(latitude: 51.454, longitude: -2.61),
        lastRoutedAt: now.subtract(const Duration(minutes: 3)),
        lastTarget: previous,
      ),
      isTrue,
    );
  });

  test('devices aboard one vehicle share its latest target choice', () {
    final events = [
      _event('register', 'driver', RideEventType.craftRegistered, now, {
        'craftId': 'rover',
        'kind': CraftKind.vehicle.name,
      }),
      _event(
        'attach-driver',
        'driver',
        RideEventType.deviceAttachedToCraft,
        now.add(const Duration(seconds: 1)),
        {'craftId': 'rover', 'deviceId': 'driver'},
      ),
      _event(
        'attach-crew',
        'crew',
        RideEventType.deviceAttachedToCraft,
        now.add(const Duration(seconds: 2)),
        {'craftId': 'rover', 'deviceId': 'crew'},
      ),
      _event(
        'driver-choice',
        'driver',
        RideEventType.chaseGuidanceTargetSelected,
        now.add(const Duration(seconds: 3)),
        {'craftId': 'rover', 'target': 'balloon'},
      ),
      _event(
        'crew-choice',
        'crew',
        RideEventType.chaseGuidanceTargetSelected,
        now.add(const Duration(seconds: 4)),
        {'craftId': 'rover', 'target': 'landingArea'},
      ),
    ];

    final selection = const ChaseGuidanceSelectionReducer().fromEvents(
      events,
    )['rover'];

    expect(selection?.target, ChaseGuidanceTarget.landingArea);
    expect(selection?.changedByDeviceId, 'crew');
  });

  test('a device cannot redirect a different chase vehicle', () {
    final events = [
      _event('register-a', 'driver-a', RideEventType.craftRegistered, now, {
        'craftId': 'rover-a',
        'kind': CraftKind.vehicle.name,
      }),
      _event('register-b', 'driver-b', RideEventType.craftRegistered, now, {
        'craftId': 'rover-b',
        'kind': CraftKind.vehicle.name,
      }),
      _event(
        'attach-a',
        'driver-a',
        RideEventType.deviceAttachedToCraft,
        now.add(const Duration(seconds: 1)),
        {'craftId': 'rover-a', 'deviceId': 'driver-a'},
      ),
      _event(
        'wrong-vehicle',
        'driver-a',
        RideEventType.chaseGuidanceTargetSelected,
        now.add(const Duration(seconds: 2)),
        {'craftId': 'rover-b', 'target': 'balloon'},
      ),
    ];

    expect(const ChaseGuidanceSelectionReducer().fromEvents(events), isEmpty);
  });
}

RideEvent _event(
  String id,
  String deviceId,
  RideEventType type,
  DateTime createdAt,
  Map<String, Object?> payload,
) => RideEvent(
  id: id,
  rideId: 'flight',
  deviceId: deviceId,
  type: type,
  priority: EventPriority.important,
  createdAt: createdAt,
  payload: payload,
  signature: '0' * 64,
);

LocationSample _fix(DateTime recordedAt) => LocationSample(
  position: const GeoPoint(latitude: 51.45, longitude: -2.61),
  recordedAt: recordedAt,
  accuracyMeters: 4,
  speedMetersPerSecond: 5,
  headingDegrees: 40,
);
