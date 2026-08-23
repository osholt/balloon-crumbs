import 'dart:convert';

import 'package:balloon_crumbs/domain/crew_room.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/internet/crew_room_directory.dart';
import 'package:balloon_crumbs/internet/internet_relay_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'creates a room through a generic path with a ride credential',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(_response(inviteToken: 'cri1_${'B' * 43}')),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final directory = HttpCrewRoomDirectory(
        configuration: _configuration,
        client: client,
      );

      final access = await directory.create(
        alias: 'tucker',
        deviceId: 'room-device-one',
        displayName: 'Oliver',
        operation: _session,
      );

      expect(captured.url.path, '/api/v1/crew-rooms/create');
      expect(captured.url.toString(), isNot(contains('TUCKER')));
      expect(captured.headers['authorization'], startsWith('Bearer rr1_'));
      final body = jsonDecode(captured.body) as Map<String, Object?>;
      expect(body['alias'], 'TUCKER');
      expect(access.alias, 'TUCKER');
      expect(access.operation?.rideId, _session.rideId);
      expect(access.inviteToken, startsWith('cri1_'));
    },
  );

  test(
    'a missing or revoked returning credential has one bounded error',
    () async {
      final directory = HttpCrewRoomDirectory(
        configuration: _configuration,
        client: MockClient(
          (_) async => http.Response(
            '{"error":"Crew room is not available"}',
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      await expectLater(
        directory.open(_membership),
        throwsA(
          isA<CrewRoomDirectoryException>().having(
            (error) => error.message,
            'message',
            'This device no longer has access to that crew room.',
          ),
        ),
      );
    },
  );
}

final _configuration = InternetRelayConfiguration(
  baseUri: Uri.parse('https://relay.example/api'),
);

final _session = RideSession(
  rideId: 'ride-one',
  rideCode: '123456',
  inviteSecret: '0123456789abcdef0123456789abcdef',
  joinToken: 'resolve-token-0123456789',
  localRiderId: 'rider-one',
  displayName: 'Oliver',
  role: RideRole.lead,
  joinedAt: DateTime.utc(2026, 8, 23),
);

final _membership = CrewRoomMembership(
  roomId: 'room-one',
  alias: 'TUCKER',
  deviceId: 'room-device-one',
  deviceCredential: 'crd1_${'A' * 43}',
  displayName: 'Oliver',
  flightRole: _session.flightRole,
  owner: true,
  operationGeneration: 1,
  operationExpiresAt: DateTime.utc(2026, 8, 26),
);

Map<String, Object?> _response({String? inviteToken}) => {
  'roomId': 'room-one',
  'alias': 'TUCKER',
  'deviceCredential': 'crd1_${'A' * 43}',
  'inviteToken': inviteToken,
  'operationGeneration': 1,
  'operation': {
    'rideId': _session.rideId,
    'rideCode': _session.rideCode,
    'inviteSecret': _session.inviteSecret,
    'resolveToken': _session.joinToken,
  },
  'operationExpiresAt': '2026-08-26T00:00:00Z',
  'owner': true,
};
