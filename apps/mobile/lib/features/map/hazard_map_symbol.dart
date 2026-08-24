import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/hazard.dart';
import 'route_trail_style.dart';

enum HazardMapBadgeShape { circle }

/// The symbol drawn inside the badge, which says which kind of report it is.
///
/// Vector paths rather than Material glyphs, for two reasons. The MapLibre
/// renderer and the flutter_map fallback have to draw the same artwork or the
/// device and the tests disagree about what shipped (#141), and one painter
/// rasterised for one and called directly by the other is the only way to
/// guarantee that. And `flutter test` ships no fonts, so a glyph-based symbol
/// renders as a filled box in exactly the harness that exists to look at it.
///
enum HazardMapGlyph { roadDefect }

/// How much of a report's trusted life has run.
///
/// Reports become less prominent as their declared lifetime runs out.
enum HazardMapFreshness { fresh, ageing, fading }

extension HazardMapFreshnessLabel on HazardMapFreshness {
  String get label => switch (this) {
    HazardMapFreshness.fresh => 'Fresh',
    HazardMapFreshness.ageing => 'Ageing',
    HazardMapFreshness.fading => 'About to expire',
  };
}

/// Every measurement and colour needed to draw one hazard report, decided once
/// and read by both renderers.
///
/// Nothing here is a renderer's own choice. The MapLibre symbol layer draws a
/// raster of [HazardMapSymbolPainter] and the flutter_map fallback draws the same
/// painter directly, so a change to any of these numbers moves both.
@immutable
class HazardMapSymbol {
  const HazardMapSymbol({
    required this.glyph,
    required this.shape,
    required this.fill,
    required this.freshness,
    required this.diameterPixels,
    required this.ringWidthPixels,
    this.ringDashPixels,
  });

  final HazardMapGlyph glyph;
  final HazardMapBadgeShape shape;

  /// Opaque badge fill. Opaque because contrast against the basemap is only
  /// measurable for an opaque colour, and #133 measures every ink on this map:
  /// the ageing steps are pre-blended toward slate rather than made translucent
  /// so they stay in the same table as everything else.
  final Color fill;

  final HazardMapFreshness freshness;

  /// On-screen badge size in logical pixels, at ride zoom.
  final double diameterPixels;

  final double ringWidthPixels;

  /// On/off run lengths for the badge outline, or null for a solid ring.
  ///
  /// The second freshness cue, and the one that survives a greyscale render.
  /// [RouteTrailStyle] settled the same argument for route lines: five bright
  /// colours cannot all be separated by luminance, so each also gets a pattern.
  final List<double>? ringDashPixels;

  /// A stable name for the MapLibre image registered from this symbol.
  String get imageName =>
      'hazard-symbol-${glyph.name}-${_fillKey(fill)}-${freshness.name}';

  @override
  bool operator ==(Object other) =>
      other is HazardMapSymbol &&
      glyph == other.glyph &&
      shape == other.shape &&
      fill == other.fill &&
      freshness == other.freshness &&
      diameterPixels == other.diameterPixels &&
      ringWidthPixels == other.ringWidthPixels;

  @override
  int get hashCode => Object.hash(
    glyph,
    shape,
    fill,
    freshness,
    diameterPixels,
    ringWidthPixels,
  );
}

String _fillKey(Color color) =>
    color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);

/// The badge palette and the rules that map a report onto it.
abstract final class HazardMapSymbols {
  /// The layout box every badge is drawn into, in logical pixels.
  ///
  /// One box for every symbol so the MapLibre layer can use a single constant
  /// `icon-size` and the difference in badge size between a fresh report and a
  /// fading one comes from the artwork, identically in both renderers.
  static const extentPixels = 44.0;

  /// What an ageing badge blends toward.
  ///
  /// A stale rider marker demotes toward `#6B7684`, and matching it would have
  /// been the tidier answer, but it is dark enough to push the critical-severity
  /// fill to 4.14:1 against its own ring - under the 4.5:1 floor #133 set for
  /// every badge on this map. This grey is two steps lighter, which keeps the
  /// worst faded fill at 6.16:1 while still washing the colour out of it.
  static const stalenessBlend = Color(0xFF9AA7B4);

  static const _fadeFractions = <HazardMapFreshness, double>{
    HazardMapFreshness.fresh: 0,
    HazardMapFreshness.ageing: 0.45,
    HazardMapFreshness.fading: 0.8,
  };

  /// Fill for a road-defect badge, unchanged from what the map drew before this
  /// symbol language existed so a fresh defect looks exactly as it did.
  static Color severityFill(HazardSeverity severity) => switch (severity) {
    HazardSeverity.advisory => const Color(0xFF8EA7C4),
    HazardSeverity.caution => const Color(0xFFFFC857),
    HazardSeverity.serious => const Color(0xFFFF8A4C),
    HazardSeverity.critical => const Color(0xFFFF5D73),
  };

