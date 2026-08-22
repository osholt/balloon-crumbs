import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/landing_zone.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 22, 7);

  test('landing areas survive local-library JSON round trips', () {
    final target = LandingZoneTarget(
      center: const GeoPoint(latitude: 51.381, longitude: -2.361),
      radiusMeters: 500,
      label: 'West field',
      updatedAt: start,
    );

    final decoded = LandingZoneTarget.fromJson(target.toJson());

    expect(decoded.center, target.center);
    expect(decoded.radiusMeters, 500);
    expect(decoded.label, 'West field');
    expect(decoded.updatedAt.toUtc(), start);
  });

  test('only the current coordinator can replace the landing area', () {
    final events = [
      _event(
        id: 'created',
        deviceId: 'pilot',
        type: RideEventType.rideCreated,
        createdAt: start,
        payload: const {'role': 'lead'},
      ),
      _landingEvent(
        id: 'first',
        deviceId: 'pilot',
        createdAt: start.add(const Duration(minutes: 1)),
        latitude: 51.38,
      ),
      _event(
        id: 'chaser-joined',
        deviceId: 'chaser',
        type: RideEventType.riderJoined,
        createdAt: start.add(const Duration(minutes: 2)),
        payload: const {'role': 'rider'},
      ),
      _landingEvent(
        id: 'unauthorised',
        deviceId: 'chaser',
        createdAt: start.add(const Duration(minutes: 3)),
        latitude: 52,
      ),
      _event(
        id: 'promoted',
        deviceId: 'chaser',
        type: RideEventType.roleChanged,
        createdAt: start.add(const Duration(minutes: 4)),
        payload: const {'role': 'lead'},
      ),
      _event(
        id: 'demoted',
        deviceId: 'pilot',
        type: RideEventType.roleChanged,
        createdAt: start.add(const Duration(minutes: 4)),
        payload: const {'role': 'rider'},
      ),
      _landingEvent(
        id: 'replacement',
        deviceId: 'chaser',
        createdAt: start.add(const Duration(minutes: 5)),
        latitude: 51.4,
      ),
    ];

    final result = const LandingZoneReducer().fromEvents(events.reversed);

    expect(result?.center.latitude, 51.4);
    expect(result?.label, 'Intended landing area');
  });

  test('invalid radii are ignored', () {
    final result = const LandingZoneReducer().fromEvents([
      _event(
        id: 'created',
        deviceId: 'pilot',
        type: RideEventType.rideCreated,
        createdAt: start,
        payload: const {'role': 'lead'},
      ),
      _event(
        id: 'invalid',
        deviceId: 'pilot',
        type: RideEventType.landingAreaNoted,
        createdAt: start.add(const Duration(minutes: 1)),
        payload: const {
          'leaderRiderId': 'pilot',
          'latitude': 51.38,
          'longitude': -2.36,
          'radiusMeters': 50,
          'label': 'Too small',
        },
      ),
    ]);

    expect(result, isNull);
  });
}

RideEvent _landingEvent({
  required String id,
  required String deviceId,
  required DateTime createdAt,
  required double latitude,
}) => _event(
  id: id,
  deviceId: deviceId,
  type: RideEventType.landingAreaNoted,
  createdAt: createdAt,
  payload: {
    'leaderRiderId': deviceId,
    'latitude': latitude,
    'longitude': -2.36,
    'radiusMeters': 500,
    'label': 'Intended landing area',
  },
);

RideEvent _event({
  required String id,
  required String deviceId,
  required RideEventType type,
  required DateTime createdAt,
  required Map<String, Object?> payload,
}) => RideEvent(
  id: id,
  rideId: 'flight-a',
  deviceId: deviceId,
  type: type,
  priority: EventPriority.important,
  createdAt: createdAt,
  payload: payload,
  signature: 'signed-for-reducer-test',
);
