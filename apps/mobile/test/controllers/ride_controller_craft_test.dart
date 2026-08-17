import 'dart:math';

import 'package:balloon_crumbs/controllers/ride_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/data/in_memory_session_store.dart';
import 'package:balloon_crumbs/domain/craft.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/internet/internet_relay_client.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
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

  test('a flight starts with no crafts until one is registered', () {
    expect(controller.resolveCraftRoster().crafts, isEmpty);
    expect(controller.resolveCraftRoster().balloon, isNull);
    expect(controller.localCraft, isNull);
  });

  test('the pilot registers the balloon and attaches this device to it', () async {
    expect(
      await controller.registerCraft(
        craftId: 'balloon',
        kind: CraftKind.balloon,
        label: 'Balloon',
      ),
      isTrue,
    );
    expect(await controller.attachLocalDeviceToCraft('balloon'), isTrue);

    final roster = controller.resolveCraftRoster();
    expect(roster.balloons, hasLength(1));
    expect(roster.balloon!.craft.label, 'Balloon');
    expect(controller.localCraft?.id, 'balloon');
    // No fix has been reported yet, and the roster says which kind of nothing
    // that is rather than inventing a position.
    expect(roster.balloon!.fix.hasFix, isFalse);
  });

  test('re-registering a craft id updates it rather than duplicating it', () async {
    // Two devices can race to introduce the balloon. They must converge, not
    // put two aircraft on the map.
    await controller.registerCraft(
      craftId: 'balloon',
      kind: CraftKind.balloon,
      label: 'Balloon',
    );
    await controller.registerCraft(
      craftId: 'balloon',
      kind: CraftKind.balloon,
      label: 'G-ABCD',
    );

    final roster = controller.resolveCraftRoster();
    expect(roster.balloons, hasLength(1));
    expect(roster.balloon!.craft.label, 'G-ABCD');
  });

  test('moving a device between crafts is one event, not a leave and a join', () async {
    await controller.registerCraft(
      craftId: 'balloon',
      kind: CraftKind.balloon,
      label: 'Balloon',
    );
    await controller.registerCraft(
      craftId: 'v1',
      kind: CraftKind.vehicle,
      label: 'Land Rover',
    );

    await controller.attachLocalDeviceToCraft('balloon');
    expect(controller.localCraft?.id, 'balloon');

    await controller.attachLocalDeviceToCraft('v1');
    expect(controller.localCraft?.id, 'v1');
    expect(
      controller.resolveCraftRoster().balloon!.crewCount,
      0,
      reason: 'the device is aboard one craft at a time',
    );
  });

  test('attaching to a craft nobody registered is refused', () {
    // Better to refuse than to write an event that reconciles to nothing.
    expect(controller.attachLocalDeviceToCraft('ghost'), completion(isFalse));
  });

  group('authority', () {
    test('a non-pilot cannot introduce the balloon', () async {
      // The creator holds authority in this session, so drop it to prove the
      // gate rather than asserting it from the happy path.
      await controller.setRole(RideRole.rider);
      expect(controller.hasFlightAuthority, isFalse);

      expect(
        await controller.registerCraft(
          craftId: 'balloon',
          kind: CraftKind.balloon,
          label: 'Balloon',
        ),
        isFalse,
      );
      expect(controller.resolveCraftRoster().balloons, isEmpty);
    });

    test('a chase vehicle can register itself without the pilot acting', () async {
      await controller.setRole(RideRole.rider);

      // A crew joining mid-flight must not need the pilot to press something
      // while they are flying.
      expect(
        await controller.registerCraft(
          craftId: 'v2',
          kind: CraftKind.vehicle,
          label: 'Vehicle 2',
        ),
        isTrue,
      );
      expect(controller.resolveCraftRoster().vehicles, hasLength(1));
    });

    test('only the pilot nominates a craft reporting device', () async {
      await controller.registerCraft(
        craftId: 'balloon',
        kind: CraftKind.balloon,
        label: 'Balloon',
      );
      await controller.attachLocalDeviceToCraft('balloon');
      final deviceId = controller.session!.localRiderId;

      expect(
        await controller.nominateCraftPrimaryDevice(
          craftId: 'balloon',
          deviceId: deviceId,
        ),
        isTrue,
      );
      expect(
        controller.resolveCraftRoster().balloon!.primaryDeviceId,
        deviceId,
      );

      await controller.setRole(RideRole.rider);
      expect(
        await controller.nominateCraftPrimaryDevice(
          craftId: 'balloon',
          deviceId: deviceId,
        ),
        isFalse,
      );
    });

    test('nominating a device that is not aboard is refused', () async {
      await controller.registerCraft(
        craftId: 'balloon',
        kind: CraftKind.balloon,
        label: 'Balloon',
      );

      // Writing it would silently do nothing at election time, which is worse
      // than saying no.
      expect(
        await controller.nominateCraftPrimaryDevice(
          craftId: 'balloon',
          deviceId: 'someone-elses-phone',
        ),
        isFalse,
      );
    });
  });

  group('chase assignment', () {
    setUp(() async {
      await controller.registerCraft(
        craftId: 'balloon',
        kind: CraftKind.balloon,
        label: 'Balloon',
      );
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
          targetCraftId: 'balloon',
        ),
        isTrue,
      );
      expect(controller.resolveCraftRoster().byId('v1')!.craft.chasing, 'balloon');

      expect(
        await controller.assignChase(vehicleCraftId: 'v1', targetCraftId: null),
        isTrue,
      );
      expect(controller.resolveCraftRoster().byId('v1')!.craft.chasing, isNull);
    });

    test('a balloon cannot be given something to chase', () async {
      expect(
        await controller.assignChase(
          vehicleCraftId: 'balloon',
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

  test('the roster survives a journal replay', () async {
    await controller.registerCraft(
      craftId: 'balloon',
      kind: CraftKind.balloon,
      label: 'Balloon',
    );
    await controller.registerCraft(
      craftId: 'v1',
      kind: CraftKind.vehicle,
      label: 'Land Rover',
    );
    await controller.attachLocalDeviceToCraft('balloon');
    await controller.assignChase(
      vehicleCraftId: 'v1',
      targetCraftId: 'balloon',
    );

    // The same events reduced twice must give the same answer: this is what a
    // restarted phone and a peer receiving the backlog both do.
    final first = controller.resolveCraftRoster();
    final second = controller.resolveCraftRoster();

    expect(second.crafts.map((c) => c.id), first.crafts.map((c) => c.id));
    expect(second.byId('v1')!.craft.chasing, 'balloon');
    expect(second.balloon!.crewCount, 1);
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
