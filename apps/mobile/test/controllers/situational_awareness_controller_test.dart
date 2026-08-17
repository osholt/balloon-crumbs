import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/controllers/situational_awareness_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/hazard.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/services/external_hazard_provider.dart';
import 'package:balloon_crumbs/services/situation_event_factory.dart';

void main() {
  late InMemoryEventStore store;
  late DateTime now;
  late int nextId;
  late SituationalAwarenessController controller;

  setUp(() async {
    store = InMemoryEventStore();
    now = DateTime.utc(2026, 7, 16, 12);
    nextId = 0;
    controller = _controller(
      store: store,
      clock: () => now,
      idFactory: () => 'id-${nextId++}',
    );
    await controller.initialize();
  });

  tearDown(() => controller.dispose());

  test('a location is persisted as a ride event', () async {
    await controller.recordLocalLocation(_sample(latitude: 51.002, at: now));

    expect(controller.riderLocations, hasLength(1));

    final events = await store.eventsForRide(_session.rideId);
    expect(
      events.map((event) => event.type),
      contains(RideEventType.riderLocationUpdated),
    );
  });

  test(
    'stored situational events are projected into the shared journal',
    () async {
      final stored = <RideEvent>[];
      final projecting = SituationalAwarenessController(
        store,
        _session,
        route: const [
          GeoPoint(latitude: 51, longitude: -1),
          GeoPoint(latitude: 51, longitude: -0.99),
        ],
        clock: () => now,
        idFactory: () => 'projected-${nextId++}',
        onEventStored: stored.add,
      );
      addTearDown(projecting.dispose);
      await projecting.initialize();

      await projecting.recordLocalLocation(_sample(latitude: 51.002, at: now));

      expect(
        stored.map((event) => event.type),
        contains(RideEventType.riderLocationUpdated),
      );
    },
  );

  test('the leader keeps their whole trail across a long ride', () async {
    final events = <RideEvent>[];
    for (var index = 0; index < 1200; index += 1) {
      final recordedAt = now.add(Duration(seconds: index));
      final factory = SituationEventFactory(
        session: _session,
        clock: () => recordedAt,
        idFactory: () => 'leader-$index',
      );
      final location = RiderLocation(
        riderId: _session.localRiderId,
        displayName: _session.displayName,
        role: RideRole.lead,
        sample: LocationSample(
          position: GeoPoint(latitude: 51 + index * 0.00001, longitude: -0.995),
          recordedAt: recordedAt,
          accuracyMeters: 5,
        ),
        receivedAt: recordedAt,
      );
      events.add(
        factory.create(
          type: RideEventType.riderLocationUpdated,
          payload: {'location': location.toJson()},
        ),
      );
    }
    final longRide = _controller(
      store: store,
      clock: () => now.add(const Duration(hours: 2)),
      idFactory: () => 'unused',
    );
    addTearDown(longRide.dispose);

    await longRide.initialize(restoredEvents: events);

    // This test previously asserted the opposite - that the trail was truncated
    // to a 600-point recent-track limit. That bound cost a
    // tester the tail of a 6 h 4 m, 112 mile ride: at these rates 600 points is
    // the last 40 minutes, and everything earlier was deleted from memory, so it
    // could never be drawn, exported or recapped again.
    //
    // The performance property #165 needed is that no *per-update* work grows
    // with the ride, and that is now held by two things instead: the projection
    // is cached rather than rebuilt per read, and the follow-corridor check is
    // handed only the recent window. Neither requires throwing history away.
    expect(longRide.leaderTrail, hasLength(1200));
    expect(
      longRide.leaderTrail.first.latitude,
      closeTo(51, 1e-9),
      reason: 'the earliest point of the ride must survive',
    );
    expect(longRide.leaderTrail.last.latitude, closeTo(51.01199, 1e-9));
  });

  test(
    'the cached trail projection stays consistent as points arrive',
    () async {
      // The cache is what makes retaining the whole trail affordable, so a stale
      // cache would be a silently wrong trail rather than a slow one.
      var nextId = 0;
      final controller = _controller(
        store: InMemoryEventStore(),
        clock: () => now,
        idFactory: () => 'cached-${nextId++}',
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoredEvents: const []);

      expect(controller.leaderTrail, isEmpty);

      for (var index = 0; index < 3; index += 1) {
        await controller.recordLocalLocation(
          LocationSample(
            position: GeoPoint(latitude: 51 + index * 0.001, longitude: -0.995),
            recordedAt: now.add(Duration(seconds: index)),
            accuracyMeters: 5,
          ),
        );
        expect(
          controller.leaderTrail,
          hasLength(index + 1),
          reason: 'the projection must reflect every recorded point',
        );
        expect(controller.leaderTrailSamples, hasLength(index + 1));
      }
      expect(controller.leaderTrail.last.latitude, closeTo(51.002, 1e-9));
    },
  );

  test(
    // The rule, decided for #300: a rider is visible to the group from the
    // moment they join, and the channel that carries that is presence — see
    // `pre_start_visibility_test.dart`. The durable journal is history, and
    // history starts at Start ride. This test used to be named "pre-start
    // location fixes are neither persisted nor displayed", which described
    // both halves as one policy; only the persistence half was ever this
    // controller's to enforce, and only that half survives the decision.
    'the durable journal records no fixes before the ride starts',
    () async {
      final waiting = SituationalAwarenessController(
        store,
        _session,
        route: const [
          GeoPoint(latitude: 51, longitude: -1),
          GeoPoint(latitude: 51, longitude: -0.99),
        ],
        rideStarted: false,
        rideStartedAt: null,
        clock: () => now,
        idFactory: () => 'waiting-${nextId++}',
      );
      await waiting.initialize();

      await waiting.recordLocalLocation(_sample(latitude: 51, at: now));
      await waiting.ingestRemoteEvent(
        _remoteLocationEvent(
          riderId: 'early-rider',
          role: RideRole.rider,
          latitude: 51,
          now: now,
        ),
      );

      expect(
        waiting.riderLocations,
        isEmpty,
        reason:
            'the journal projection is history, and history starts at '
            'Start ride; visibility before then comes from presence',
      );
      final stored = await store.eventsForRide(_session.rideId);
      expect(
        stored,
        hasLength(1),
        reason:
            'this device authored nothing — the one row is the remote '
            'peer\'s own event, kept as received',
      );
      expect(stored.single.id, 'early-rider-event');
      waiting.dispose();
    },
  );

  test(
    'activity replay rejects fixes recorded before the start anchor',
    () async {
      final startedAt = now.add(const Duration(minutes: 1));
      await store.append(
        _remoteLocationEvent(
          riderId: 'early-rider',
          role: RideRole.rider,
          latitude: 51,
          now: now,
        ),
      );
      await store.append(
        _remoteLocationEvent(
          riderId: 'late-rider',
          role: RideRole.rider,
          latitude: 51,
          now: startedAt,
        ),
      );
      final started = SituationalAwarenessController(
        store,
        _session,
        route: const [
          GeoPoint(latitude: 51, longitude: -1),
          GeoPoint(latitude: 51, longitude: -0.99),
        ],
        rideStarted: true,
        rideStartedAt: startedAt,
        clock: () => startedAt,
        idFactory: () => 'started-${nextId++}',
      );

      await started.initialize();

      expect(started.riderLocations.map((location) => location.riderId), [
        'late-rider',
      ]);
      started.dispose();
    },
  );

  test(
    'hazard report deduplicates, persists, expires, and can clear',
    () async {
      final first = await controller.reportHazard(
        type: HazardType.debris,
        severity: HazardSeverity.caution,
        position: const GeoPoint(latitude: 51, longitude: -1),
      );
      now = now.add(const Duration(minutes: 2));
      final confirmed = await controller.reportHazard(
        type: HazardType.debris,
        severity: HazardSeverity.serious,
        position: const GeoPoint(latitude: 51.0002, longitude: -1),
      );

      expect(confirmed?.id, first?.id);
      expect(controller.activeHazards.single.confirmations, 2);
      expect(controller.activeHazards.single.severity, HazardSeverity.serious);

      await controller.clearHazard(first!.id);
      expect(controller.activeHazards, isEmpty);
      final events = await store.eventsForRide(_session.rideId);
      expect(events.last.type, RideEventType.hazardCleared);
    },
  );

  test('riders can report enforcement sightings to the group', () async {
    for (final type in [HazardType.policeActivity, HazardType.speedCamera]) {
      final report = await controller.reportHazard(
        type: type,
        severity: HazardSeverity.serious,
        position: const GeoPoint(latitude: 51, longitude: -1),
      );

      expect(report, isNotNull);
      expect(report!.type, type);
      expect(report.source, HazardSource.rider);
    }

    expect(controller.activeHazards, hasLength(2));
    expect(await store.eventsForRide(_session.rideId), hasLength(2));
  });

  test('event replay restores active hazards', () async {
    final hazard = await controller.reportHazard(
      type: HazardType.roadworks,
      severity: HazardSeverity.caution,
      position: const GeoPoint(latitude: 51, longitude: -1),
    );
    await controller.recordLocalLocation(_sample(latitude: 51.002, at: now));

    final restored = _controller(
      store: store,
      clock: () => now,
      idFactory: () => 'restored-${nextId++}',
    );
    await restored.initialize();

    expect(restored.activeHazards.single.id, hazard?.id);
    restored.dispose();
  });

  test('remote events require ride match and a valid signature', () async {
    final factory = SituationEventFactory(
      session: _session,
      clock: () => now,
      idFactory: () => 'remote-event',
    );
    final location = RiderLocation(
      riderId: 'remote-rider',
      displayName: 'Remote',
      role: RideRole.rider,
      sample: _sample(latitude: 51, at: now),
      receivedAt: now,
    );
    final valid = factory.create(
      type: RideEventType.riderLocationUpdated,
      payload: {'location': location.toJson()},
    );

    await controller.ingestRemoteEvent(valid);
    expect(controller.riderLocations.map((item) => item.riderId), [
      'remote-rider',
    ]);

    final tampered = RideEvent(
      id: valid.id,
      rideId: valid.rideId,
      deviceId: valid.deviceId,
      type: valid.type,
      priority: valid.priority,
      createdAt: valid.createdAt,
      payload: {'location': location.toJson()..['displayName'] = 'Tampered'},
      signature: valid.signature,
    );
    expect(
      () => controller.ingestRemoteEvent(tampered),
      throwsA(isA<FormatException>()),
    );
  });

  test('updated local role is used by subsequent location beacons', () async {
    controller.updateLocalSession(
      _session.copyWith(role: RideRole.rider),
    );

    await controller.recordLocalLocation(_sample(latitude: 51, at: now));

    expect(controller.localLocation?.role, RideRole.rider);
  });

  test(
    'refreshing the same provider incident does not invent confirmations',
    () async {
      final provider = _RefreshingTrafficProvider(now);
      final live = SituationalAwarenessController(
        store,
        _session,
        route: const [
          GeoPoint(latitude: 51, longitude: -1),
          GeoPoint(latitude: 51, longitude: -0.99),
        ],
        externalProviders: [provider],
        clock: () => now,
        idFactory: () => 'external-${nextId++}',
      );
      await live.initialize();

      await live.refreshExternalHazards();
      await live.refreshExternalHazards();

      expect(live.activeHazards, hasLength(1));
      expect(live.activeHazards.single.id, 'tomtom-incident');
      expect(live.activeHazards.single.confirmations, 4);
      live.dispose();
    },
  );

  test('unavailable Waze adapter remains explicit and is never fetched', () {
    final provider = controller.externalProviders.single;

    expect(provider, isA<WazeReadHazardProvider>());
    expect(provider.status.state, ExternalHazardProviderState.unavailable);
    expect(provider.status.canFetch, isFalse);
  });
}

