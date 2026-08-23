import 'dart:math';

import 'package:balloon_crumbs/controllers/ride_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/data/in_memory_session_store.dart';
import 'package:balloon_crumbs/domain/craft.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/ride_join_payload.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/internet/internet_relay_client.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/services/chase_guidance_target.dart';
import 'package:balloon_crumbs/services/nearby_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP3 wiring: the controller writes craft events to the journal and reads the
/// roster back out of it.
void main() {
  late RideController controller;
  late int id;

  setUp(() async {
    id = 0;
    controller = RideController(
      InMemoryEventStore(),
      InMemorySessionStore(),
      const _FakeNearbyBridge(),
      clock: () => DateTime.utc(2026, 8, 17, 10),
      idFactory: () => 'id-${(id++).toString().padLeft(3, '0')}',
      random: Random(42),
      rideCodeDirectory: _InMemoryRideCodeDirectory(),
    );
    await controller.initialize();
    await controller.createRide('Oliver');
  });

  tearDown(() => controller.dispose());

  Future<RideController> joinedAs(
    FlightRole role, {
    String vehicleLabel = 'Land Rover',
  }) async {
    final flight = controller.session!;
    final joined = RideController(
      InMemoryEventStore(),
      InMemorySessionStore(),
      const _FakeNearbyBridge(),
      clock: () => DateTime.utc(2026, 8, 17, 10, 1),
      idFactory: () => 'joined-${(id++).toString().padLeft(3, '0')}',
      random: Random(84),
      rideCodeDirectory: _InMemoryRideCodeDirectory(),
    );
    addTearDown(joined.dispose);
    await joined.initialize();
    await joined.joinRideFromInvitation(
      RideJoinPayload(
        rideId: flight.rideId,
        rideCode: flight.rideCode,
        inviteSecret: flight.inviteSecret,
        joinToken: flight.joinToken,
      ),
      'Alex',
      flightRole: role,
      vehicleLabel: vehicleLabel,
    );
    return joined;
  }

  test('a new flight registers and attaches its balloon atomically', () {
    final roster = controller.resolveCraftRoster();
    expect(roster.balloons, hasLength(1));
    expect(roster.balloon?.id, controller.localCraftId);
    expect(controller.localCraft?.id, controller.localCraftId);
    expect(controller.localCraft?.crewCount, 1);
  });

  test(
    'the pilot registers the balloon and attaches this device to it',
    () async {
      final balloonId = controller.localCraftId!;
      expect(controller.localCraft?.id, balloonId);

      final roster = controller.resolveCraftRoster();
      expect(roster.balloons, hasLength(1));
      expect(roster.balloon!.craft.label, 'Balloon');
      expect(controller.localCraft?.id, balloonId);
      // No fix has been reported yet, and the roster says which kind of nothing
      // that is rather than inventing a position.
      expect(roster.balloon!.fix.hasFix, isFalse);
    },
  );

  test(
    're-registering a craft id updates it rather than duplicating it',
    () async {
      // Two devices can race to introduce the balloon. They must converge, not
      // put two aircraft on the map.
      final balloonId = controller.localCraftId!;
      await controller.registerCraft(
        craftId: balloonId,
        kind: CraftKind.balloon,
        label: 'Balloon',
      );
      await controller.registerCraft(
        craftId: balloonId,
        kind: CraftKind.balloon,
        label: 'G-ABCD',
      );

      final roster = controller.resolveCraftRoster();
      expect(roster.balloons, hasLength(1));
      expect(roster.balloon!.craft.label, 'G-ABCD');
    },
  );

  test(
    'moving a device between crafts is one event, not a leave and a join',
    () async {
      await controller.registerCraft(
        craftId: 'v1',
        kind: CraftKind.vehicle,
        label: 'Land Rover',
      );

      expect(controller.localCraft?.id, controller.localCraftId);

      await controller.attachLocalDeviceToCraft('v1');
      expect(controller.localCraft?.id, 'v1');
      expect(
        controller.resolveCraftRoster().balloon!.crewCount,
        0,
        reason: 'the device is aboard one craft at a time',
      );
    },
  );

  test('attaching to a craft nobody registered is refused', () {
    // Better to refuse than to write an event that reconciles to nothing.
    expect(controller.attachLocalDeviceToCraft('ghost'), completion(isFalse));
  });

  group('authority', () {
    test('a non-pilot cannot introduce the balloon', () async {
      final crew = await joinedAs(FlightRole.balloonCrew);
      expect(crew.hasFlightAuthority, isFalse);

      expect(
        await crew.registerCraft(
          craftId: 'another-balloon',
          kind: CraftKind.balloon,
          label: 'Balloon',
        ),
        isFalse,
      );
      expect(crew.resolveCraftRoster().balloons, hasLength(1));
    });

    test(
      'a chase vehicle can register itself without the pilot acting',
      () async {
        final crew = await joinedAs(FlightRole.chaseCrew);

        // A crew joining mid-flight must not need the pilot to press something
        // while they are flying.
        expect(
          await crew.registerCraft(
            craftId: 'v2',
            kind: CraftKind.vehicle,
            label: 'Vehicle 2',
          ),
          isTrue,
        );
        expect(crew.resolveCraftRoster().byId('v2'), isNotNull);
      },
    );

    test('only the pilot nominates a craft reporting device', () async {
      final balloonId = controller.localCraftId!;
      final deviceId = controller.session!.localRiderId;

      expect(
        await controller.nominateCraftPrimaryDevice(
          craftId: balloonId,
          deviceId: deviceId,
        ),
        isTrue,
      );
      expect(
        controller.resolveCraftRoster().balloon!.primaryDeviceId,
        deviceId,
      );

      final crew = await joinedAs(FlightRole.balloonCrew);
      expect(
        await crew.nominateCraftPrimaryDevice(
          craftId: crew.localCraftId!,
          deviceId: crew.session!.localRiderId,
        ),
        isFalse,
      );
    });

    test('nominating a device that is not aboard is refused', () async {
      // Writing it would silently do nothing at election time, which is worse
      // than saying no.
      expect(
        await controller.nominateCraftPrimaryDevice(
          craftId: controller.localCraftId!,
          deviceId: 'someone-elses-phone',
        ),
        isFalse,
      );
    });
  });

  group('chase assignment', () {
    setUp(() async {
      await controller.registerCraft(
        craftId: 'v1',
        kind: CraftKind.vehicle,
        label: 'Land Rover',
      );
    });

    test('a vehicle is pointed at the balloon and can be cleared', () async {
      expect(
        await controller.assignChase(
          vehicleCraftId: 'v1',
          targetCraftId: controller.localCraftId,
        ),
        isTrue,
      );
      expect(
        controller.resolveCraftRoster().byId('v1')!.craft.chasing,
        controller.localCraftId,
      );

      expect(
        await controller.assignChase(vehicleCraftId: 'v1', targetCraftId: null),
        isTrue,
      );
      expect(controller.resolveCraftRoster().byId('v1')!.craft.chasing, isNull);
    });

    test('a balloon cannot be given something to chase', () async {
      expect(
        await controller.assignChase(
          vehicleCraftId: controller.localCraftId!,
          targetCraftId: 'v1',
        ),
        isFalse,
      );
    });

    test('a vehicle cannot be sent to chase another vehicle', () async {
      await controller.registerCraft(
        craftId: 'v2',
        kind: CraftKind.vehicle,
        label: 'Vehicle 2',
      );

      expect(
        await controller.assignChase(vehicleCraftId: 'v1', targetCraftId: 'v2'),
        isFalse,
      );
    });
  });

  test('a chaser records a target choice against their vehicle', () async {
    final driver = await joinedAs(FlightRole.chaseDriver);

    expect(
      await driver.setLocalChaseGuidanceTarget(ChaseGuidanceTarget.landingArea),
      isTrue,
    );
    expect(
      driver.localChaseGuidanceSelection?.target,
      ChaseGuidanceTarget.landingArea,
    );
    expect(driver.events.last.type, RideEventType.chaseGuidanceTargetSelected);
    expect(driver.events.last.payload['craftId'], driver.localCraftId);
  });

  test('a balloon device cannot set chase guidance', () async {
    expect(
      await controller.setLocalChaseGuidanceTarget(ChaseGuidanceTarget.balloon),
      isFalse,
    );
  });

  test('the roster survives a journal replay', () async {
    await controller.registerCraft(
      craftId: 'v1',
      kind: CraftKind.vehicle,
      label: 'Land Rover',
    );
    await controller.assignChase(
      vehicleCraftId: 'v1',
      targetCraftId: controller.localCraftId,
    );

    // The same events reduced twice must give the same answer: this is what a
    // restarted phone and a peer receiving the backlog both do.
    final first = controller.resolveCraftRoster();
    final second = controller.resolveCraftRoster();

    expect(second.crafts.map((c) => c.id), first.crafts.map((c) => c.id));
    expect(second.byId('v1')!.craft.chasing, controller.localCraftId);
    expect(second.balloon!.crewCount, 1);
  });

  group('legacy assignment repair', () {
    Future<({RideController controller, InMemoryEventStore events})>
    restoreLegacy(RideRole legacyRole) async {
      final sessions = InMemorySessionStore();
      final events = InMemoryEventStore();
      final persisted =
          RideSession(
              rideId: 'legacy-flight',
              rideCode: '123456',
              inviteSecret: 'legacy-secret-with-enough-entropy',
              joinToken: 'legacy-token-with-enough-entropy',
              localRiderId: 'legacy-device',
              displayName: 'Alex',
              role: legacyRole,
              joinedAt: DateTime.utc(2026, 8, 1),
            ).toJson()
            ..remove('flightRole')
            ..remove('localCraftId');
      await sessions.save(RideSession.fromJson(persisted));
      var eventId = 0;
      final restored = RideController(
        events,
        sessions,
        const _FakeNearbyBridge(),
        clock: () => DateTime.utc(2026, 8, 23, 9),
        idFactory: () => 'repair-${eventId++}',
        rideCodeDirectory: _InMemoryRideCodeDirectory(),
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      return (controller: restored, events: events);
    }

    test('the legacy creator explicitly restores pilot and balloon', () async {
      final fixture = await restoreLegacy(RideRole.lead);
      expect(fixture.controller.hasFlightAuthority, isFalse);
      expect(fixture.controller.session!.requiresFlightAssignment, isTrue);

      await fixture.controller.repairFlightAssignment(role: FlightRole.pilot);

      expect(fixture.controller.errorMessage, isNull);
      expect(fixture.controller.localFlightRole, FlightRole.pilot);
      expect(fixture.controller.hasFlightAuthority, isTrue);
      expect(fixture.controller.session!.requiresFlightAssignment, isFalse);
      expect(fixture.controller.localCraft?.craft.kind, CraftKind.balloon);
      expect(fixture.controller.localCraft?.primaryDeviceId, 'legacy-device');
      final recorded = await fixture.events.eventsForRide('legacy-flight');
      expect(
        recorded.map((event) => event.type),
        containsAll(<RideEventType>[
          RideEventType.roleChanged,
          RideEventType.craftRegistered,
          RideEventType.deviceAttachedToCraft,
          RideEventType.craftPrimaryDeviceNominated,
        ]),
      );
    });

    test('a legacy participant repairs into a named chase vehicle', () async {
      final fixture = await restoreLegacy(RideRole.rider);

      await fixture.controller.repairFlightAssignment(
        role: FlightRole.chaseDriver,
        vehicleLabel: '  Land   Rover  ',
      );

      expect(fixture.controller.errorMessage, isNull);
      expect(fixture.controller.localFlightRole, FlightRole.chaseDriver);
      expect(fixture.controller.hasFlightAuthority, isFalse);
      expect(fixture.controller.localCraft?.craft.kind, CraftKind.vehicle);
      expect(fixture.controller.localCraft?.craft.label, 'Land Rover');
    });

    test('a legacy participant cannot claim pilot authority', () async {
      final fixture = await restoreLegacy(RideRole.rider);

      await fixture.controller.repairFlightAssignment(role: FlightRole.pilot);

      expect(fixture.controller.errorMessage, isNotNull);
      expect(fixture.controller.localFlightRole, FlightRole.observer);
      expect(fixture.controller.session!.requiresFlightAssignment, isTrue);
      expect(fixture.controller.hasFlightAuthority, isFalse);
    });
  });
}

class _FakeNearbyBridge extends NearbyBridge {
  const _FakeNearbyBridge();

  @override
  Future<NearbyCapabilities> capabilities() async => const NearbyCapabilities(
    platform: 'test',
    nativeBridgeReady: true,
    nearbyApiLinked: false,
    status: 'phase0',
  );
}

class _InMemoryRideCodeDirectory implements RideCodeDirectory {
  final _credentials = <String, RideCodeCredentials>{};

  @override
  Future<void> register(RideSession session) async {
    final existing = _credentials[session.rideCode];
    if (existing != null && existing.rideId != session.rideId) {
      throw const RideCodeDirectoryException(
        'Ride code is already in use.',
        codeConflict: true,
      );
    }
    _credentials[session.rideCode] = RideCodeCredentials(
      rideId: session.rideId,
      rideCode: session.rideCode,
      inviteSecret: session.inviteSecret,
      joinToken: session.joinToken,
    );
  }

  @override
  Future<RideCodeCredentials> resolve(
    String rideCode, {
    String? joinToken,
  }) async {
    final credentials = _credentials[rideCode];
    if (credentials == null) {
      throw const RideCodeDirectoryException('That ride code is not active.');
    }
    return credentials;
  }

  @override
  void close() {}
}
