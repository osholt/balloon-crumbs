import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/crew_room.dart';
import '../domain/ride_session.dart';
import 'internet_relay_client.dart';

class CrewRoomAccess {
  const CrewRoomAccess({
    required this.roomId,
    required this.alias,
    required this.deviceCredential,
    required this.operationGeneration,
    required this.operationExpiresAt,
    required this.owner,
    this.inviteToken,
    this.operation,
  });

  final String roomId;
  final String alias;
  final String deviceCredential;
  final String? inviteToken;
  final int operationGeneration;
  final CrewRoomOperation? operation;
  final DateTime operationExpiresAt;
  final bool owner;

  factory CrewRoomAccess.fromJson(Map<String, Object?> json) {
    final operation = json['operation'];
    final roomId = json['roomId'];
    final credential = json['deviceCredential'];
    final generation = json['operationGeneration'];
    final expires = json['operationExpiresAt'];
    final owner = json['owner'];
    final inviteToken = json['inviteToken'];
    if (roomId is! String ||
        roomId.isEmpty ||
        credential is! String ||
        !RegExp(r'^crd1_[A-Za-z0-9_-]{43}$').hasMatch(credential) ||
        generation is! int ||
        generation < 1 ||
        expires is! String ||
        owner is! bool ||
        (inviteToken != null && inviteToken is! String)) {
      throw const FormatException('Crew room response is invalid.');
    }
    return CrewRoomAccess(
      roomId: roomId,
      alias: normaliseCrewRoomAlias(json['alias']),
      deviceCredential: credential,
      inviteToken: inviteToken as String?,
      operationGeneration: generation,
      operation: operation == null
          ? null
          : CrewRoomOperation.fromJson(
              Map<String, Object?>.from(operation as Map),
            ),
      operationExpiresAt: DateTime.parse(expires).toLocal(),
      owner: owner,
    );
  }
}

abstract interface class CrewRoomDirectory {
  Future<CrewRoomAccess> create({
    required String alias,
    required String deviceId,
    required String displayName,
    required RideSession operation,
  });

  Future<CrewRoomAccess> open(CrewRoomMembership membership);

  Future<CrewRoomAccess> join({
    required String alias,
    required String inviteToken,
    required String deviceId,
    required String displayName,
  });

  Future<CrewRoomAccess> startOperation({
    required CrewRoomMembership membership,
    required RideSession operation,
  });

  Future<List<CrewRoomDevice>> devices(CrewRoomMembership membership);

  Future<String> rename(CrewRoomMembership membership, String newAlias);

  Future<void> transfer(CrewRoomMembership membership, String targetDeviceId);

  Future<void> revoke(CrewRoomMembership membership, String targetDeviceId);

  Future<void> delete(CrewRoomMembership membership);

  void close();
}

class CrewRoomDirectoryException implements Exception {
  const CrewRoomDirectoryException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => 'CrewRoomDirectoryException: $message';
}

class HttpCrewRoomDirectory implements CrewRoomDirectory {
  factory HttpCrewRoomDirectory.fromEnvironment() => HttpCrewRoomDirectory(
    configuration: InternetRelayConfiguration.fromEnvironment(),
    client: http.Client(),
  );

  HttpCrewRoomDirectory({
    required this.configuration,
    required this.client,
    RelayClientDescriptor? descriptor,
  }) : _descriptor = descriptor ?? RelayClientDescriptor.current();

  final InternetRelayConfiguration configuration;
  final http.Client client;
  final RelayClientDescriptor _descriptor;

  @override
  Future<CrewRoomAccess> create({
    required String alias,
    required String deviceId,
    required String displayName,
    required RideSession operation,
  }) async => CrewRoomAccess.fromJson(
    await _request(
      'create',
      {
        'alias': normaliseCrewRoomAlias(alias),
        'deviceId': deviceId,
        'displayName': displayName,
        'operation': _operation(operation),
      },
      ride: operation,
      expectedStatus: 201,
    ),
  );

  @override
  Future<CrewRoomAccess> open(CrewRoomMembership membership) async =>
      CrewRoomAccess.fromJson(await _request('open', _auth(membership)));

  @override
  Future<CrewRoomAccess> join({
    required String alias,
    required String inviteToken,
    required String deviceId,
    required String displayName,
  }) async => CrewRoomAccess.fromJson(
    await _request('join', {
      'alias': normaliseCrewRoomAlias(alias),
      'inviteToken': inviteToken,
      'deviceId': deviceId,
      'displayName': displayName,
    }),
  );

  @override
  Future<CrewRoomAccess> startOperation({
    required CrewRoomMembership membership,
    required RideSession operation,
  }) async => CrewRoomAccess.fromJson(
    await _request('start-operation', {
      ..._auth(membership),
      'operation': _operation(operation),
    }, ride: operation),
  );

