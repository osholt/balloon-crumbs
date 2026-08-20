/// Where an altitude reading came from.
///
/// Recorded rather than inferred because the two sources fail differently: a
/// GNSS altitude is noisy but absolute, a barometric one is smooth but drifts
/// with the weather and needs a reference setting. A balloon crew judging a
/// climb rate needs to know which they are looking at.
enum AltitudeSource {
  /// Height from the positioning fix itself.
  gnss,

  /// Height from a pressure sensor.
  barometric,

  /// An altitude arrived with no statement of where it came from — typically an
  /// imported file. Never used to mean "no altitude": that is a null reading.
  unknown,
}

/// The vertical reference used by an altitude reading.
///
/// This cannot be inferred from [AltitudeSource]. Core Location reports height
/// above mean sea level, while Android's ordinary `Location.altitude` reports
/// height above the WGS84 ellipsoid. The difference is tens of metres in parts
/// of the UK, so losing this field can make a technically precise reading
/// materially misleading.
enum AltitudeDatum {
  /// Orthometric height above the WGS84-associated mean-sea-level geoid.
  wgs84Geoid,

  /// Geometric height above the WGS84 reference ellipsoid.
  wgs84Ellipsoid,

  /// Height relative to the launch field, used by simulations and pilot-facing
  /// relative-height data. It is not an absolute elevation.
  relativeToLaunch,

  /// An altitude arrived without a datum statement, typically from GPX.
  unknown,
}
