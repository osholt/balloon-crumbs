import 'dart:io';

import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/altitude_unit.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/map_orientation.dart';
import 'package:balloon_crumbs/domain/route_store.dart';
import 'package:balloon_crumbs/domain/distance_unit.dart';
import 'package:balloon_crumbs/domain/geo_point.dart' as live;
import 'package:balloon_crumbs/features/map/craft_icon.dart';
import 'package:balloon_crumbs/features/map/ride_map.dart';
import 'package:balloon_crumbs/services/basemap_configuration.dart';
import 'package:balloon_crumbs/services/gpx_import_source.dart';
import 'package:balloon_crumbs/services/offline_tile_cache.dart';
import 'package:balloon_crumbs/services/open_meteo_wind.dart';
import 'package:balloon_crumbs/services/route_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'forecast context follows the assigned role rather than camera mode',
    () {
      expect(
        rideMapShowsForecastContext(perspective: RideMapPerspective.balloon),
        isTrue,
        reason: 'airborne views default to forecast context',
      );
      expect(
        rideMapShowsForecastContext(
          perspective: RideMapPerspective.chase,
          explicitPreference: true,
        ),
        isTrue,
        reason: 'chase crew retain wind and airspace in the tactical camera',
      );
      expect(
        rideMapShowsForecastContext(
          perspective: RideMapPerspective.chase,
          explicitPreference: false,
        ),
        isFalse,
        reason: 'the driver road view explicitly suppresses forecast controls',
      );
    },
  );

  testWidgets(
    'balloon map shows aircraft telemetry and suppresses driving chrome',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync('balloon-map');
      addTearDown(() => directory.deleteSync(recursive: true));
      final navigation = ValueNotifier<MapNavigationPosition?>(
        MapNavigationPosition(
          point: const GeoPoint(latitude: 51.43, longitude: -2.70),
          recordedAt: DateTime.now(),
          speedMetersPerSecond: 7,
          headingDegrees: 245,
          accuracyMeters: 4,
          altitudeMeters: 226,
          altitudeSource: AltitudeSource.gnss,
          altitudeDatum: AltitudeDatum.relativeToLaunch,
          altitudeAccuracyMeters: 6,
          verticalSpeedMetersPerSecond: 1.2,
        ),
      );
      final trails = ValueNotifier<List<MapOverlayTrace>>([
        const MapOverlayTrace(
          id: 'balloon-track',
          label: 'Balloon ground track',
          kind: RiderTrailKind.balloonGroundTrack,
          points: [
            GeoPoint(
              latitude: 51.4459,
              longitude: -2.6413,
              elevationMeters: 50,
            ),
            GeoPoint(latitude: 51.44, longitude: -2.66, elevationMeters: 250),
            GeoPoint(latitude: 51.435, longitude: -2.68, elevationMeters: 650),
            GeoPoint(latitude: 51.43, longitude: -2.70, elevationMeters: 1150),
          ],
        ),
      ]);
      addTearDown(navigation.dispose);
      addTearDown(trails.dispose);
      final wind = WindForecastController(
        const _NoWindProvider(),
        initialField: WindForecastField(
          columns: const [
            WindForecastColumn(
              position: live.GeoPoint(latitude: 51.43, longitude: -2.70),
              vectors: [
                WindForecastVector(
                  altitudeMetersMsl: 20,
                  fromDegrees: 250,
                  speedKmh: 12,
                ),
                WindForecastVector(
                  altitudeMetersMsl: 1000,
                  fromDegrees: 300,
                  speedKmh: 30,
                ),
              ],
              surfaceGustKmh: 38,
            ),
          ],
          validAt: DateTime.utc(2026, 8, 21, 10),
          fetchedAt: DateTime.utc(2026, 8, 21, 9, 55),
          origin: WindForecastOrigin.bundledFallback,
          sourceLabel: 'Bundled demo wind',
        ),
      );
      addTearDown(wind.dispose);
      final cache = OfflineTileCache(
        rootDirectory: directory,
        configuration: const BasemapConfiguration(),
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(cache.dispose);
      MapOrientationMode? requestedOrientation;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: RideMapScreen(
            routeStore: InMemoryRouteStore(_roadRoute),
            routeImporter: RouteImporter(source: const _NoFileSource()),
            offlineTileCache: cache,
            navigationPosition: navigation,
            riderTrails: trails,
            windForecastController: wind,
            landingZone: const MapLandingZone(
              center: GeoPoint(latitude: 51.4128, longitude: -2.7584),
              label: 'Simulated landing zone',
            ),
            rideStarted: true,
            rideHasNoLeader: true,
            onEmergencyAlert: () async {},
            onLeaveRide: () async {},
            onOpenRideMenu: () async {},
            perspective: RideMapPerspective.balloon,
            mapOrientation: MapOrientationMode.northUp,
            onMapOrientationChanged: (mode) => requestedOrientation = mode,
            distanceUnit: DistanceUnit.miles,
            localCraftStyle: CraftIconStyle.fourByFour,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Releasing follow mode reproduces the maximum set of controls visible
      // in the reported screenshots without relying on a private map state.
      await tester.drag(find.byType(FlutterMap), const Offset(60, 0));
      await tester.pump();

      Future<void> expectUnclutteredChrome(Size size) async {
        tester.view.physicalSize = size;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.takeException(),
          isNull,
          reason: 'map chrome overflowed in $size',
        );

        const requiredKeys = [
          'ride-clock',
          'ride-menu-button',
          'balloon-altitude-card',
          'wind-forecast-chip',
          'emergency-alert-button',
          'leave-ride-button',
          'navigation-follow-button',
          'map-orientation-toggle',
        ];
        final rects = <String, Rect>{};
        for (final key in requiredKeys) {
          final finder = find.byKey(Key(key));
          expect(finder, findsOneWidget, reason: '$key is missing in $size');
          final rect = tester.getRect(finder);
          rects[key] = rect;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
        }

        final entries = rects.entries.toList(growable: false);
        for (var first = 0; first < entries.length; first += 1) {
          for (var second = first + 1; second < entries.length; second += 1) {
            expect(
              entries[first].value
                  .deflate(0.5)
                  .overlaps(entries[second].value.deflate(0.5)),
              isFalse,
              reason:
                  '${entries[first].key} overlaps ${entries[second].key} '
                  'in $size',
            );
          }
        }

        for (final key in const [
          'emergency-alert-button',
          'leave-ride-button',
        ]) {
          expect(rects[key]!.width, greaterThanOrEqualTo(48));
          expect(rects[key]!.height, greaterThanOrEqualTo(48));
        }
      }

      await expectUnclutteredChrome(const Size(390, 844));
      await expectUnclutteredChrome(const Size(844, 390));
      await expectUnclutteredChrome(const Size(390, 844));

      expect(find.byKey(const Key('balloon-altitude-card')), findsOneWidget);
      expect(find.text('North up'), findsOneWidget);
      await tester.tap(find.byKey(const Key('map-orientation-toggle')));
      expect(requestedOrientation, MapOrientationMode.directionUp);
      expect(find.byKey(const Key('ride-clock')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('ride-clock'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('balloon-altitude-card'))).dy,
        ),
        reason: 'the clock belongs above balloon telemetry',
      );
      expect(find.text('226 m'), findsOneWidget);
      expect(find.textContaining('↑ 1.2 m/s'), findsOneWidget);
      expect(find.textContaining('GNSS'), findsOneWidget);
      expect(find.textContaining('relative to launch'), findsOneWidget);
      expect(find.text('Not terrain clearance'), findsOneWidget);
      expect(find.byKey(const Key('aeronautical-chart-status')), findsNothing);
      expect(
        find.byKey(const Key('aeronautical-chart-status-position')),
        findsNothing,
      );
      expect(find.text('AIRSPACE UNAVAILABLE'), findsNothing);
      expect(find.byKey(const Key('balloon-map-info-button')), findsOneWidget);
      expect(find.byKey(const Key('balloon-altitude-legend')), findsNothing);
      expect(find.text('TRACK ALTITUDE · METRES'), findsNothing);
      expect(find.byKey(const Key('landing-zone-area-layer')), findsOneWidget);
      expect(
        find.byKey(const Key('landing-zone-marker-layer')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('wind-forecast-chip')), findsOneWidget);
      expect(
        find.byKey(const Key('wind-forecast-details-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('wind-forecast-control')), findsNothing);
      expect(find.byKey(const Key('wind-altitude-slider')), findsNothing);
      expect(find.byKey(const Key('wind-forecast-layer')), findsOneWidget);
      expect(find.textContaining('WIND · 500 M'), findsOneWidget);
      expect(find.byKey(const Key('no-leader-banner')), findsNothing);
      expect(find.text('NO RIDE LEADER'), findsNothing);

      await tester.tap(find.byKey(const Key('wind-forecast-toggle')));
      await tester.pump();
      expect(wind.enabled, isFalse);
      expect(find.byKey(const Key('wind-altitude-slider')), findsNothing);
      expect(find.byKey(const Key('wind-forecast-layer')), findsNothing);

      wind.setEnabled(true);
      wind.setSelectedAltitude(1000);
      await tester.pump();
      expect(find.textContaining('WIND · 1000 M'), findsOneWidget);
      expect(find.byKey(const Key('wind-forecast-layer')), findsOneWidget);

      await tester.tap(find.byKey(const Key('wind-forecast-details-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'wind sheet overflowed');
      expect(find.byKey(const Key('wind-forecast-control')), findsOneWidget);
      expect(find.byKey(const Key('wind-altitude-slider')), findsOneWidget);
      expect(find.textContaining('1000 M MSL'), findsOneWidget);
      expect(find.textContaining('BUNDLED REFERENCE'), findsOneWidget);
      expect(
        find.byKey(const Key('wind-surface-gust-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('38–38 km/h'), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('wind-forecast-control'))),
      ).pop();
      await tester.pumpAndSettle();

      final trackLayer = tester.widget<PolylineLayer>(
        find.byType(PolylineLayer),
      );
      expect(
        trackLayer.polylines.any(
          (line) => line.color == const Color(0xFF55E05B),
        ),
        isTrue,
      );
      expect(
        trackLayer.polylines.any(
          (line) => line.color == const Color(0xFFFFE45E),
        ),
        isTrue,
      );
      expect(
        trackLayer.polylines.any(
          (line) => line.color == const Color(0xFFFF4FA3),
        ),
        isTrue,
      );
      expect(
        trackLayer.polylines.any(
          (line) => line.color == RouteTrailStyle.routeAhead.color,
        ),
        isFalse,
        reason: 'the balloon viewport must not draw the chase road route',
      );

      await tester.tap(find.byKey(const Key('balloon-map-info-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'map sheet overflowed');
      expect(
        find.byKey(const Key('balloon-map-information-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('aeronautical-chart-information')),
        findsOneWidget,
      );
      expect(find.text('AIRSPACE UNAVAILABLE'), findsOneWidget);
      expect(
        find.textContaining('official AIP and NOTAM briefing'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('aeronautical-chart-key')), findsOneWidget);
      expect(find.text('Red / red hatching'), findsOneWidget);
      expect(find.text('Blue / pink'), findsOneWidget);
      expect(find.textContaining('GND means the surface'), findsOneWidget);
      expect(find.textContaining('shown in metres'), findsOneWidget);
      expect(find.byKey(const Key('balloon-altitude-legend')), findsOneWidget);
      expect(find.text('TRACK ALTITUDE · METRES'), findsOneWidget);

      for (final key in const [
        'posted-speed-limit-position',
        'speed-compass-cluster',
        'navigation-guidance-banner',
        'navigation-guidance-status-banner',
        'route-start-guidance-banner',
        'route-progress-panel-position',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }

      final markerBadges = tester.widgetList<RiderMarkerBadge>(
        find.byType(RiderMarkerBadge),
      );
      expect(
        markerBadges.any((badge) => badge.style == CraftIconStyle.balloon),
        isTrue,
        reason: 'the local aircraft must not inherit the profile 4x4 marker',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('feet preference converts telemetry and its legend together', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('balloon-feet-map');
    addTearDown(() => directory.deleteSync(recursive: true));
    final navigation = ValueNotifier<MapNavigationPosition?>(
      MapNavigationPosition(
        point: const GeoPoint(latitude: 51.43, longitude: -2.70),
        recordedAt: DateTime.now(),
        accuracyMeters: 4,
        altitudeMeters: 300,
        altitudeSource: AltitudeSource.gnss,
        altitudeDatum: AltitudeDatum.wgs84Geoid,
        altitudeAccuracyMeters: 6,
        verticalSpeedMetersPerSecond: 1.5,
      ),
    );
    addTearDown(navigation.dispose);
    final cache = OfflineTileCache(
      rootDirectory: directory,
      configuration: const BasemapConfiguration(),
      httpClient: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(cache.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RideMapScreen(
          routeStore: InMemoryRouteStore(_roadRoute),
          routeImporter: RouteImporter(source: const _NoFileSource()),
          offlineTileCache: cache,
          navigationPosition: navigation,
          perspective: RideMapPerspective.balloon,
          altitudeUnit: AltitudeUnit.feet,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('984 ft'), findsOneWidget);
    expect(find.textContaining('↑ 295 ft/min'), findsOneWidget);
    expect(find.textContaining('±20 ft'), findsOneWidget);

    await tester.tap(find.byKey(const Key('balloon-map-info-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('shown in feet'), findsOneWidget);
    expect(find.text('TRACK ALTITUDE · FEET'), findsOneWidget);
    expect(find.text('2953+ ft'), findsOneWidget);
  });

  testWidgets('balloon map draws an advisory forecast without road controls', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'balloon-forecast-map',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final cache = OfflineTileCache(
      rootDirectory: directory,
      configuration: const BasemapConfiguration(),
      httpClient: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(cache.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RideMapScreen(
          routeStore: InMemoryRouteStore(_forecastRoute),
          routeImporter: RouteImporter(source: const _NoFileSource()),
          offlineTileCache: cache,
          perspective: RideMapPerspective.balloon,
          rideStarted: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(
      layer.polylines.any(
        (line) =>
            line.color == BalloonAltitudeStyle.colorForMeters(510) &&
            line.points.length == 2,
      ),
      isTrue,
      reason:
          'the forecast line should remain visible and altitude-coloured for the pilot',
    );
    expect(find.byTooltip('Fit forecast plan'), findsOneWidget);
    expect(find.byTooltip('Navigate or export route'), findsNothing);
    expect(find.text('All turns for this route'), findsNothing);
  });
}

final _forecastRoute = ImportedRoute(
  id: 'balloon-forecast',
  name: 'Bath forecast',
  purpose: ImportedRoutePurpose.balloonForecast,
  importedAt: DateTime.utc(2026, 8, 23),
  sourceFileName: 'forecast.gpx',
  paths: [
    RoutePath(
      kind: RoutePathKind.track,
      points: [
        GeoPoint(
          latitude: 51.4459,
          longitude: -2.6413,
          elevationMeters: 120,
          recordedAt: DateTime.utc(2026, 8, 23, 6),
        ),
        GeoPoint(
          latitude: 51.4128,
          longitude: -2.7585,
          elevationMeters: 900,
          recordedAt: DateTime.utc(2026, 8, 23, 7, 15),
        ),
      ],
    ),
  ],
  waypoints: const [],
);

final _roadRoute = ImportedRoute(
  id: 'chase-road',
  name: 'Chase road route',
  importedAt: DateTime.utc(2026, 8, 20),
  sourceFileName: 'chase.gpx',
  paths: const [
    RoutePath(
      kind: RoutePathKind.route,
      points: [
        GeoPoint(latitude: 51.4459, longitude: -2.6413),
        GeoPoint(latitude: 51.4128, longitude: -2.7585),
      ],
    ),
  ],
  waypoints: const [],
  maneuvers: const [
    RouteManeuver(
      position: GeoPoint(latitude: 51.43, longitude: -2.70),
      type: 'turn',
      modifier: 'right',
      name: 'Road the balloon must not follow',
    ),
  ],
);

class _NoFileSource implements GpxImportSource {
  const _NoFileSource();

  @override
  Future<PickedGpxFile?> pickGpxFile() async => null;
}

class _NoWindProvider implements WindForecastProvider {
  const _NoWindProvider();

  @override
  Future<WindForecastField> fetch({
    required live.GeoPoint center,
    required DateTime at,
  }) => throw UnimplementedError();
}
