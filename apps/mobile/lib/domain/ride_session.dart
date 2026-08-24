import 'dart:convert';
import 'dart:math';

import '../features/map/craft_icon.dart';
import 'flight_role.dart';
import 'ride_coordination_mode.dart';
import 'ride_role.dart';
import 'rider_color.dart';

class RideSession {
  static const minimumSimulationRiderCount = 2;
  static const maximumSimulationRiderCount = 30;
  static const defaultSimulationRiderCount = 2;

  const RideSession({
    required this.rideId,
    required this.rideCode,
    required this.inviteSecret,
    required this.joinToken,
    required this.localRiderId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    FlightRole? flightRole,
    this.localCraftId,
    this.requiresFlightAssignment = false,
    this.isSimulation = false,
    this.simulationRiderCount = defaultSimulationRiderCount,
    this.craftStyle = craftIconStyleDefault,
    this.riderSymbol = riderSymbolDefault,
    this.riderColor = riderColorDefault,
    this.coordinationMode = RideCoordinationMode.keepTogether,
    this.rideName,
    this.crewRoomId,
    this.authorizationVersion = 1,
    this.authorityRootPublicKey,
    this.localDevicePublicKey,
  }) : flightRole =
           flightRole ??
           (role == RideRole.lead ? FlightRole.pilot : FlightRole.chaseCrew),
       assert(
         !isSimulation ||
             (simulationRiderCount >= minimumSimulationRiderCount &&
                 simulationRiderCount <= maximumSimulationRiderCount),
       );

  final String rideId;
  final String rideCode;
  final String inviteSecret;

  /// A high-entropy credential paired with [rideCode] on the internet relay.
  /// The six-digit code alone is brute-forceable over the public internet;
  /// resolving the invite secret from the relay requires this too. Only
  /// carried in the "Share" text and a smart-paste, never displayed on its
  /// own - the six digits remain what a rider reads or types.
  final String joinToken;

  /// Version one trusts only the shared flight HMAC and is retained solely for
  /// local development-alpha recovery. Version two additionally binds every
  /// accepted event to an operation-scoped device signing key.
  final int authorizationVersion;
  final String? authorityRootPublicKey;
  final String? localDevicePublicKey;

  bool get usesDeviceAuthority =>
      authorizationVersion >= 2 &&
      authorityRootPublicKey != null &&
      localDevicePublicKey != null;
  final String localRiderId;
  final String displayName;
  final RideRole role;

  /// The person's balloon-specific job. [role] remains only for mixed-version
  /// relay compatibility and must not drive the live experience or authority.
  final FlightRole flightRole;

  /// The stable craft this device is aboard. The journal attachment is the
  /// shared source of truth; retaining the id here lets a restored device reach
  /// the correct assignment/recovery flow before relay replay completes.
  final String? localCraftId;

  /// True only for a session written by a build that did not persist a flight
  /// role. Such a session is least-privileged until the assignment repair flow
  /// has run; it must never inherit pilot authority merely from `lead`.
  final bool requiresFlightAssignment;
  final DateTime joinedAt;
  final bool isSimulation;
  final int simulationRiderCount;
  final CraftIconStyle craftStyle;
  final RiderSymbol riderSymbol;
  final RiderColor riderColor;
  final RideCoordinationMode coordinationMode;

  /// Optional, leader-chosen at creation. Never required: rides are always
  /// identifiable by their six-digit code even with no name set.
  final String? rideName;

  /// Opaque persistent room identity, never an access credential.
  final String? crewRoomId;

  RideSession copyWith({
    RideRole? role,
    FlightRole? flightRole,
    String? localCraftId,
    bool? requiresFlightAssignment,
    String? rideCode,
    int? simulationRiderCount,
    CraftIconStyle? craftStyle,
    RideCoordinationMode? coordinationMode,
    String? crewRoomId,
    int? authorizationVersion,
    String? authorityRootPublicKey,
    String? localDevicePublicKey,
  }) => RideSession(
    rideId: rideId,
    rideCode: rideCode ?? this.rideCode,
    inviteSecret: inviteSecret,
    joinToken: joinToken,
    authorizationVersion: authorizationVersion ?? this.authorizationVersion,
    authorityRootPublicKey:
        authorityRootPublicKey ?? this.authorityRootPublicKey,
    localDevicePublicKey: localDevicePublicKey ?? this.localDevicePublicKey,
    localRiderId: localRiderId,
    displayName: displayName,
    role: role ?? this.role,
    flightRole: flightRole ?? this.flightRole,
    localCraftId: localCraftId ?? this.localCraftId,
    requiresFlightAssignment:
        requiresFlightAssignment ?? this.requiresFlightAssignment,
    joinedAt: joinedAt,
    isSimulation: isSimulation,
    simulationRiderCount: simulationRiderCount ?? this.simulationRiderCount,
    craftStyle: craftStyle ?? this.craftStyle,
    riderSymbol: riderSymbol,
    riderColor: riderColor,
    coordinationMode: coordinationMode ?? this.coordinationMode,
    rideName: rideName,
    crewRoomId: crewRoomId ?? this.crewRoomId,
  );