class _RefreshingTrafficProvider implements ExternalHazardProvider {
  _RefreshingTrafficProvider(this.now);

  final DateTime now;
  var fetchCount = 0;

  @override
  String get displayName => 'Live traffic';

  @override
  String get id => 'tomtom-traffic';

  @override
  ExternalHazardProviderStatus get status => const ExternalHazardProviderStatus(
    state: ExternalHazardProviderState.configured,
    message: 'Configured',
  );

  @override
  Future<ExternalHazardFetchResult> fetch(ExternalHazardQuery query) async {
    fetchCount += 1;
    return ExternalHazardFetchResult(
      status: ExternalHazardProviderStatus(
        state: ExternalHazardProviderState.ready,
        message: 'Ready',
        lastUpdatedAt: now.add(Duration(minutes: fetchCount)),
      ),
      hazards: [
        HazardReport(
          id: 'tomtom-incident',
          rideId: query.rideId,
          type: HazardType.roadworks,
          severity: HazardSeverity.serious,
          position: const GeoPoint(latitude: 51, longitude: -0.995),
          reportedAt: now,
          updatedAt: now.add(Duration(minutes: fetchCount)),
          expiresAt: now.add(const Duration(hours: 1)),
          reporterId: id,
          source: HazardSource.externalProvider,
          providerId: id,
          confirmations: 4,
        ),
      ],
    );
  }
}

