import 'geo_point.dart';

enum HazardType {
  pothole,
  looseSurface,
  debris,
  roadworks,
  collision,
  stoppedVehicle,
  flooding,
  animals,
  other,
}

extension HazardTypeLabel on HazardType {
  String get label => switch (this) {
    HazardType.pothole => 'Pothole',
    HazardType.looseSurface => 'Loose surface',
    HazardType.debris => 'Debris',
    HazardType.roadworks => 'Roadworks',
    HazardType.collision => 'Collision',
    HazardType.stoppedVehicle => 'Stopped vehicle',
    HazardType.flooding => 'Flooding',
    HazardType.animals => 'Animals',
    HazardType.other => 'Other hazard',
  };
}

/// Road conditions that an operational crew member can raise from the app.
const riderReportableHazardTypes = <HazardType>[
  HazardType.pothole,
  HazardType.looseSurface,
  HazardType.debris,
  HazardType.roadworks,
  HazardType.collision,
  HazardType.stoppedVehicle,
  HazardType.flooding,
  HazardType.animals,
  HazardType.other,
];

extension HazardTypePolicy on HazardType {
  bool get isRiderReportable => riderReportableHazardTypes.contains(this);
}

enum HazardSeverity { advisory, caution, serious, critical }

extension HazardSeverityLabel on HazardSeverity {
  String get label => switch (this) {
    HazardSeverity.advisory => 'Advisory',
    HazardSeverity.caution => 'Caution',
    HazardSeverity.serious => 'Serious',
    HazardSeverity.critical => 'Critical',
  };
}

enum HazardSource { rider, externalProvider }

class HazardReport {
  const HazardReport({
    required this.id,
    required this.rideId,
    required this.type,
    required this.severity,
    required this.position,
    required this.reportedAt,
    required this.updatedAt,
    required this.expiresAt,
    required this.reporterId,
    required this.source,
    this.reporterName,
    this.providerId,
    this.details,
    this.confirmations = 1,
  }) : assert(confirmations >= 1),
       assert(source == HazardSource.rider || providerId != null);

  final String id;
  final String rideId;
  final HazardType type;
  final HazardSeverity severity;
  final GeoPoint position;
  final DateTime reportedAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final String reporterId;
  final String? reporterName;
  final HazardSource source;
  final String? providerId;
  final String? details;
  final int confirmations;

  bool isActiveAt(DateTime now) => expiresAt.isAfter(now);

  HazardReport copyWith({
    HazardSeverity? severity,
    DateTime? updatedAt,
    DateTime? expiresAt,
    String? details,
    int? confirmations,
  }) => HazardReport(
    id: id,
    rideId: rideId,
    type: type,
    severity: severity ?? this.severity,
    position: position,
    reportedAt: reportedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    reporterId: reporterId,
    reporterName: reporterName,
    source: source,
    providerId: providerId,
    details: details ?? this.details,
    confirmations: confirmations ?? this.confirmations,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'rideId': rideId,
    'type': type.name,
    'severity': severity.name,
    'position': position.toJson(),
    'reportedAt': reportedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'reporterId': reporterId,
    'reporterName': reporterName,
    'source': source.name,
    'providerId': providerId,
    'details': details,
    'confirmations': confirmations,
  };

  factory HazardReport.fromJson(Map<String, Object?> json) => HazardReport(
    id: json['id']! as String,
    rideId: json['rideId']! as String,
    // Builds predating baseline isolation may have persisted the inherited
    // `speedCamera` or `policeActivity` values. They reopen as an ordinary
    // short-lived road note rather than restoring enforcement behaviour.
    type: _hazardTypeFromJson(json['type']),
    severity: HazardSeverity.values.byName(json['severity']! as String),
    position: GeoPoint.fromJson(
      Map<String, Object?>.from(json['position']! as Map),
    ),
    reportedAt: DateTime.parse(json['reportedAt']! as String).toLocal(),
    updatedAt: DateTime.parse(json['updatedAt']! as String).toLocal(),
    expiresAt: DateTime.parse(json['expiresAt']! as String).toLocal(),
    reporterId: json['reporterId']! as String,
    reporterName: json['reporterName'] as String?,
    source: HazardSource.values.byName(json['source']! as String),
    providerId: json['providerId'] as String?,
    details: json['details'] as String?,
    confirmations: (json['confirmations'] as num?)?.toInt() ?? 1,
  );
}

class HazardExpiryPolicy {
  const HazardExpiryPolicy();

  Duration durationFor(HazardType type, HazardSeverity severity) {
    if (severity == HazardSeverity.critical) {
      return const Duration(hours: 4);
    }
    return switch (type) {
      HazardType.pothole ||
      HazardType.roadworks ||
      HazardType.flooding => const Duration(hours: 12),
      HazardType.collision ||
      HazardType.stoppedVehicle => const Duration(hours: 2),
      HazardType.looseSurface ||
      HazardType.debris ||
      HazardType.animals ||
      HazardType.other => const Duration(hours: 6),
    };
  }
}

HazardType _hazardTypeFromJson(Object? value) {
  if (value == 'speedCamera' || value == 'policeActivity') {
    return HazardType.other;
  }
  if (value is String) {
    for (final type in HazardType.values) {
      if (type.name == value) return type;
    }
  }
  return HazardType.other;
}