  /// [base] aged. Opaque at every step: see [HazardMapSymbol.fill].
  static Color fadedFill(Color base, HazardMapFreshness freshness) =>
      Color.lerp(base, stalenessBlend, _fadeFractions[freshness]!) ?? base;

  static HazardMapGlyph glyphFor(HazardType type) => HazardMapGlyph.roadDefect;

  /// How far through its trusted life [report] is, from 0 to 1.
  ///
  /// Measured from [HazardReport.updatedAt] rather than [HazardReport.reportedAt]
  /// so a re-confirmed sighting reads as fresh again - which it is: somebody has
  /// just seen it. The denominator is the window the report itself declares, so a
  /// each report is judged against its own expiry rather than a number restated
  /// here.
  static double lifeFraction(HazardReport report, DateTime now) {
    final window = report.expiresAt.difference(report.updatedAt);
    if (window.inMilliseconds <= 0) return 1;
    final elapsed = now.difference(report.updatedAt);
    return (elapsed.inMilliseconds / window.inMilliseconds).clamp(0.0, 1.0);
  }

  static HazardMapFreshness freshnessFor(HazardReport report, DateTime now) {
    final fraction = lifeFraction(report, now);
    if (fraction < 0.5) return HazardMapFreshness.fresh;
    if (fraction < 0.8) return HazardMapFreshness.ageing;
    return HazardMapFreshness.fading;
  }

  /// The symbol for [report] as it stands at [now].
  static HazardMapSymbol forReport(
    HazardReport report, {
    required DateTime now,
  }) => symbolFor(
    glyph: glyphFor(report.type),
    severity: report.severity,
    freshness: freshnessFor(report, now),
  );

  static HazardMapSymbol symbolFor({
    required HazardMapGlyph glyph,
    required HazardSeverity severity,
    required HazardMapFreshness freshness,
  }) {
    final base = severityFill(severity);
    // Ageing shrinks the badge as well as dulling it and breaking its ring. Three
    // cues rather than one, because a single cue is a single point of failure at
    // ride zoom in sunlight.
    final scale = switch (freshness) {
      HazardMapFreshness.fresh => 1.0,
      HazardMapFreshness.ageing => 0.92,
      HazardMapFreshness.fading => 0.84,
    };
    final diameter = 34.0 * scale;
    return HazardMapSymbol(
      glyph: glyph,
      shape: HazardMapBadgeShape.circle,
      fill: fadedFill(base, freshness),
      freshness: freshness,
      diameterPixels: diameter,
      ringWidthPixels: 2.0,
      // Few, long dashes. Short ones were tried first and the render harness
      // showed why they cannot be used: at this size a dozen 6-pixel runs read as
      // teeth around the badge, like a cog or a torn stamp, rather than as a
      // broken outline. Four or five long runs read as a line with gaps in it.
      ringDashPixels: switch (freshness) {
        HazardMapFreshness.fresh => null,
        HazardMapFreshness.ageing => [diameter * 0.55, diameter * 0.28],
        HazardMapFreshness.fading => [diameter * 0.28, diameter * 0.42],
      },
    );
  }

  /// What a tap says: the kind, who saw it and when.
  ///
  /// One sentence rather than a panel, and the whole of it is the marker's
  /// tooltip and the message a tap shows, so nothing here needs a second
  /// interaction to read while moving.
  static String describe(HazardReport report, {required DateTime now}) {
    final reporter = report.source == HazardSource.rider
        ? (report.reporterName ?? 'a crew member')
        : (report.reporterName ?? report.providerId ?? 'a feed');
    final age = _relativeAge(now.difference(report.updatedAt));
    final confirmations = report.confirmations > 1
        ? ' · ${report.confirmations} crew'
        : '';
    final freshness = freshnessFor(report, now);
    final caveat = freshness == HazardMapFreshness.fresh
        ? ''
        : ' · ${freshness.label.toLowerCase()}';
    return '${report.type.label} · $reporter $age$confirmations$caveat';
  }

  /// Every symbol the map can draw, so the native renderer can register its
  /// images up front and one test can hold the whole set against #133's contrast
  /// rules rather than each colour being listed by hand.
  static List<HazardMapSymbol> get catalogue {
    final symbols = <String, HazardMapSymbol>{};
    for (final glyph in HazardMapGlyph.values) {
      for (final freshness in HazardMapFreshness.values) {
        for (final severity in HazardSeverity.values) {
          final symbol = symbolFor(
            glyph: glyph,
            severity: severity,
            freshness: freshness,
          );
          symbols[symbol.imageName] = symbol;
        }
      }
    }
    return symbols.values.toList(growable: false);
  }
}

String _relativeAge(Duration age) {
  if (age.isNegative || age.inSeconds < 60) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  return '${age.inHours} h ago';
}

