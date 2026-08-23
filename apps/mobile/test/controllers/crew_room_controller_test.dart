import 'package:balloon_crumbs/controllers/ride_controller.dart';
import 'package:balloon_crumbs/data/in_memory_crew_room_store.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/data/in_memory_session_store.dart';
import 'package:balloon_crumbs/domain/crew_room.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/internet/crew_room_directory.dart';
import 'package:balloon_crumbs/internet/internet_relay_client.dart';
import 'package:balloon_crumbs/services/nearby_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeCrewRoomDirectory directory;
  late InMemoryCrewRoomStore roomStore;
  late RideController controller;
  var id = 0;

  RideController buildController({
    InMemoryCrewRoomStore? store,
    String installationId = 'stable-installation',
  }) => RideController(
    InMemoryEventStore(),
    InMemorySessionStore(),
    const _NoNearby(),
    idFactory: () => 'event-${id++}',
    installationId: installationId,
    rideCodeDirectory: _NoRideCodes(),
    crewRoomDirectory: directory,
    crewRoomStore: store ?? roomStore,
  );

  setUp(() async {
    directory = _FakeCrewRoomDirectory();
    roomStore = InMemoryCrewRoomStore();
    controller = buildController();
    await controller.initialize();
  });

  tearDown(() => controller.dispose());

  test(
    'TUCKER creates fresh isolated operations under one durable room',
    () async {
      await controller.createRide('Oliver', crewRoomAlias: 'tucker');

      expect(controller.errorMessage, isNull);
      expect(controller.currentCrewRoom?.alias, 'TUCKER');
      expect(controller.currentCrewRoom?.owner, isTrue);
      expect(controller.currentCrewRoom?.inviteToken, startsWith('cri1_'));
      final firstRideId = controller.session!.rideId;
      final membership = controller.currentCrewRoom!;

      await controller.startRide();
      await controller.endRide();
      await controller.startNewCrewRoomOperation(
        membership,
        displayName: 'Oliver',
      );

      expect(controller.errorMessage, isNull);
      expect(controller.session!.rideId, isNot(firstRideId));
      expect(controller.session!.crewRoomId, membership.roomId);
      expect(controller.currentCrewRoom?.operationGeneration, 2);
      expect(
        controller.events.every((event) => event.rideId != firstRideId),
        isTrue,
      );
      expect(directory.startedRideIds, [controller.session!.rideId]);
    },
  );

  test(
    'a returning device opens the current room without the human alias alone',
    () async {
      await controller.createRide('Oliver', crewRoomAlias: 'TUCKER');
      final membership = controller.currentCrewRoom!;

      final restored = buildController(store: roomStore);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.crewRooms.single.alias, 'TUCKER');

      await restored.openCrewRoom(membership);

      expect(restored.errorMessage, isNull);
      expect(restored.session?.rideId, controller.session?.rideId);
      expect(restored.session?.flightRole, FlightRole.pilot);
      expect(restored.currentCrewRoom?.roomId, membership.roomId);
    },
  );

  test('a private room invitation enrols a new independent device', () async {
    await controller.createRide('Oliver', crewRoomAlias: 'TUCKER');
    final owner = controller.currentCrewRoom!;
    final joinedStore = InMemoryCrewRoomStore();
    final joined = buildController(
      store: joinedStore,
      installationId: 'nigel-installation',
    );
    addTearDown(joined.dispose);
    await joined.initialize();

    await joined.joinCrewRoom(
      alias: owner.alias,
      inviteToken: owner.inviteToken!,
      displayName: 'Nigel',
      flightRole: FlightRole.chaseDriver,
    );

    expect(joined.errorMessage, isNull);
    expect(joined.session?.rideId, controller.session?.rideId);
    expect(joined.session?.flightRole, FlightRole.chaseDriver);
    expect(joined.crewRooms.single.owner, isFalse);
    expect(joined.crewRooms.single.deviceId, isNot(owner.deviceId));
  });
}

class _FakeCrewRoomDirectory implements CrewRoomDirectory {
  CrewRoomOperation? operation;
  String? ownerDeviceId;
  int generation = 1;
  final List<String> startedRideIds = [];

  static const roomId = 'room_test';
  static const credential = 'crd1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  static const invite = 'cri1_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

  @override
  Future<CrewRoomAccess> create({
    required String alias,
    required String deviceId,
    required String displayName,
    required RideSession operation,
  }) async {
    ownerDeviceId = deviceId;
    this.operation = _operation(operation);
    return _access(alias: 'TUCKER', owner: true, inviteToken: invite);
  }

  @override
  Future<CrewRoomAccess> open(CrewRoomMembership membership) async {
    if (membership.deviceCredential != credential) {
      throw const CrewRoomDirectoryException('No access.');
    }
    return _access(
      alias: membership.alias,
      owner: membership.deviceId == ownerDeviceId,
    );
  }

  @override
  Future<CrewRoomAccess> join({
    required String alias,
    required String inviteToken,
    required String deviceId,
    required String displayName,
  }) async {
    if (inviteToken != invite) {
      throw const CrewRoomDirectoryException('No access.');
    }
    return _access(alias: alias, owner: false);
  }

  @override
  Future<CrewRoomAccess> startOperation({
    required CrewRoomMembership membership,
    required RideSession operation,
  }) async {
    generation += 1;
    this.operation = _operation(operation);
    startedRideIds.add(operation.rideId);
    return _access(
      alias: membership.alias,
      owner: true,
      inviteToken: 'cri1_CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
    );
  }

  CrewRoomAccess _access({
    required String alias,
    required bool owner,
    String? inviteToken,
  }) => CrewRoomAccess(
    roomId: roomId,
    alias: alias,
    deviceCredential: credential,
    inviteToken: inviteToken,
    operationGeneration: generation,
    operation: operation,
    operationExpiresAt: DateTime.utc(2026, 9, 1),
    owner: owner,
  );

  CrewRoomOperation _operation(RideSession session) => CrewRoomOperation(
    rideId: session.rideId,
    rideCode: session.rideCode,
    inviteSecret: session.inviteSecret,
    joinToken: session.joinToken,
  );

  @override
  Future<void> delete(CrewRoomMembership membership) async {}

  @override
  Future<List<CrewRoomDevice>> devices(CrewRoomMembership membership) async =>
      const [];

  @override
  Future<String> rename(CrewRoomMembership membership, String newAlias) async =>
      normaliseCrewRoomAlias(newAlias);

  @override
  Future<void> revoke(
    CrewRoomMembership membership,
    String targetDeviceId,
  ) async {}

  @override
  Future<void> transfer(
    CrewRoomMembership membership,
    String targetDeviceId,
  ) async {}

  @override
  void close() {}
}

class _NoRideCodes implements RideCodeDirectory {
  @override
  Future<void> register(RideSession session) async {}

  @override
  Future<RideCodeCredentials> resolve(String rideCode, {String? joinToken}) =>
      throw UnimplementedError();

  @override
  void close() {}
}

class _NoNearby implements NearbyBridge {
  const _NoNearby();

  @override
  Future<NearbyCapabilities> capabilities() async =>
      const NearbyCapabilities.unavailable();
}
