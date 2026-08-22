import 'imported_route.dart';
import 'flight_replay.dart';
import 'ride_role.dart';

/// A secret-free, immutable local record derived from a completed ride.
///
/// Invitation credentials, rider identifiers, event payloads and other
/// riders' location trails are deliberately excluded.
class CompletedRide {
  const CompletedRide({
    required this.rideId,
    required this.rideCode,
    required this.rideName,
    required this.localDisplayName,
    required this.localRole,
    required this.startedAt,
    required this.endedAt,
    required this.archivedAt,
    required this.riderCount,
    required this.eventCount,
    required this.totalDistanceMeters,
    required this.plannedRoute,
    required this.traveledRoute,
    this.replay,
  });

  static const schemaVersion = 2;

  final String rideId;
  final String rideCode;
  final String? rideName;
  final String localDisplayName;
  final RideRole localRole;
  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime archivedAt;
  final int riderCount;
  final int eventCount;
  final double totalDistanceMeters;
  final ImportedRoute? plannedRoute;
  final ImportedRoute? traveledRoute;
  final FlightReplay? replay;

  String get title => rideName?.trim().isNotEmpty == true
      ? rideName!.trim()
      : 'Flight $rideCode';

  Duration get duration => endedAt.difference(startedAt).abs();

  /// More than one recorded track means the location stream stopped long
  /// enough that joining the fixes would invent a straight line (#205).
  bool get hasRecordingGaps =>
      (traveledRoute?.paths
              .where((path) => path.kind == RoutePathKind.track)
              .length ??
          0) >
      1;

  Iterable<GeoPoint> get mapPoints sync* {
    if (plannedRoute case final route?) yield* route.allPoints;
    if (traveledRoute case final route?) yield* route.allPoints;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'rideId': rideId,
    'rideCode': rideCode,
    if (rideName != null) 'rideName': rideName,
    'localDisplayName': localDisplayName,
    'localRole': localRole.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'archivedAt': archivedAt.toUtc().toIso8601String(),
    'riderCount': riderCount,
    'eventCount': eventCount,
    'totalDistanceMeters': totalDistanceMeters,
    if (plannedRoute != null) 'plannedRoute': plannedRoute!.toJson(),
    if (traveledRoute != null) 'traveledRoute': traveledRoute!.toJson(),
    if (replay != null) 'replay': replay!.toJson(),
  };

  factory CompletedRide.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != 1 && version != schemaVersion) {
      throw FormatException(
        'Unsupported completed ride schema: ${json['schemaVersion']}',
      );
    }
    return CompletedRide(
      rideId: json['rideId']! as String,
      rideCode: json['rideCode']! as String,
      rideName: json['rideName'] as String?,
      localDisplayName: json['localDisplayName']! as String,
      localRole: rideRoleFromName(json['localRole']),
      startedAt: DateTime.parse(json['startedAt']! as String).toUtc(),
      endedAt: DateTime.parse(json['endedAt']! as String).toUtc(),
      archivedAt: DateTime.parse(json['archivedAt']! as String).toUtc(),
      riderCount: (json['riderCount'] as num?)?.toInt() ?? 1,
      eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
      totalDistanceMeters:
          (json['totalDistanceMeters'] as num?)?.toDouble() ?? 0,
      plannedRoute: _optionalRoute(json['plannedRoute']),
      traveledRoute: _optionalRoute(json['traveledRoute']),
      replay: version == 1 ? null : _optionalReplay(json['replay']),
    );
  }

  static ImportedRoute? _optionalRoute(Object? value) {
    if (value is! Map) return null;
    try {
      return ImportedRoute.fromJson(Map<String, Object?>.from(value));
    } on FormatException {
      // Preserve useful summary metadata when optional geometry is damaged.
      return null;
    }
  }

  static FlightReplay? _optionalReplay(Object? value) {
    if (value is! Map) return null;
    try {
      return FlightReplay.fromJson(Map<String, Object?>.from(value));
    } on Object {
      // A damaged optional replay must not hide the flight summary or GPX.
      return null;
    }
  }
}
