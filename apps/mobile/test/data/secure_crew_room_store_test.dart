import 'package:balloon_crumbs/data/secure_crew_room_store.dart';
import 'package:balloon_crumbs/domain/crew_room.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('returning credential stays in secure storage across flights', () async {
    const store = SecureCrewRoomStore();
    final membership = CrewRoomMembership(
      roomId: 'room-one',
      alias: 'TUCKER',
      deviceId: 'device-one',
      deviceCredential: 'crd1_${'A' * 43}',
      displayName: 'Oliver',
      flightRole: FlightRole.pilot,
      owner: true,
      operationGeneration: 1,
      operationExpiresAt: DateTime.utc(2026, 8, 26),
      inviteToken: 'cri1_${'B' * 43}',
    );

    await store.upsert(membership);
    final restored = (await store.loadAll()).single;

    expect(restored.alias, 'TUCKER');
    expect(restored.deviceCredential, membership.deviceCredential);
    expect(restored.inviteToken, membership.inviteToken);
    await store.delete(membership.roomId);
    expect(await store.loadAll(), isEmpty);
  });

  test('corrupt room state is removed rather than partially trusted', () async {
    await const FlutterSecureStorage().write(
      key: 'balloon_crumbs_crew_rooms_v1',
      value: '{"schemaVersion":1,"rooms":[{"alias":"TUCKER"}]}',
    );

    expect(await const SecureCrewRoomStore().loadAll(), isEmpty);
  });
}
