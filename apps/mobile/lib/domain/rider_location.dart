import '../features/map/craft_icon.dart';
import 'altitude.dart';
import 'geo_point.dart';
import 'ride_role.dart';
import 'rider_color.dart';

export 'altitude.dart';

class LocationSample {
  const LocationSample({
    required this.position,
    required this.recordedAt,
    required this.accuracyMeters,
    this.speedMetersPerSecond,
    this.headingDegrees,
    this.altitudeMeters,
    this.altitudeSource = AltitudeSource.unknown,
    this.altitudeDatum = AltitudeDatum.unknown,
    this.altitudeAccuracyMeters,
    this.verticalSpeedMetersPerSecond,
  }) : assert(accuracyMeters >= 0),
       assert(speedMetersPerSecond == null || speedMetersPerSecond >= 0),
       assert(
         headingDegrees == null ||
             (headingDegrees >= 0 && headingDegrees < 360),
       ),
       assert(altitudeAccuracyMeters == null || altitudeAccuracyMeters >= 0),
       // An accuracy or a source without a reading describes nothing, and a
       // reading is what every altitude surface branches on.
       assert(altitudeMeters != null || altitudeAccuracyMeters == null),
       assert(
         altitudeMeters != null || altitudeSource == AltitudeSource.unknown,
       ),
       assert(altitudeMeters != null || altitudeDatum == AltitudeDatum.unknown);

  final GeoPoint position;
  final DateTime recordedAt;
  final double accuracyMeters;
  final double? speedMetersPerSecond;
  final double? headingDegrees;

  /// Metres relative to [altitudeDatum], or null when this fix carried no usable
  /// altitude.
  ///
  /// Null and zero are different answers. A balloon on the ground reports zero;
  /// a device that cannot measure height reports null. Platform location APIs
  /// return 0.0 for both, which is why capture gates on the accuracy figure
  /// rather than the reading — see `DeviceLocationSource`.
  final double? altitudeMeters;

  /// Where [altitudeMeters] came from. [AltitudeSource.unknown] whenever there
  /// is no reading.
  final AltitudeSource altitudeSource;

  /// The vertical reference for [altitudeMeters].
  ///
  /// [AltitudeDatum.unknown] is an honest value for an imported or legacy
  /// reading. It must never be silently upgraded to geoid or ellipsoid.
  final AltitudeDatum altitudeDatum;

  /// Reported vertical accuracy in metres, when the platform supplies one.
  final double? altitudeAccuracyMeters;

  /// Climb (positive) or descent (negative) in metres per second.
  ///
  /// Only ever a measured or platform-supplied figure. Nothing derives it from
  /// two altitudes here: that belongs to a read model that can see the fix ages
  /// and decide whether the pair is worth differencing.
  final double? verticalSpeedMetersPerSecond;

  /// Whether this fix can answer "how high is the balloon".
  bool get hasAltitude => altitudeMeters != null;

  Duration ageAt(DateTime now) {
    final age = now.difference(recordedAt);
    return age.isNegative ? Duration.zero : age;
  }

  bool isStaleAt(DateTime now, Duration threshold) => ageAt(now) > threshold;

