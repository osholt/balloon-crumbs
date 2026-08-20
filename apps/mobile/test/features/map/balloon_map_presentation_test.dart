import 'dart:io';

import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/route_store.dart';
import 'package:balloon_crumbs/features/map/craft_icon.dart';
import 'package:balloon_crumbs/features/map/ride_map.dart';
import 'package:balloon_crumbs/services/basemap_configuration.dart';
import 'package:balloon_crumbs/services/gpx_import_source.dart';
import 'package:balloon_crumbs/services/offline_tile_cache.dart';
import 'package:balloon_crumbs/services/route_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'balloon map shows aircraft telemetry and suppresses driving chrome',
    (tester) async {
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
            GeoPoint(latitude: 51.4459, longitude: -2.6413),
            GeoPoint(latitude: 51.43, longitude: -2.70),
          ],
        ),
      ]);
      addTearDown(navigation.dispose);
      addTearDown(trails.dispose);
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
            riderTrails: trails,
            rideStarted: true,
            perspective: RideMapPerspective.balloon,
            localMotorcycleStyle: CraftIconStyle.fourByFour,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('balloon-altitude-card')), findsOneWidget);
      expect(find.text('226 m'), findsOneWidget);
      expect(find.textContaining('↑ 1.2 m/s'), findsOneWidget);
      expect(find.textContaining('GNSS'), findsOneWidget);
      expect(find.textContaining('relative to launch'), findsOneWidget);
      expect(find.text('Not terrain clearance'), findsOneWidget);
      expect(
        find.byKey(const Key('aeronautical-chart-status')),
        findsOneWidget,
      );
      expect(find.text('AIRSPACE UNAVAILABLE'), findsOneWidget);

      final trackLayer = tester.widget<PolylineLayer>(
        find.byType(PolylineLayer),
      );
      expect(
        trackLayer.polylines.any(
          (line) => line.color == RouteTrailStyle.balloonGroundTrack.color,
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
}

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
