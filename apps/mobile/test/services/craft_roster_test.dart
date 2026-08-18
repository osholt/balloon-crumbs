import 'package:balloon_crumbs/domain/craft.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/craft_roster.dart';
import 'package:balloon_crumbs/services/craft_telemetry_election.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP3 acceptance, written as tests: several phones in one basket produce one
/// balloon track, several vehicles stay individually addressable, and a craft
/// with no usable fix says so rather than showing a stale one as live.
void main() {
  final start = DateTime.utc(2026, 8, 17, 10);
  const reducer = CraftRosterReducer();
  var sequence = 0;

  setUp(() => sequence = 0);

  RideEvent event(
    RideEventType type, {
    required String deviceId,
    Map<String, Object?> payload = const {},
    Duration at = Duration.zero,
  }) {
    sequence += 1;
    return RideEvent(
      id: 'event-$sequence',
      rideId: 'flight-1',
      deviceId: deviceId,
      type: type,
      priority: EventPriority.routine,
      createdAt: start.add(at),
      payload: payload,
      signature: '0' * 64,
    );
  }

  RideEvent registerCraft(String id, CraftKind kind, String label) => event(
    RideEventType.craftRegistered,
    deviceId: 'pilot-phone',
    payload: {'craftId': id, 'kind': kind.name, 'label': label},
  );

  RideEvent attach(String deviceId, String craftId) => event(
    RideEventType.deviceAttachedToCraft,
    deviceId: deviceId,
    payload: {'deviceId': deviceId, 'craftId': craftId},
  );

  RideEvent report(
    String deviceId, {
    required Duration age,
    double longitude = -2.59,
    double accuracy = 5,
    double? altitude = 400,
  }) => event(
    RideEventType.riderLocationUpdated,
    deviceId: deviceId,
    at: -age,
    payload: {
      'sample': LocationSample(
        position: GeoPoint(latitude: 51.45, longitude: longitude),
        recordedAt: start.subtract(age),
        accuracyMeters: accuracy,
        altitudeMeters: altitude,
        altitudeSource: altitude == null
            ? AltitudeSource.unknown
            : AltitudeSource.gnss,
        altitudeAccuracyMeters: altitude == null ? null : 6,
      ).toJson(),
    },
  );

  test('three phones in one basket produce one balloon track', () {
    final roster = reducer.fromEvents(
      events: [
        registerCraft('balloon', CraftKind.balloon, 'Balloon'),
        attach('pilot-phone', 'balloon'),
        attach('crew-phone', 'balloon'),
        attach('passenger-phone', 'balloon'),
        report('pilot-phone', age: const Duration(seconds: 8)),
        report('crew-phone', age: const Duration(seconds: 2)),
        report('passenger-phone', age: const Duration(seconds: 12)),
      ],
      now: start,
    );

    expect(roster.balloons, hasLength(1));
    final balloon = roster.balloon!;
    expect(balloon.crewCount, 3, reason: 'all three crew are aboard');
    expect(balloon.fix.hasFix, isTrue);
    expect(balloon.fix.deviceId, 'crew-phone');
    expect(
      balloon.fix.contributingDeviceCount,
      3,
      reason: 'one position, three contributors',
    );
  });

  test('handing the phone between crew does not make the track jump', () {
    final events = [
      registerCraft('balloon', CraftKind.balloon, 'Balloon'),
      attach('phone-a', 'balloon'),
      attach('phone-b', 'balloon'),
      report('phone-a', age: const Duration(seconds: 7), longitude: -2.590),
      report('phone-b', age: const Duration(seconds: 3), longitude: -2.591),
    ];

    // phone-a already speaks for the balloon. phone-b is a little fresher but
    // sitting in the same basket, so the balloon must stay with phone-a rather
    // than stuttering between two positions metres apart.
    final roster = reducer.fromEvents(
      events: events,
      now: start,
      previousReporters: const {'balloon': 'phone-a'},
    );

    expect(roster.balloon!.fix.deviceId, 'phone-a');
    expect(
      CraftRosterReducer.reportersOf(roster),
      const {'balloon': 'phone-a'},
      reason: 'reporters feed back as the next frame incumbents',
    );
  });

  test('four vehicles stay individually identifiable and addressable', () {
    final roster = reducer.fromEvents(
      events: [
        registerCraft('balloon', CraftKind.balloon, 'Balloon'),
        attach('pilot-phone', 'balloon'),
        report('pilot-phone', age: const Duration(seconds: 1)),
        for (final n in [1, 2, 3, 4]) ...[
          registerCraft('v$n', CraftKind.vehicle, 'Vehicle $n'),
          attach('driver-$n', 'v$n'),
          report(
            'driver-$n',
            age: const Duration(seconds: 4),
            longitude: -2.5 - n / 100,
          ),
        ],
      ],
      now: start,
    );

    expect(roster.vehicles, hasLength(4));
    expect(roster.byId('v3')!.craft.label, 'Vehicle 3');
    expect(roster.byId('v3')!.fix.hasFix, isTrue);
    // Every vehicle reports its own position — nothing is collapsed.
    final positions = roster.vehicles
        .map((v) => v.fix.sample!.position.longitude)
        .toSet();
    expect(positions, hasLength(4));
  });

  group('a craft with no usable fix says which kind of nothing', () {
    test('registered with nobody aboard', () {
      final roster = reducer.fromEvents(
        events: [registerCraft('v1', CraftKind.vehicle, 'Vehicle 1')],
        now: start,
      );

      expect(roster.byId('v1')!.fix.hasFix, isFalse);
      expect(roster.byId('v1')!.fix.absence, CraftFixAbsence.noDevices);
    });

    test('aboard but lost, which is not the same thing', () {
      final roster = reducer.fromEvents(
        events: [
          registerCraft('balloon', CraftKind.balloon, 'Balloon'),
          attach('crew-phone', 'balloon'),
          report('crew-phone', age: const Duration(minutes: 6)),
        ],
        now: start,
      );

      final balloon = roster.balloon!;
      expect(
        balloon.fix.hasFix,
        isFalse,
        reason: 'never show a stale fix as live',
      );
      expect(balloon.fix.absence, CraftFixAbsence.allUnusable);
      expect(balloon.crewCount, 1, reason: 'the crew are still aboard');
    });
  });

  group('chase assignment', () {
    test('with one balloon an unassigned vehicle is chasing it', () {
      final roster = reducer.fromEvents(
        events: [
          registerCraft('balloon', CraftKind.balloon, 'Balloon'),
          registerCraft('v1', CraftKind.vehicle, 'Land Rover'),
        ],
        now: start,
      );

      expect(roster.chasing('balloon').map((c) => c.id), ['v1']);
    });

    test('an explicit assignment is reassignable mid-flight', () {
      final roster = reducer.fromEvents(
        events: [
          registerCraft('b1', CraftKind.balloon, 'Balloon One'),
          registerCraft('b2', CraftKind.balloon, 'Balloon Two'),
          registerCraft('v1', CraftKind.vehicle, 'Land Rover'),
          event(
            RideEventType.craftChaseAssigned,
            deviceId: 'driver-1',
            payload: {'craftId': 'v1', 'chasing': 'b1'},
            at: const Duration(minutes: 1),
          ),
          event(
            RideEventType.craftChaseAssigned,
            deviceId: 'driver-1',
            payload: {'craftId': 'v1', 'chasing': 'b2'},
            at: const Duration(minutes: 2),
          ),
        ],
        now: start.add(const Duration(minutes: 3)),
      );

      // The multi-balloon shape works today even though the UI does not offer it.
      expect(roster.balloons, hasLength(2));
      expect(roster.byId('v1')!.craft.chasing, 'b2');
      expect(roster.chasing('b2').map((c) => c.id), ['v1']);
      expect(
        roster.chasing('b1'),
        isEmpty,
        reason: 'with two balloons an assignment is explicit, not inferred',
      );
    });

    test('an assignment naming a balloon is dropped, not fatal', () {
      // Applying it would trip the Craft constructor and take out the roster on
      // every device that replayed the journal.
      final roster = reducer.fromEvents(
        events: [
          registerCraft('balloon', CraftKind.balloon, 'Balloon'),
          event(
            RideEventType.craftChaseAssigned,
            deviceId: 'pilot-phone',
            payload: {'craftId': 'balloon', 'chasing': 'v1'},
            at: const Duration(minutes: 1),
          ),
        ],
        now: start.add(const Duration(minutes: 2)),
      );

      expect(roster.balloon!.craft.chasing, isNull);
    });
  });

  group('the reducer is deterministic and defensive', () {
    test('event order does not change the outcome', () {
      final events = [
        registerCraft('balloon', CraftKind.balloon, 'Balloon'),
        attach('phone-a', 'balloon'),
        attach('phone-b', 'balloon'),
        report('phone-a', age: const Duration(seconds: 5)),
        report('phone-b', age: const Duration(seconds: 9)),
      ];

      final forwards = reducer.fromEvents(events: events, now: start);
      final shuffled = reducer.fromEvents(events: events.reversed, now: start);

      expect(forwards.balloon!.fix.deviceId, shuffled.balloon!.fix.deviceId);
      expect(forwards.balloon!.deviceIds, shuffled.balloon!.deviceIds);
    });

    test('a late-arriving older fix does not replace a newer one', () {
      final roster = reducer.fromEvents(
        events: [
          registerCraft('balloon', CraftKind.balloon, 'Balloon'),
          attach('crew-phone', 'balloon'),
          report(
            'crew-phone',
            age: const Duration(seconds: 2),
            longitude: -2.60,
          ),
          report(
            'crew-phone',
            age: const Duration(seconds: 30),
            longitude: -2.50,
          ),
        ],
        now: start,
      );

      expect(roster.balloon!.fix.sample!.position.longitude, -2.60);
    });

    test('a device attached to an unregistered craft is dropped', () {
      // Inventing a craft for it would put an aircraft on the map that nobody
      // registered.
      final roster = reducer.fromEvents(
        events: [
          attach('stray-phone', 'ghost-craft'),
          report('stray-phone', age: const Duration(seconds: 1)),
        ],
        now: start,
      );

      expect(roster.crafts, isEmpty);
    });

    test('a malformed fix does not stop other crafts reconciling', () {
      final roster = reducer.fromEvents(
        events: [
          registerCraft('balloon', CraftKind.balloon, 'Balloon'),
          registerCraft('v1', CraftKind.vehicle, 'Land Rover'),
          attach('crew-phone', 'balloon'),
          attach('driver-1', 'v1'),
          event(
            RideEventType.riderLocationUpdated,
            deviceId: 'crew-phone',
            payload: const {
              'sample': {'nonsense': true},
            },
          ),
          report('driver-1', age: const Duration(seconds: 3)),
        ],
        now: start,
      );

      expect(roster.balloon!.fix.hasFix, isFalse);
      expect(roster.byId('v1')!.fix.hasFix, isTrue);
    });

    test('balloons sort first, then vehicles by label', () {
      final roster = reducer.fromEvents(
        events: [
          registerCraft('v2', CraftKind.vehicle, 'Zebra'),
          registerCraft('v1', CraftKind.vehicle, 'Alpha'),
          registerCraft('balloon', CraftKind.balloon, 'Balloon'),
        ],
        now: start,
      );

      expect(roster.crafts.map((c) => c.id), ['balloon', 'v1', 'v2']);
    });
  });

  test('a nominated primary is honoured through the journal', () {
    final roster = reducer.fromEvents(
      events: [
        registerCraft('balloon', CraftKind.balloon, 'Balloon'),
        attach('pilot-phone', 'balloon'),
        attach('crew-phone', 'balloon'),
        event(
          RideEventType.craftPrimaryDeviceNominated,
          deviceId: 'pilot-phone',
          payload: {'craftId': 'balloon', 'deviceId': 'pilot-phone'},
        ),
        report('pilot-phone', age: const Duration(seconds: 20)),
        report('crew-phone', age: const Duration(seconds: 2)),
      ],
      now: start,
    );

    expect(roster.balloon!.primaryDeviceId, 'pilot-phone');
    expect(roster.balloon!.fix.deviceId, 'pilot-phone');
  });
}
