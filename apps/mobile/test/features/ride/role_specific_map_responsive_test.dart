import 'dart:io';

import 'package:balloon_crumbs/controllers/speed_limit_display_controller.dart';
import 'package:balloon_crumbs/domain/craft.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/route_store.dart';
import 'package:balloon_crumbs/features/map/ride_map.dart';
import 'package:balloon_crumbs/features/ride/active_ride_shell.dart';
import 'package:balloon_crumbs/services/basemap_configuration.dart';
import 'package:balloon_crumbs/services/gpx_import_source.dart';
import 'package:balloon_crumbs/services/offline_tile_cache.dart';
import 'package:balloon_crumbs/services/route_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const roles = [
    FlightRole.pilot,
    FlightRole.balloonCrew,
    FlightRole.chaseDriver,
    FlightRole.chaseCrew,
    FlightRole.observer,
  ];
  const profiles = [
    (name: 'small phone', size: Size(320, 568), textScale: 1.0),
    (name: 'landscape', size: Size(667, 375), textScale: 1.0),
    (name: 'large text', size: Size(390, 844), textScale: 2.0),
  ];

  test('each role has the intended recovery-map capability contract', () {
    expect(
      RecoveryMapRoleExperience.forRole(FlightRole.pilot),
      isA<RecoveryMapRoleExperience>()
          .having(
            (value) => value.perspective,
            'perspective',
            RideMapPerspective.balloon,
          )
          .having(
            (value) => value.showForecastContext,
            'forecast context',
            isTrue,
          )
          .having((value) => value.showRoadGuidance, 'road guidance', isFalse),
    );
    expect(
      RecoveryMapRoleExperience.forRole(FlightRole.balloonCrew).perspective,
      RideMapPerspective.balloon,
    );
    expect(
      RecoveryMapRoleExperience.forRole(
        FlightRole.chaseDriver,
      ).showRoadGuidance,
      isTrue,
    );
    expect(
      RecoveryMapRoleExperience.forRole(
        FlightRole.chaseDriver,
      ).showForecastContext,
      isFalse,
    );
    expect(
      RecoveryMapRoleExperience.forRole(
        FlightRole.chaseCrew,
      ).showForecastContext,
      isTrue,
    );
    expect(
      RecoveryMapRoleExperience.forRole(FlightRole.observer).showRoadGuidance,
      isFalse,
    );
  });

  for (final profile in profiles) {
    testWidgets('every role map fits the ${profile.name} profile', (
      tester,
    ) async {
      tester.view.physicalSize = profile.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'balloon-role-map-',
      );
      final cache = OfflineTileCache(
        rootDirectory: directory,
        configuration: const BasemapConfiguration(),
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(() {
        cache.dispose();
        directory.deleteSync(recursive: true);
      });

      for (final role in roles) {
        final experience = RecoveryMapRoleExperience.forRole(role);
        final speedLimitDisplay = experience.showRoadGuidance
            ? SpeedLimitDisplayController.inMemory()
            : null;
        final currentPosition = ValueNotifier<GeoPoint?>(null);
        final markers = ValueNotifier<List<MapOverlayMarker>>(const [
          MapOverlayMarker(
            id: 'rider-balloon',
            point: GeoPoint(latitude: 51.46, longitude: -2.58),
            label: 'Balloon · live',
            craftStyle: CraftIconStyle.balloon,
          ),
          MapOverlayMarker(
            id: 'rider-rover-1',
            point: GeoPoint(latitude: 51.44, longitude: -2.60),
            label: 'Recovery 1 · relayed',
            craftStyle: CraftIconStyle.fourByFour,
          ),
          MapOverlayMarker(
            id: 'rider-rover-2',
            point: GeoPoint(latitude: 51.43, longitude: -2.61),
            label: 'Recovery 2 · stale',
            craftStyle: CraftIconStyle.fourByFour,
          ),
          MapOverlayMarker(
            id: 'rider-rover-3',
            point: GeoPoint(latitude: 51.42, longitude: -2.62),
            label: 'Recovery 3 · unknown',
            craftStyle: CraftIconStyle.fourByFour,
          ),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(profile.textScale)),
                child: RideMapScreen(
                  routeStore: InMemoryRouteStore(),
                  routeImporter: RouteImporter(source: const _NoFileSource()),
                  offlineTileCache: cache,
                  mapStyleString: '{}',
                  currentPosition: currentPosition,
                  overlayMarkers: markers,
                  groupRiderCount: 5,
                  perspective: experience.perspective,
                  showForecastContext: experience.showForecastContext,
                  speedLimitDisplay: speedLimitDisplay,
                  showRouteProgress: experience.showRoadGuidance,
                  rideStarted: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final exception = tester.takeException();
        expect(exception, isNull, reason: role.name);
        expect(
          find.byKey(const Key('recovery-map-viewpoint')),
          findsOneWidget,
          reason: role.name,
        );
        expect(
          find.byKey(const Key('group-mini-map')),
          experience.perspective == RideMapPerspective.balloon
              ? findsNothing
              : findsOneWidget,
          reason: role.name,
        );
        if (profile.name == 'small phone' && role == FlightRole.pilot) {
          await tester.tap(find.byKey(const Key('recovery-map-viewpoint')));
          await tester.pumpAndSettle();
          expect(find.text('My craft'), findsOneWidget);
          expect(find.text('Balloon'), findsAtLeastNWidgets(1));
          expect(find.text('Whole crew'), findsOneWidget);
          final balloonChoice = find.byWidgetPredicate(
            (widget) =>
                widget is PopupMenuItem<RecoveryMapViewpoint> &&
                widget.value == RecoveryMapViewpoint.balloon,
          );
          expect(balloonChoice, findsOneWidget);
          await tester.tap(balloonChoice);
          await tester.pumpAndSettle(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
        }

        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        currentPosition.dispose();
        markers.dispose();
        speedLimitDisplay?.dispose();
      }
    });
  }
}

class _NoFileSource implements GpxImportSource {
  const _NoFileSource();

  @override
  Future<PickedGpxFile?> pickGpxFile() async => null;
}