/// Draws one [HazardMapSymbol] centred in the box it is given.
///
/// The single source of hazard artwork. [HazardMapSymbolBadge] wraps it for the
/// flutter_map fallback and [rasterizeHazardMapSymbolPng] bakes it for MapLibre,
/// so neither renderer can drift from the other.
class HazardMapSymbolPainter extends CustomPainter {
  const HazardMapSymbolPainter({required this.symbol, this.drawShadow = true});

  final HazardMapSymbol symbol;

  /// A soft drop shadow under the badge, so it lifts off a busy basemap.
  final bool drawShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = symbol.diameterPixels;
    final centre = Offset(size.width / 2, size.height / 2);
    final bounds = Rect.fromCenter(
      center: centre,
      width: diameter,
      height: diameter,
    );
    final badge = _badgePath(bounds);

    if (drawShadow) {
      canvas.drawPath(
        badge.shift(Offset(0, diameter * 0.045)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, diameter * 0.075),
      );
    }
    canvas.drawPath(badge, Paint()..color = symbol.fill);

    // Inset by half its width so the ring sits wholly inside the badge, the way
    // a Flutter `Border.all` does. Centred on the edge, a dashed ring's runs
    // poke out past the fill and the badge grows a fringe.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = symbol.ringWidthPixels
      ..strokeCap = StrokeCap.butt
      ..color = RouteTrailStyle.casing;
    final ringPath = _badgePath(bounds.deflate(symbol.ringWidthPixels / 2));
    final dashes = symbol.ringDashPixels;
    canvas.drawPath(
      dashes == null ? ringPath : _dashed(ringPath, dashes),
      ring,
    );

    _paintGlyph(canvas, bounds);
  }

  Path _badgePath(Rect bounds) {
    return Path()..addOval(bounds);
  }

  /// The glyph, drawn inside the badge with room for the ring.
  void _paintGlyph(Canvas canvas, Rect badge) {
    final inset = badge.width * 0.26;
    final box = badge.deflate(inset);
    final ink = Paint()..color = RouteTrailStyle.markerGlyph;
    _paintRoadDefect(canvas, box, ink);
  }

  /// The warning triangle the map already used for a road defect, drawn rather
  /// than borrowed from the icon font so it lands in the same harness as the
  /// other two and cannot be a filled box in it.
  void _paintRoadDefect(Canvas canvas, Rect box, Paint ink) {
    double x(double fraction) => box.left + box.width * fraction;
    double y(double fraction) => box.top + box.height * fraction;

    final corner = box.width * 0.10;
    final triangle = Path()
      ..moveTo(x(0.50), y(0.02))
      ..lineTo(x(1.0), y(0.94))
      ..lineTo(x(0.0), y(0.94))
      ..close();
    canvas.drawPath(
      triangle,
      Paint()
        ..color = RouteTrailStyle.markerGlyph
        ..style = PaintingStyle.stroke
        ..strokeWidth = corner
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        x(0.44),
        y(0.36),
        x(0.56),
        y(0.66),
        Radius.circular(corner * 0.6),
      ),
      ink,
    );
    canvas.drawCircle(Offset(x(0.50), y(0.80)), box.width * 0.07, ink);
  }

  /// [path] reduced to the on-runs of [dashes].
  static Path _dashed(Path path, List<double> dashes) {
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var index = 0;
      while (distance < metric.length) {
        final run = dashes[index % dashes.length];
        if (index.isEven) {
          dashed.addPath(
            metric.extractPath(distance, distance + run),
            Offset.zero,
          );
        }
        distance += run;
        index += 1;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(HazardMapSymbolPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.drawShadow != drawShadow;
}

/// The flutter_map fallback's hazard marker.
class HazardMapSymbolBadge extends StatelessWidget {
  const HazardMapSymbolBadge({
    super.key,
    required this.symbol,
    this.extentPixels = HazardMapSymbols.extentPixels,
  });

  final HazardMapSymbol symbol;
  final double extentPixels;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(extentPixels),
    painter: HazardMapSymbolPainter(symbol: symbol),
  );
}

/// How many device pixels the rasteriser puts into one logical pixel.
const hazardMapSymbolRasterScale = 4.0;

/// [symbol] baked to a PNG for `MapLibreMapController.addImage`.
///
/// Registered with `sdf: false`: this is full-colour artwork, not a shape mask,
/// so the badge fill and ring come out of the same painter the fallback uses
/// rather than out of a layer paint property the fallback has no equivalent for.
Future<Uint8List> rasterizeHazardMapSymbolPng(HazardMapSymbol symbol) async {
  const extent = HazardMapSymbols.extentPixels;
  final pixels = (extent * hazardMapSymbolRasterScale).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(hazardMapSymbolRasterScale);
  HazardMapSymbolPainter(
    symbol: symbol,
  ).paint(canvas, const Size(extent, extent));
  final image = await recorder.endRecording().toImage(pixels, pixels);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
