import 'dart:ui';

import '../../domain/imported_route.dart';
import '../../domain/altitude_unit.dart';

/// One colour band in the balloon ground-track legend.
class BalloonAltitudeBand {
  const BalloonAltitudeBand({
    required this.minimumMeters,
    required this.label,
    required this.color,
  });

  final double minimumMeters;
  final String label;
  final Color color;
}

/// One drawable ground-track leg.
///
/// A leg only receives an altitude colour when both of its fixes carry a valid
/// altitude. A neutral line is used across missing data rather than inventing a
/// height between one known endpoint and one unknown endpoint.
class BalloonAltitudeSegment {
  const BalloonAltitudeSegment({
    required this.points,
    required this.color,
    required this.altitudeMeters,
    required this.widthFactor,
  });

  final List<GeoPoint> points;
  final Color color;
  final double? altitudeMeters;

  /// A non-colour cue shared by every renderer: higher bands are progressively
  /// thicker, while an unknown-altitude leg is the thinnest.
  final double widthFactor;

  bool get hasAltitude => altitudeMeters != null;
}

/// Metric altitude palette shared by both map renderers and the legend.
class BalloonAltitudeStyle {
  const BalloonAltitudeStyle._();

  static const unknownColor = Color(0xFFB7C4D1);
  static const unknownWidthFactor = 0.65;
  static const bandWidthFactors = <double>[0.8, 0.95, 1.1, 1.25, 1.4];

  static const bands = <BalloonAltitudeBand>[
    BalloonAltitudeBand(
      minimumMeters: double.negativeInfinity,
      label: '<150 m',
      color: Color(0xFF00E5FF),
    ),
    BalloonAltitudeBand(
      minimumMeters: 150,
      label: '150–299 m',
      color: Color(0xFF55E05B),
    ),
    BalloonAltitudeBand(
      minimumMeters: 300,
      label: '300–599 m',
      color: Color(0xFFFFE45E),
    ),
    BalloonAltitudeBand(
      minimumMeters: 600,
      label: '600–899 m',
      color: Color(0xFFFF9F43),
    ),
    BalloonAltitudeBand(
      minimumMeters: 900,
      label: '900+ m',
      color: Color(0xFFFF4FA3),
    ),
  ];

  static Color colorForMeters(double meters) {
    var selected = bands.first.color;
    for (final band in bands) {
      if (meters < band.minimumMeters) break;
      selected = band.color;
    }
    return selected;
  }

  static List<String> labels(AltitudeUnit unit) => [
    for (var index = 0; index < bands.length; index += 1)
      _labelForBand(index, unit),
  ];

  static String _labelForBand(int index, AltitudeUnit unit) {
    final lower = bands[index].minimumMeters;
    final upper = index + 1 < bands.length
        ? bands[index + 1].minimumMeters
        : null;
    String value(double metres) => unit.fromMetres(metres).round().toString();
    if (!lower.isFinite && upper != null) {
      return '<${value(upper)} ${unit.symbol}';
    }
    if (upper == null) return '${value(lower)}+ ${unit.symbol}';
    return '${value(lower)}–${value(upper)} ${unit.symbol}';
  }

  static List<BalloonAltitudeSegment> segments(List<GeoPoint> points) => [
    for (var index = 1; index < points.length; index += 1)
      _segment(points[index - 1], points[index]),
  ];

  static BalloonAltitudeSegment _segment(GeoPoint start, GeoPoint end) {
    final startAltitude = start.elevationMeters;
    final endAltitude = end.elevationMeters;
    final altitude =
        startAltitude != null &&
            startAltitude.isFinite &&
            endAltitude != null &&
            endAltitude.isFinite
        ? (startAltitude + endAltitude) / 2
        : null;
    return BalloonAltitudeSegment(
      points: [start, end],
      color: altitude == null ? unknownColor : colorForMeters(altitude),
      altitudeMeters: altitude,
      widthFactor: altitude == null
          ? unknownWidthFactor
          : _widthFactorForMeters(altitude),
    );
  }

  static double _widthFactorForMeters(double meters) {
    var selected = bandWidthFactors.first;
    for (var index = 0; index < bands.length; index += 1) {
      if (meters < bands[index].minimumMeters) break;
      selected = bandWidthFactors[index];
    }
    return selected;
  }
}