  Map<String, Object?> toJson() => {
    'rideId': rideId,
    'rideCode': rideCode,
    'inviteSecret': inviteSecret,
    'joinToken': joinToken,
    if (authorizationVersion >= 2) 'authorizationVersion': authorizationVersion,
    if (authorityRootPublicKey != null)
      'authorityRootPublicKey': authorityRootPublicKey,
    if (localDevicePublicKey != null)
      'localDevicePublicKey': localDevicePublicKey,
    'localRiderId': localRiderId,
    'displayName': displayName,
    'role': role.name,
    'flightRole': flightRole.name,
    if (localCraftId != null) 'localCraftId': localCraftId,
    if (requiresFlightAssignment) 'requiresFlightAssignment': true,
    'joinedAt': joinedAt.toUtc().toIso8601String(),
    if (isSimulation) 'isSimulation': true,
    if (isSimulation) 'simulationRiderCount': simulationRiderCount,
    craftStyleWireKey: craftStyle.name,
    legacyCraftStyleWireKey: craftStyle.name,
    'riderSymbol': riderSymbol.storageValue,
    'riderColor': riderColor.name,
    'coordinationMode': coordinationMode.name,
    if (rideName != null) 'rideName': rideName,
    if (crewRoomId != null) 'crewRoomId': crewRoomId,
  };

  factory RideSession.fromJson(Map<String, Object?> json) {
    final storedFlightRole = json['flightRole'];
    final hasFlightRole =
        storedFlightRole is String &&
        FlightRole.values.any((role) => role.name == storedFlightRole);
    return RideSession(
      rideId: json['rideId']! as String,
      rideCode: json['rideCode']! as String,
      inviteSecret: json['inviteSecret']! as String,
      joinToken: _joinTokenOrFallback(json['joinToken']),
      authorizationVersion: json['authorizationVersion'] as int? ?? 1,
      authorityRootPublicKey: json['authorityRootPublicKey'] as String?,
      localDevicePublicKey: json['localDevicePublicKey'] as String?,
      localRiderId: json['localRiderId']! as String,
      displayName: json['displayName']! as String,
      role: rideRoleFromName(json['role']),
      flightRole: hasFlightRole
          ? flightRoleFromName(storedFlightRole)
          : FlightRole.observer,
      localCraftId: json['localCraftId'] as String?,
      requiresFlightAssignment:
          json['requiresFlightAssignment'] as bool? ?? !hasFlightRole,
      joinedAt: DateTime.parse(json['joinedAt']! as String).toLocal(),
      isSimulation: json['isSimulation'] as bool? ?? false,
      simulationRiderCount: _simulationRiderCount(json['simulationRiderCount']),
      craftStyle: craftIconStyleFromName(craftStyleNameFromPayload(json)),
      riderSymbol: RiderSymbol.fromStorageValue(json['riderSymbol'] as String?),
      riderColor: riderColorFromName(json['riderColor'] as String?),
      coordinationMode: RideCoordinationMode.fromName(
        json['coordinationMode'] as String?,
      ),
      rideName: json['rideName'] as String?,
      crewRoomId: json['crewRoomId'] as String?,
    );
  }

  static int _simulationRiderCount(Object? value) {
    if (value is! int) return defaultSimulationRiderCount;
    return value
        .clamp(minimumSimulationRiderCount, maximumSimulationRiderCount)
        .toInt();
  }

  /// A ride session persisted before the join token existed has none stored.
  /// Generating a fresh one keeps old local sessions loadable; a lead in
  /// that state simply re-publishes its ride code with the new token.
  static String _joinTokenOrFallback(Object? value) {
    if (value is String && value.length >= 16) return value;
    return base64Url
        .encode(List<int>.generate(20, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
  }
}
