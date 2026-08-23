import 'package:balloon_crumbs/domain/craft.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/craft_track_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 23, 7);
  var sequence = 0;

  setUp(() => sequence = 0);

  RideEvent event(
    RideEventType type, {
    required String deviceId,
    required Duration at,
    Map<String, Object?> payload = const {},
  }) {
    sequence += 1;
    return RideEvent(
      id: 'event-${sequence.toString().padLeft(3, '0')}',
      rideId: 'flight',
      deviceId: deviceId,
      type: type,
      priority: EventPriority.routine,
      createdAt: start.add(at),
      payload: payload,
      signature: '0' * 64,
    );
  }

  RideEvent register(String id, CraftKind kind, Duration at) => event(
    RideEventType.craftRegistered,
    deviceId: 'pilot',
    at: at,
    payload: {'craftId': id, 'kind': kind.name, 'label': id},
  );

  RideEvent attach(String device, String craft, Duration at) => event(
    RideEventType.deviceAttachedToCraft,
    deviceId: device,
    at: at,
    payload: {'deviceId': device, 'craftId': craft},
  );

  RideEvent fix(String device, Duration at, double longitude) => event(
    RideEventType.riderLocationUpdated,
    deviceId: device,
    at: at,
    payload: {
      'sample': LocationSample(
        position: GeoPoint(latitude: 51.4, longitude: longitude),
        recordedAt: start.add(at),
        accuracyMeters: 5,
        altitudeMeters: device.startsWith('balloon') ? 300 : null,
        altitudeSource: device.startsWith('balloon')
            ? AltitudeSource.gnss
            : AltitudeSource.unknown,
      ).toJson(),
    },
  );

  test('several basket phones reduce to one balloon track', () {
    final tracks = const CraftTrackReducer().fromEvents([
      register('Balloon', CraftKind.balloon, Duration.zero),
      attach('balloon-a', 'Balloon', const Duration(seconds: 1)),
      attach('balloon-b', 'Balloon', const Duration(seconds: 2)),
      fix('balloon-a', const Duration(seconds: 10), -2.50),
      fix('balloon-b', const Duration(seconds: 12), -2.49),
      fix('balloon-a', const Duration(seconds: 20), -2.48),
      fix('balloon-b', const Duration(seconds: 22), -2.47),
    ]);

    expect(tracks, hasLength(1));
    expect(tracks.single.isBalloon, isTrue);
    expect(
      tracks.single.samples.map((sample) => sample.position.longitude),
      [-2.50, -2.48],
      reason: 'the incumbent phone produces one continuous craft path',
    );
  });

  test('keeps independently elected tracks for separate vehicles', () {
    final tracks = const CraftTrackReducer().fromEvents([
      register('Land Rover', CraftKind.vehicle, Duration.zero),
      register('Van', CraftKind.vehicle, const Duration(milliseconds: 100)),
      attach('rover-phone', 'Land Rover', const Duration(seconds: 1)),
      attach('van-phone', 'Van', const Duration(seconds: 2)),
      fix('rover-phone', const Duration(seconds: 10), -2.5),
      fix('van-phone', const Duration(seconds: 11), -2.6),
      fix('rover-phone', const Duration(seconds: 20), -2.4),
      fix('van-phone', const Duration(seconds: 21), -2.7),
    ]);

    expect(tracks, hasLength(2));
    expect(tracks.map((track) => track.label), ['Land Rover', 'Van']);
    expect(tracks.every((track) => track.samples.length == 2), isTrue);
  });

  test('ignores duplicate and out-of-order measurements', () {
    final tracks = const CraftTrackReducer().fromEvents([
      register('Balloon', CraftKind.balloon, Duration.zero),
      attach('balloon-a', 'Balloon', const Duration(seconds: 1)),
      fix('balloon-a', const Duration(seconds: 20), -2.4),
      fix('balloon-a', const Duration(seconds: 10), -2.5),
      fix('balloon-a', const Duration(seconds: 20), -2.3),
    ]);

    expect(tracks.single.samples, hasLength(2));
    expect(tracks.single.samples.map((sample) => sample.recordedAt), [
      start.add(const Duration(seconds: 10)).toLocal(),
      start.add(const Duration(seconds: 20)).toLocal(),
    ]);
  });
}
