import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/craft_telemetry_election.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP3. Several phones in one basket must produce one balloon position, and
/// every peer has to reach the same answer without negotiating.
void main() {
  final now = DateTime.utc(2026, 8, 17, 10);
  const election = CraftTelemetryElection();

  LocationSample fix({
    Duration age = Duration.zero,
    double accuracy = 5,
    double longitude = -2.59,
  }) => LocationSample(
    position: GeoPoint(latitude: 51.45, longitude: longitude),
    recordedAt: now.subtract(age),
    accuracyMeters: accuracy,
    altitudeMeters: 400,
    altitudeSource: AltitudeSource.gnss,
    altitudeAccuracyMeters: 6,
  );

  CraftFixCandidate device(
    String id, {
    Duration age = Duration.zero,
    double accuracy = 5,
    bool primary = false,
    double longitude = -2.59,
  }) => CraftFixCandidate(
    deviceId: id,
    sample: fix(age: age, accuracy: accuracy, longitude: longitude),
    isNominatedPrimary: primary,
  );

  group('a basket with several phones reports one position', () {
    test('three crew aboard yield one fix and a crew count of three', () {
      final result = election.elect(
        candidates: [
          device('pilot-phone', age: const Duration(seconds: 6)),
          device('crew-phone', age: const Duration(seconds: 2)),
          device('passenger-phone', age: const Duration(seconds: 9)),
        ],
        now: now,
      );

      expect(result.hasFix, isTrue);
      expect(result.deviceId, 'crew-phone', reason: 'freshest fix wins');
      expect(result.contributingDeviceCount, 3);
    });

    test('the pilot is not assumed to be the reporter', () {
      // The pilot is flying; the crew member beside them is holding the phone.
      final result = election.elect(
        candidates: [
          device('pilot-phone', age: const Duration(seconds: 30)),
          device('crew-phone', age: const Duration(seconds: 1)),
        ],
        now: now,
      );

      expect(result.deviceId, 'crew-phone');
    });

    test('a nominated primary wins while its fix is usable', () {
      final result = election.elect(
        candidates: [
          device('nominated', age: const Duration(seconds: 20), primary: true),
          device('fresher', age: const Duration(seconds: 1)),
        ],
        now: now,
      );

      expect(result.deviceId, 'nominated');
    });

    test('a nominated primary with a dead receiver does not silence the craft', () {
      // The pilot's choice is a preference, not an override. A nominated phone
      // that has stopped reporting must not keep the balloon dark while another
      // phone in the same basket has a good fix.
      final result = election.elect(
        candidates: [
          device('nominated', age: const Duration(minutes: 5), primary: true),
          device('crew-phone', age: const Duration(seconds: 2)),
        ],
        now: now,
      );

      expect(result.deviceId, 'crew-phone');
    });
  });

  group('an absent fix says which kind of absent', () {
    test('nobody aboard is not the same as nobody reporting usefully', () {
      final empty = election.elect(candidates: const [], now: now);
      expect(empty.hasFix, isFalse);
      expect(empty.absence, CraftFixAbsence.noDevices);
      expect(empty.contributingDeviceCount, 0);

      final lost = election.elect(
        candidates: [device('crew-phone', age: const Duration(minutes: 4))],
        now: now,
      );
      expect(lost.hasFix, isFalse);
      expect(
        lost.absence,
        CraftFixAbsence.allUnusable,
        reason: '"we have lost them" is not "nobody joined"',
      );
      expect(lost.contributingDeviceCount, 1);
    });

    test('a wildly inaccurate fix is not published however fresh', () {
      final result = election.elect(
        candidates: [device('crew-phone', accuracy: 2000)],
        now: now,
      );

      expect(result.hasFix, isFalse);
      expect(result.absence, CraftFixAbsence.allUnusable);
    });
  });

  group('hysteresis stops the balloon stuttering between two phones', () {
    test('the incumbent keeps the craft against a marginally fresher rival', () {
      // Two phones side by side, reporting a few seconds apart. Without
      // hysteresis the balloon's track would jump between positions metres
      // apart every cycle, which reads as the balloon jinking.
      final result = election.elect(
        candidates: [
          device('phone-a', age: const Duration(seconds: 8)),
          device('phone-b', age: const Duration(seconds: 2)),
        ],
        now: now,
        incumbentDeviceId: 'phone-a',
      );

      expect(result.deviceId, 'phone-a');
    });

    test('a meaningfully fresher rival does take over', () {
      final result = election.elect(
        candidates: [
          device('phone-a', age: const Duration(seconds: 40)),
          device('phone-b', age: const Duration(seconds: 1)),
        ],
        now: now,
        incumbentDeviceId: 'phone-a',
      );

      expect(result.deviceId, 'phone-b');
    });

    test('an incumbent that has gone unusable is replaced at once', () {
      final result = election.elect(
        candidates: [
          device('phone-a', age: const Duration(minutes: 3)),
          device('phone-b', age: const Duration(seconds: 5)),
        ],
        now: now,
        incumbentDeviceId: 'phone-a',
      );

      expect(result.deviceId, 'phone-b');
    });
  });

  group('every peer reaches the same answer', () {
    test('identical inputs in any order elect the same device', () {
      final candidates = [
        device('zulu', age: const Duration(seconds: 4)),
        device('alpha', age: const Duration(seconds: 4)),
        device('mike', age: const Duration(seconds: 4)),
      ];

      // Equal freshness: the tie must break on device id, not arrival order,
      // or two phones computing this from the same journal disagree about where
      // the balloon is.
      final forwards = election.elect(candidates: candidates, now: now);
      final backwards = election.elect(
        candidates: candidates.reversed,
        now: now,
      );

      expect(forwards.deviceId, 'alpha');
      expect(backwards.deviceId, 'alpha');
    });

    test('the election reads nothing but its arguments', () {
      // No wall clock, no state carried between calls: the same inputs a minute
      // later still elect the same device, which is what makes it replayable
      // from the journal.
      final candidates = [
        device('phone-a', age: const Duration(seconds: 3)),
        device('phone-b', age: const Duration(seconds: 12)),
      ];

      expect(
        election.elect(candidates: candidates, now: now).deviceId,
        election.elect(candidates: candidates, now: now).deviceId,
      );
    });
  });
}
