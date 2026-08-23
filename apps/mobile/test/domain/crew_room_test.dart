import 'package:balloon_crumbs/domain/crew_room.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/ride_join_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalises a memorable alias without making it a credential', () {
    expect(normaliseCrewRoomAlias('  tucker '), 'TUCKER');
    expect(() => normaliseCrewRoomAlias('four'), throwsFormatException);
    expect(() => normaliseCrewRoomAlias('TUCKER GRAVE'), throwsFormatException);
  });

  test('room membership round-trips its revocable credential', () {
    final membership = CrewRoomMembership(
      roomId: 'room-one',
      alias: 'TUCKER',
      deviceId: 'device-one',
      deviceCredential: 'crd1_${'A' * 43}',
      displayName: 'Oliver',
      flightRole: FlightRole.pilot,
      owner: true,
      operationGeneration: 2,
      operationExpiresAt: DateTime.utc(2026, 8, 26),
      inviteToken: 'cri1_${'B' * 43}',
    );

    expect(
      CrewRoomMembership.fromJson(membership.toJson()).toJson(),
      membership.toJson(),
    );
  });

  test(
    'QR carries offline flight bootstrap plus optional returning access',
    () {
      const payload = RideJoinPayload(
        rideId: 'ride-one',
        rideCode: '123456',
        inviteSecret: '0123456789abcdef',
        joinToken: 'join-token-0123456789',
        crewRoomId: 'room-one',
        crewRoomAlias: 'TUCKER',
        crewRoomInviteToken: 'cri1_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
      );

      final decoded = RideJoinPayload.decode(payload.encode());
      expect(decoded.rideId, payload.rideId);
      expect(decoded.crewRoomAlias, 'TUCKER');
      expect(decoded.crewRoomInviteToken, payload.crewRoomInviteToken);
    },
  );
}