SituationalAwarenessController _controller({
  required InMemoryEventStore store,
  required DateTime Function() clock,
  required String Function() idFactory,
}) => SituationalAwarenessController(
  store,
  _session,
  route: const [
    GeoPoint(latitude: 51, longitude: -1),
    GeoPoint(latitude: 51, longitude: -0.99),
  ],
  externalProviders: const [WazeReadHazardProvider()],
  clock: clock,
  idFactory: idFactory,
);

final _session = RideSession(
  rideId: 'ride',
  rideCode: 'ABC123',
  inviteSecret: 'shared-secret',
  joinToken: 'test-join-token-0123456789',
  localRiderId: 'local-rider',
  displayName: 'Oliver',
  role: RideRole.lead,
  joinedAt: DateTime.utc(2026, 7, 16),
);

LocationSample _sample({required double latitude, required DateTime at}) =>
    LocationSample(
      position: GeoPoint(latitude: latitude, longitude: -0.995),
      recordedAt: at,
      accuracyMeters: 5,
    );

RideEvent _remoteLocationEvent({
  required String riderId,
  required RideRole role,
  required double latitude,
  required DateTime now,
}) {
  final factory = SituationEventFactory(
    session: _session,
    clock: () => now,
    idFactory: () => '$riderId-event',
  );
  final location = RiderLocation(
    riderId: riderId,
    displayName: riderId,
    role: role,
    sample: _sample(latitude: latitude, at: now),
    receivedAt: now,
  );
  return factory.create(
    type: RideEventType.riderLocationUpdated,
    payload: {'location': location.toJson()},
  );
}
