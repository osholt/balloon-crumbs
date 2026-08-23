import 'geo_point.dart';

enum LandAccessGeometryKind { point, polygon }

enum LandAccessOutcome {
  unknown,
  askFirst,
  permissionConfirmed,
  accessDeclined,
}

enum LandAccessProvenance { crewObservation, landContact, publicReference }

enum LandAccessConsentStatus {
  notRecorded,
  verbal,
  written,
  contactRequestedRemoval,
}

class LandAccessGeometry {
  LandAccessGeometry({required this.kind, required List<GeoPoint> points})
    : points = List.unmodifiable(points) {
    if (kind == LandAccessGeometryKind.point && points.length != 1) {
      throw const FormatException('A point geometry needs exactly one point.');
    }
    if (kind == LandAccessGeometryKind.polygon && points.length < 3) {
      throw const FormatException(
        'A polygon geometry needs at least three points.',
      );
    }
    if (points.length > 200) {
      throw const FormatException('A land access geometry is too detailed.');
    }
  }

  final LandAccessGeometryKind kind;
  final List<GeoPoint> points;

  GeoPoint get anchor => points.first;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'points': points.map((point) => point.toJson()).toList(growable: false),
  };

  factory LandAccessGeometry.fromJson(Map<String, Object?> json) {
    final kind = LandAccessGeometryKind.values.byName(json['kind']! as String);
    final rawPoints = json['points'];
    if (rawPoints is! List) {
      throw const FormatException('Land access geometry points are missing.');
    }
    return LandAccessGeometry(
      kind: kind,
      points: rawPoints
          .map(
            (item) => GeoPoint.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(growable: false),
    );
  }
}

class LandAccessNote {
  LandAccessNote({
    required this.id,
    required this.geometry,
    required this.outcome,
    required this.confirmedAt,
    required this.recordedBy,
    required this.provenance,
    required this.consentStatus,
    required this.reviewAfter,
    required this.createdAt,
    required this.updatedAt,
    this.firstName,
    this.contactRole,
    this.phoneNumber,
    this.gateNotes = '',
  }) {
    if (id.trim().isEmpty || id.length > 80) {
      throw const FormatException('Land access note id is invalid.');
    }
    if (reviewAfter.isBefore(confirmedAt)) {
      throw const FormatException('Review date cannot predate confirmation.');
    }
    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException('Updated time cannot predate creation.');
    }
    _checkLength(firstName, 80, 'First name');
    _checkLength(contactRole, 80, 'Contact role');
    _checkLength(phoneNumber, 40, 'Phone number');
    _checkLength(recordedBy, 80, 'Recorder');
    _checkLength(gateNotes, 1000, 'Gate notes');
  }

  final String id;
  final LandAccessGeometry geometry;
  final LandAccessOutcome outcome;
  final String? firstName;
  final String? contactRole;
  final String? phoneNumber;
  final String gateNotes;
  final DateTime confirmedAt;
  final String recordedBy;
  final LandAccessProvenance provenance;
  final LandAccessConsentStatus consentStatus;
  final DateTime reviewAfter;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasPersonalContact =>
      (firstName?.trim().isNotEmpty ?? false) ||
      (contactRole?.trim().isNotEmpty ?? false) ||
      (phoneNumber?.trim().isNotEmpty ?? false);

  bool isExpiredAt(DateTime now) => !reviewAfter.isAfter(now.toUtc());

  LandAccessNote copyWith({
    LandAccessGeometry? geometry,
    LandAccessOutcome? outcome,
    String? firstName,
    String? contactRole,
    String? phoneNumber,
    String? gateNotes,
    DateTime? confirmedAt,
    String? recordedBy,
    LandAccessProvenance? provenance,
    LandAccessConsentStatus? consentStatus,
    DateTime? reviewAfter,
    DateTime? updatedAt,
  }) => LandAccessNote(
    id: id,
    geometry: geometry ?? this.geometry,
    outcome: outcome ?? this.outcome,
    firstName: firstName ?? this.firstName,
    contactRole: contactRole ?? this.contactRole,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    gateNotes: gateNotes ?? this.gateNotes,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    recordedBy: recordedBy ?? this.recordedBy,
    provenance: provenance ?? this.provenance,
    consentStatus: consentStatus ?? this.consentStatus,
    reviewAfter: reviewAfter ?? this.reviewAfter,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'geometry': geometry.toJson(),
    'outcome': outcome.name,
    'firstName': ?firstName,
    'contactRole': ?contactRole,
    'phoneNumber': ?phoneNumber,
    'gateNotes': gateNotes,
    'confirmedAt': confirmedAt.toUtc().toIso8601String(),
    'recordedBy': recordedBy,
    'provenance': provenance.name,
    'consentStatus': consentStatus.name,
    'reviewAfter': reviewAfter.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LandAccessNote.fromJson(Map<String, Object?> json) => LandAccessNote(
    id: json['id']! as String,
    geometry: LandAccessGeometry.fromJson(
      Map<String, Object?>.from(json['geometry']! as Map),
    ),
    outcome: LandAccessOutcome.values.byName(json['outcome']! as String),
    firstName: json['firstName'] as String?,
    contactRole: json['contactRole'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    gateNotes: json['gateNotes'] as String? ?? '',
    confirmedAt: DateTime.parse(json['confirmedAt']! as String).toUtc(),
    recordedBy: json['recordedBy']! as String,
    provenance: LandAccessProvenance.values.byName(
      json['provenance']! as String,
    ),
    consentStatus: LandAccessConsentStatus.values.byName(
      json['consentStatus']! as String,
    ),
    reviewAfter: DateTime.parse(json['reviewAfter']! as String).toUtc(),
    createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt']! as String).toUtc(),
  );

  static void _checkLength(String? value, int maximum, String label) {
    if ((value?.length ?? 0) > maximum) {
      throw FormatException('$label is too long.');
    }
  }
}

class LandAccessExportMetadata {
  LandAccessExportMetadata({
    required this.exportId,
    required List<String> noteIds,
    required this.createdAt,
  }) : noteIds = List.unmodifiable(noteIds) {
    if (exportId.trim().isEmpty || noteIds.isEmpty) {
      throw const FormatException('Land access export metadata is invalid.');
    }
  }

  final String exportId;
  final List<String> noteIds;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'exportId': exportId,
    'noteIds': noteIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory LandAccessExportMetadata.fromJson(Map<String, Object?> json) =>
      LandAccessExportMetadata(
        exportId: json['exportId']! as String,
        noteIds: (json['noteIds']! as List).cast<String>(),
        createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
      );
}
