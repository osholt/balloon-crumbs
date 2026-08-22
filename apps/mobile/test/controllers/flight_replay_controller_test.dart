import 'package:balloon_crumbs/controllers/flight_replay_controller.dart';
import 'package:balloon_crumbs/domain/flight_replay.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all archived tracks share one seekable clock', () {
    final start = DateTime.utc(2026, 8, 22, 6);
    final controller = FlightReplayController(
      FlightReplay(
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 10)),
        tracks: [
          _track('balloon', FlightReplayTrackKind.balloon, start, 51.4),
          _track('chaser', FlightReplayTrackKind.localChaser, start, 51.3),
        ],
        windContexts: const [],
        landingAreas: const [],
        peerTracksIncluded: false,
      ),
    );
    addTearDown(controller.dispose);

    controller.seek(0.5);

    expect(controller.elapsed, const Duration(minutes: 5));
    expect(controller.frame.samples, hasLength(2));
    expect(
      controller.frame.samples['balloon']!.position.latitude,
      closeTo(51.45, 0.00001),
    );
    expect(
      controller.frame.samples['chaser']!.position.latitude,
      closeTo(51.35, 0.00001),
    );
  });

  test('a long recording gap is held rather than invented as a line', () {
    final start = DateTime.utc(2026, 8, 22, 6);
    final controller = FlightReplayController(
      FlightReplay(
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 10)),
        tracks: [
          _gapTrack('balloon', FlightReplayTrackKind.balloon, start, 51.4),
        ],
        windContexts: const [],
        landingAreas: const [],
        peerTracksIncluded: false,
      ),
    );
    addTearDown(controller.dispose);

    controller.seek(0.5);

    expect(controller.frame.samples['balloon']!.position.latitude, 51.4);
  });
}

FlightReplayTrack _track(
  String id,
  FlightReplayTrackKind kind,
  DateTime start,
  double latitude,
) => FlightReplayTrack(
  id: id,
  label: id,
  kind: kind,
  samples: [
    FlightReplaySample(
      position: GeoPoint(latitude: latitude, longitude: -2.6),
      recordedAt: start,
    ),
    FlightReplaySample(
      position: GeoPoint(latitude: latitude + 0.04, longitude: -2.56),
      recordedAt: start.add(const Duration(minutes: 4)),
    ),
    FlightReplaySample(
      position: GeoPoint(latitude: latitude + 0.06, longitude: -2.54),
      recordedAt: start.add(const Duration(minutes: 6)),
    ),
    FlightReplaySample(
      position: GeoPoint(latitude: latitude + 0.1, longitude: -2.5),
      recordedAt: start.add(const Duration(minutes: 10)),
    ),
  ],
);

FlightReplayTrack _gapTrack(
  String id,
  FlightReplayTrackKind kind,
  DateTime start,
  double latitude,
) => FlightReplayTrack(
  id: id,
  label: id,
  kind: kind,
  samples: [
    FlightReplaySample(
      position: GeoPoint(latitude: latitude, longitude: -2.6),
      recordedAt: start,
    ),
    FlightReplaySample(
      position: GeoPoint(latitude: latitude + 0.1, longitude: -2.5),
      recordedAt: start.add(const Duration(minutes: 10)),
    ),
  ],
);
