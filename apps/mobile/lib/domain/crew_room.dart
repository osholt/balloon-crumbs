import 'flight_role.dart';

class CrewRoomOperation {
  const CrewRoomOperation({
    required this.rideId,
    required this.rideCode,
    required this.inviteSecret,
    required this.joinToken,
    this.authorityRootPublicKey,
  });

  final String rideId;
  final String rideCode;
  final String inviteSecret;
  final String joinToken;
  final String? authorityRootPublicKey;

  Map<String, Object?> toJson() => {
    'rideId': rideId,
    'rideCode': rideCode,
    'inviteSecret': inviteSecret,
    'resolveToken': joinToken,
    if (authorityRootPublicKey != null)
      'authorityRootPublicKey': authorityRootPublicKey,
  };

  factory CrewRoomOperation.fromJson(Map<String, Object?> json) {
    final rideId = json['rideId'];
    final rideCode = json['rideCode'];
    final inviteSecret = json['inviteSecret'];
    final joinToken = json['resolveToken'];
    final authorityRootPublicKey = json['authorityRootPublicKey'];
    if (rideId is! String ||
        rideId.isEmpty ||
        rideCode is! String ||
        !RegExp(r'^\d{6}$').hasMatch(rideCode) ||
        inviteSecret is! String ||
        inviteSecret.length < 16 ||
        joinToken is! String ||
        joinToken.length < 16 ||
        (authorityRootPublicKey != null &&
            (authorityRootPublicKey is! String ||
                !RegExp(
                  r'^[A-Za-z0-9_-]{43}$',
                ).hasMatch(authorityRootPublicKey)))) {
      throw const FormatException('Crew room operation is invalid.');
    }
    return CrewRoomOperation(
      rideId: rideId,
      rideCode: rideCode,
      inviteSecret: inviteSecret,
      joinToken: joinToken,
      authorityRootPublicKey: authorityRootPublicKey as String?,
    );
  }
}

class CrewRoomMembership {
  const CrewRoomMembership({
    required this.roomId,
    required this.alias,
    required this.deviceId,
    required this.deviceCredential,
    required this.displayName,
    required this.flightRole,
    required this.owner,
    required this.operationGeneration,
    required this.operationExpiresAt,
    this.vehicleLabel = 'Land Rover',
    this.inviteToken,
  });

  final String roomId;
  final String alias;
  final String deviceId;
  final String deviceCredential;
  final String displayName;
  final FlightRole flightRole;
  final String vehicleLabel;
  final bool owner;
  final int operationGeneration;
  final DateTime operationExpiresAt;
  final String? inviteToken;

  CrewRoomMembership copyWith({
    String? alias,
    bool? owner,
    int? operationGeneration,
    DateTime? operationExpiresAt,
    String? inviteToken,
  }) => CrewRoomMembership(
    roomId: roomId,
    alias: alias ?? this.alias,
    deviceId: deviceId,
    deviceCredential: deviceCredential,
    displayName: displayName,
    flightRole: flightRole,
    vehicleLabel: vehicleLabel,
    owner: owner ?? this.owner,
    operationGeneration: operationGeneration ?? this.operationGeneration,
    operationExpiresAt: operationExpiresAt ?? this.operationExpiresAt,
    inviteToken: inviteToken ?? this.inviteToken,
  );

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'alias': alias,
    'deviceId': deviceId,
    'deviceCredential': deviceCredential,
    'displayName': displayName,
    'flightRole': flightRole.name,
    'vehicleLabel': vehicleLabel,
    'owner': owner,
    'operationGeneration': operationGeneration,
    'operationExpiresAt': operationExpiresAt.toUtc().toIso8601String(),
    if (inviteToken != null) 'inviteToken': inviteToken,
  };

  factory CrewRoomMembership.fromJson(Map<String, Object?> json) {
    final alias = normaliseCrewRoomAlias(json['alias']);
    final roleName = json['flightRole'];
    final role = roleName is String
        ? FlightRole.values.where((item) => item.name == roleName).firstOrNull
        : null;
    final roomId = json['roomId'];
    final deviceId = json['deviceId'];
    final credential = json['deviceCredential'];
    final displayName = json['displayName'];
    final owner = json['owner'];
    final generation = json['operationGeneration'];
    final expires = json['operationExpiresAt'];
    final inviteToken = json['inviteToken'];
    if (roomId is! String ||
        roomId.isEmpty ||
        deviceId is! String ||
        deviceId.isEmpty ||
        credential is! String ||
        !RegExp(r'^crd1_[A-Za-z0-9_-]{43}$').hasMatch(credential) ||
        displayName is! String ||
        displayName.isEmpty ||
        role == null ||
        owner is! bool ||
        generation is! int ||
        generation < 1 ||
        expires is! String ||
        (inviteToken != null &&
            (inviteToken is! String ||
                !RegExp(r'^cri1_[A-Za-z0-9_-]{43}$').hasMatch(inviteToken)))) {
      throw const FormatException('Crew room membership is invalid.');
    }
    return CrewRoomMembership(
      roomId: roomId,
      alias: alias,
      deviceId: deviceId,
      deviceCredential: credential,
      displayName: displayName,
      flightRole: role,
      vehicleLabel: json['vehicleLabel'] is String
          ? json['vehicleLabel']! as String
          : 'Land Rover',
      owner: owner,
      operationGeneration: generation,
      operationExpiresAt: DateTime.parse(expires).toLocal(),
      inviteToken: inviteToken as String?,
    );
  }
}

class CrewRoomDevice {
  const CrewRoomDevice({
    required this.deviceId,
    required this.displayName,
    required this.owner,
    required this.revoked,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String displayName;
  final bool owner;
  final bool revoked;
  final DateTime lastSeenAt;

  factory CrewRoomDevice.fromJson(Map<String, Object?> json) => CrewRoomDevice(
    deviceId: json['deviceId']! as String,
    displayName: json['displayName']! as String,
    owner: json['owner']! as bool,
    revoked: json['revoked']! as bool,
    lastSeenAt: DateTime.parse(json['lastSeenAt']! as String).toLocal(),
  );
}

String normaliseCrewRoomAlias(Object? value) {
  if (value is! String) {
    throw const FormatException('Enter a crew room alias.');
  }
  final normalised = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9]{5,12}$').hasMatch(normalised)) {
    throw const FormatException(
      'Use 5–12 letters or numbers for the crew room alias.',
    );
  }
  return normalised;
}