  Map<String, Object?> toJson() => {
    'position': position.toJson(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'accuracyMeters': accuracyMeters,
    'speedMetersPerSecond': speedMetersPerSecond,
    'headingDegrees': headingDegrees,
    // Additive and optional: a peer on an older build ignores what it does not
    // know, and this build reads their payload as a fix without altitude.
    // Written only when there is a reading, so the absence stays an absence
    // rather than becoming an explicit null that later looks like a measurement.
    if (altitudeMeters case final altitude?) ...{
      'altitudeMeters': altitude,
      'altitudeSource': altitudeSource.name,
      'altitudeDatum': altitudeDatum.name,
      'altitudeAccuracyMeters': ?altitudeAccuracyMeters,
    },
    'verticalSpeedMetersPerSecond': ?verticalSpeedMetersPerSecond,
  };

  factory LocationSample.fromJson(Map<String, Object?> json) {
    final altitude = (json['altitudeMeters'] as num?)?.toDouble();
    return LocationSample(
      position: GeoPoint.fromJson(
        Map<String, Object?>.from(json['position']! as Map),
      ),
      recordedAt: DateTime.parse(json['recordedAt']! as String).toLocal(),
      accuracyMeters: (json['accuracyMeters']! as num).toDouble(),
      speedMetersPerSecond: (json['speedMetersPerSecond'] as num?)?.toDouble(),
      headingDegrees: (json['headingDegrees'] as num?)?.toDouble(),
      altitudeMeters: altitude,
      // A source or an accuracy without a reading is dropped rather than kept:
      // the constructor forbids the pairing, and a peer that sends one is
      // describing nothing this build can render.
      altitudeSource: altitude == null
          ? AltitudeSource.unknown
          : _altitudeSourceFromName(json['altitudeSource']),
      altitudeDatum: altitude == null
          ? AltitudeDatum.unknown
          : _altitudeDatumFromName(json['altitudeDatum']),
      altitudeAccuracyMeters: altitude == null
          ? null
          : (json['altitudeAccuracyMeters'] as num?)?.toDouble(),
      verticalSpeedMetersPerSecond:
          (json['verticalSpeedMetersPerSecond'] as num?)?.toDouble(),
    );
  }

  /// Reads an altitude source that another build may have written.
  ///
  /// An unrecognised name degrades to [AltitudeSource.unknown] rather than
  /// throwing, for the same reason [rideRoleFromName] exists: a peer is allowed
  /// to know a source this build does not.
  static AltitudeSource _altitudeSourceFromName(Object? value) {
    if (value is! String) return AltitudeSource.unknown;
    for (final source in AltitudeSource.values) {
      if (source.name == value) return source;
    }
    return AltitudeSource.unknown;
  }

  /// Reads a datum written by another build without making a future value fatal.
  static AltitudeDatum _altitudeDatumFromName(Object? value) {
    if (value is! String) return AltitudeDatum.unknown;
    for (final datum in AltitudeDatum.values) {
      if (datum.name == value) return datum;
    }
    return AltitudeDatum.unknown;
  }
}

class RiderLocation {
  const RiderLocation({
    required this.riderId,
    required this.displayName,
    required this.role,
    required this.sample,
    required this.receivedAt,
    this.motorcycleStyle = craftIconStyleDefault,
    this.riderSymbol = riderSymbolDefault,
    this.riderColor = riderColorDefault,
  });

  final String riderId;
  final String displayName;
  final RideRole role;
  final LocationSample sample;
  final DateTime receivedAt;
  final CraftIconStyle motorcycleStyle;
  final RiderSymbol riderSymbol;
  final RiderColor riderColor;

  Map<String, Object?> toJson() => {
    'riderId': riderId,
    'displayName': displayName,
    'role': role.name,
    'sample': sample.toJson(),
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'motorcycleStyle': riderSymbol.wireValue(motorcycleStyle),
    'riderColor': riderColor.name,
  };

  factory RiderLocation.fromJson(Map<String, Object?> json) => RiderLocation(
    riderId: json['riderId']! as String,
    displayName: json['displayName']! as String,
    role: rideRoleFromName(json['role']),
    sample: LocationSample.fromJson(
      Map<String, Object?>.from(json['sample']! as Map),
    ),
    receivedAt: DateTime.parse(json['receivedAt']! as String).toLocal(),
    motorcycleStyle: craftIconStyleFromName(json['motorcycleStyle'] as String?),
    riderSymbol: RiderSymbol.fromWireValue(json['motorcycleStyle'] as String?),
    riderColor: riderColorFromName(json['riderColor'] as String?),
  );
}

class RiderLocationEvidence {
  const RiderLocationEvidence({
    required this.location,
    required this.eventId,
    required this.eventCreatedAt,
    required this.authenticated,
  });

  final RiderLocation location;
  final String eventId;
  final DateTime eventCreatedAt;
  final bool authenticated;
}