  @override
  Future<List<CrewRoomDevice>> devices(CrewRoomMembership membership) async {
    final json = await _request('devices', _auth(membership));
    final values = json['devices'];
    if (values is! List) {
      throw const CrewRoomDirectoryException(
        'Crew room service returned an invalid response.',
      );
    }
    return List.unmodifiable(
      values.map(
        (item) =>
            CrewRoomDevice.fromJson(Map<String, Object?>.from(item as Map)),
      ),
    );
  }

  @override
  Future<String> rename(CrewRoomMembership membership, String newAlias) async {
    final json = await _request('rename', {
      ..._auth(membership),
      'newAlias': normaliseCrewRoomAlias(newAlias),
    });
    return normaliseCrewRoomAlias(json['alias']);
  }

  @override
  Future<void> transfer(CrewRoomMembership membership, String targetDeviceId) =>
      _emptyRequest('transfer', {
        ..._auth(membership),
        'targetDeviceId': targetDeviceId,
      });

  @override
  Future<void> revoke(CrewRoomMembership membership, String targetDeviceId) =>
      _emptyRequest('revoke-device', {
        ..._auth(membership),
        'targetDeviceId': targetDeviceId,
      });

  @override
  Future<void> delete(CrewRoomMembership membership) =>
      _emptyRequest('delete', _auth(membership));

  Map<String, Object?> _auth(CrewRoomMembership membership) => {
    'alias': membership.alias,
    'deviceId': membership.deviceId,
    'deviceCredential': membership.deviceCredential,
  };

  Map<String, Object?> _operation(RideSession session) => {
    'rideId': session.rideId,
    'rideCode': session.rideCode,
    'inviteSecret': session.inviteSecret,
    'resolveToken': session.joinToken,
    if (session.authorityRootPublicKey != null)
      'authorityRootPublicKey': session.authorityRootPublicKey,
  };

  Future<Map<String, Object?>> _request(
    String action,
    Map<String, Object?> body, {
    RideSession? ride,
    int expectedStatus = 200,
  }) async {
    final response = await _send(action, body, ride: ride);
    if (response.statusCode != expectedStatus) {
      throw _failure(response.statusCode);
    }
    final contentType = response.headers['content-type']?.toLowerCase();
    if (response.bodyBytes.length > 64 * 1024 ||
        contentType == null ||
        !contentType.contains('application/json')) {
      throw const CrewRoomDirectoryException(
        'Crew room service returned an invalid response.',
      );
    }
    try {
      return Map<String, Object?>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
    } on Object {
      throw const CrewRoomDirectoryException(
        'Crew room service returned an invalid response.',
      );
    }
  }

  Future<void> _emptyRequest(String action, Map<String, Object?> body) async {
    final response = await _send(action, body);
    if (response.statusCode != 204) throw _failure(response.statusCode);
  }

  Future<http.Response> _send(
    String action,
    Map<String, Object?> body, {
    RideSession? ride,
  }) async {
    final error = configuration.configurationError;
    if (error != null) {
      throw const CrewRoomDirectoryException(
        'Crew rooms need the Balloon Crumbs service to be connected.',
      );
    }
    final headers = {
      'accept': 'application/json',
      'content-type': 'application/json',
      ..._descriptor.headers,
      if (ride != null) 'authorization': 'Bearer ${_rideBearer(ride)}',
    };
    try {
      return await client
          .post(_uri(action), headers: headers, body: jsonEncode(body))
          .timeout(configuration.bodyTimeout);
    } on TimeoutException {
      throw const CrewRoomDirectoryException(
        'Crew room service timed out. Try again.',
        retryable: true,
      );
    } on http.ClientException {
      throw const CrewRoomDirectoryException(
        'Crew room service is temporarily unavailable. Try again.',
        retryable: true,
      );
    }
  }

  Uri _uri(String action) {
    final base = configuration.baseUri!.toString().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$base/v1/crew-rooms/$action');
  }

  CrewRoomDirectoryException _failure(int status) => switch (status) {
    400 => const CrewRoomDirectoryException(
      'Check the crew room alias and try again.',
    ),
    404 => const CrewRoomDirectoryException(
      'This device no longer has access to that crew room.',
    ),
    409 => const CrewRoomDirectoryException(
      'That crew room alias is already in use.',
    ),
    429 => const CrewRoomDirectoryException(
      'Too many crew room attempts. Wait a moment and try again.',
      retryable: true,
    ),
    _ => CrewRoomDirectoryException(
      'Crew room service returned HTTP $status.',
      retryable: status >= 500,
    ),
  };

  String _rideBearer(RideSession session) {
    final digest = Hmac(sha256, utf8.encode(session.inviteSecret)).convert(
      utf8.encode('balloon-crumbs-internet-token-v1\n${session.rideId}'),
    );
    return 'rr1_${base64Url.encode(digest.bytes).replaceAll('=', '')}';
  }

  @override
  void close() => client.close();
}
