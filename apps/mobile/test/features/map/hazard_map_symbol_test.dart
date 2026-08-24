import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/hazard.dart';
import 'package:balloon_crumbs/features/map/hazard_map_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reportedAt = DateTime.utc(2026, 7, 27, 12);
  const position = GeoPoint(latitude: 51.5, longitude: -3.18);

  HazardReport report({
    HazardType type = HazardType.roadworks,
    HazardSeverity severity = HazardSeverity.serious,
    Duration life = const Duration(hours: 2),
    int confirmations = 1,
    String? reporterName = 'Alex',
    HazardSource source = HazardSource.rider,
    String? providerId,
  }) => HazardReport(
    id: 'report-1',
    rideId: 'flight-1',
    type: type,
    severity: severity,
    position: position,
    reportedAt: reportedAt,
    updatedAt: reportedAt,
    expiresAt: reportedAt.add(life),
    reporterId: 'device-1',
    reporterName: reporterName,
    source: source,
    providerId: providerId,
    confirmations: confirmations,
  );

  test('every road condition uses the generic warning symbol', () {
    for (final type in HazardType.values) {
      final symbol = HazardMapSymbols.forReport(
        report(type: type),
        now: reportedAt,
      );
      expect(symbol.glyph, HazardMapGlyph.roadDefect, reason: type.name);
      expect(symbol.shape, HazardMapBadgeShape.circle, reason: type.name);
    }
  });

  test('severity controls the fresh badge fill', () {
    for (final severity in HazardSeverity.values) {
      final symbol = HazardMapSymbols.forReport(
        report(severity: severity),
        now: reportedAt,
      );
      expect(symbol.fill, HazardMapSymbols.severityFill(severity));
    }
  });

  test('freshness is derived from the report lifetime', () {
    final value = report(life: const Duration(hours: 10));
    expect(
      HazardMapSymbols.freshnessFor(value, reportedAt),
      HazardMapFreshness.fresh,
    );
    expect(
      HazardMapSymbols.freshnessFor(
        value,
        reportedAt.add(const Duration(hours: 6)),
      ),
      HazardMapFreshness.ageing,
    );
    expect(
      HazardMapSymbols.freshnessFor(
        value,
        reportedAt.add(const Duration(hours: 9)),
      ),
      HazardMapFreshness.fading,
    );
  });

  test('description identifies crew and provider provenance', () {
    expect(
      HazardMapSymbols.describe(
        report(type: HazardType.roadworks, confirmations: 2),
        now: reportedAt,
      ),
      'Roadworks · Alex just now · 2 crew',
    );
    expect(
      HazardMapSymbols.describe(
        report(
          type: HazardType.collision,
          reporterName: null,
          source: HazardSource.externalProvider,
          providerId: 'relay-traffic',
        ),
        now: reportedAt,
      ),
      'Collision · relay-traffic just now',
    );
  });

  testWidgets('the badge paints at the declared extent', (tester) async {
    final symbol = HazardMapSymbols.forReport(report(), now: reportedAt);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: HazardMapSymbolBadge(symbol: symbol)),
      ),
    );

    final painted = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(HazardMapSymbolBadge),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(painted.size, const Size.square(HazardMapSymbols.extentPixels));
    expect((painted.painter! as HazardMapSymbolPainter).symbol, symbol);
  });

  testWidgets('every catalogue symbol rasterises', (tester) async {
    for (final symbol in HazardMapSymbols.catalogue) {
      final bytes = await tester.runAsync(
        () => rasterizeHazardMapSymbolPng(symbol),
      );
      expect(bytes, isNotEmpty, reason: symbol.imageName);
    }
  });
}
