import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/domain/distance_unit.dart';
import 'package:balloon_crumbs/domain/hazard.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/domain/geo_point.dart' as presence;
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/domain/rider_color.dart';
import 'package:balloon_crumbs/features/map/motorcycle_icon.dart';
import 'package:balloon_crumbs/services/basemap_configuration.dart';
import 'package:balloon_crumbs/services/carplay_bridge.dart';
import 'package:balloon_crumbs/services/navigation_camera.dart';
import 'package:balloon_crumbs/services/route_progress.dart';
import 'package:balloon_crumbs/services/route_journey_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/carplay');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('publishes a live map snapshot no more than once per second', () async {
    final calls = <MethodCall>[];
    var now = DateTime.utc(2026, 7, 23, 12);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final bridge = CarPlayBridge(channel: channel, clock: () => now);
    addTearDown(bridge.dispose);

    Future<void> publish() => bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
      routeName: 'Friday to the Ferry',
      rideState: 'Ride in progress',
      guidanceTitle: 'turn right',
      guidanceDetail: '400 m · A27',
      groupStatus: '5 riders visible',
    );

    await publish();
    now = now.add(const Duration(milliseconds: 900));
    await publish();
    now = now.add(const Duration(milliseconds: 100));
    await publish();

    expect(calls, hasLength(2));
    expect(calls.every((call) => call.method == 'updateSnapshot'), isTrue);
    expect(calls.first.arguments, {
      'routeId': null,
      'routeName': 'Friday to the Ferry',
      'routePoints': <Object?>[],
      'rideState': 'Ride in progress',
      'surfaceMode': 'activeRide',
      'canPlanRoute': false,
      'canFreeRoam': false,
      'followRider': false,
      'routeProgressMeters': null,
      'routeTotalMeters': null,
      'remainingRoutePoints': <Object?>[],
      'riddenRoutePoints': <Object?>[],
      'journeyProgress': null,
      'guidanceTitle': 'turn right',
      'guidanceDetail': '400 m · A27',
      'guidanceRoadName': null,
      'guidanceDistanceMeters': null,
      // Null here because this snapshot has neither a distance nor a speed. It is
      // never 0: zero tells CarPlay the rider is arriving now (#452).
      'guidanceSecondsRemaining': null,
      'distanceUnit': null,
      'groupStatus': '5 riders visible',
      'rideStart': null,
      'speed': null,
      'basemap': null,
      'updatedAtMillis': DateTime.utc(2026, 7, 23, 12).millisecondsSinceEpoch,
      'riders': <Object?>[],
      'alert': null,
    });
  });

  test('publishes the phone speed and mapped limit presentation', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final bridge = CarPlayBridge(channel: channel);
    addTearDown(bridge.dispose);

    await bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
      localSpeedMetersPerSecond: 10,
      localSpeedIsAgeing: true,
      speedLimitEnabled: true,
      speedLimitStatus: 'known',
      speedLimitMilesPerHour: 30,
    );

    expect((received!.arguments as Map)['speed'], {
      'metresPerSecond': 10.0,
      'isAgeing': true,
      'limitStatus': 'known',
      'limitMilesPerHour': 30,
      'limitUnlimited': false,
    });
  });

  test('projects the phone home map and saved rider identity', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final bridge = CarPlayBridge(channel: channel);
    addTearDown(bridge.dispose);

    await bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
      surfaceMode: CarPlaySurfaceMode.home,
      canPlanRoute: true,
      canFreeRoam: true,
      followRider: true,
      localPosition: const GeoPoint(latitude: 51.46, longitude: -2.51),
      localRider: const CarPlayLocalRider(
        riderId: 'installation-1',
        displayName: 'Oliver',
        motorcycleStyle: MotorcycleIconStyle.scrambler,
        riderSymbol: RiderSymbol.emoji('🦊'),
        riderColor: RiderColor.purple,
      ),
    );

    final snapshot = received!.arguments as Map;
    expect(snapshot['surfaceMode'], 'home');
    expect(snapshot['canPlanRoute'], isTrue);
    expect(snapshot['canFreeRoam'], isTrue);
    expect(snapshot['localRider'], {
      'riderId': 'installation-1',
      'label': 'Oliver',
      'isLocal': true,
      'role': 'Rider',
      'riderSymbol': 'emoji:🦊',
      'motorcycleStyle': 'scrambler',
      'riderColor': 'purple',
      'latitude': 51.46,
      'longitude': -2.51,
      'headingDegrees': null,
    });
  });

  test('publishes a bounded prepared-ride start action', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final bridge = CarPlayBridge(channel: channel);
    addTearDown(bridge.dispose);

    await bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
      rideStart: const CarPlayRideStart(
        enabled: true,
        detail: 'Friday route. Recording, sharing and navigation will start.',
        warning: 'No Hot Pursuit is assigned.',
      ),
    );

    expect((received!.arguments as Map)['rideStart'], {
      'enabled': true,
      'detail': 'Friday route. Recording, sharing and navigation will start.',
      'warning': 'No Hot Pursuit is assigned.',
      'unavailableReason': null,
    });
  });

  test('offers prepared-ride start only to an eligible leader', () {
    CarPlayRideStart? project({
      bool hasSession = true,
      bool isLeader = true,
      bool rideStarted = false,
      bool rideEnded = false,
      bool busy = false,
      bool locationReady = true,
      bool isGroup = false,
    }) => CarPlayRideStart.project(
      hasSession: hasSession,
      isLeader: isLeader,
      rideStarted: rideStarted,
      rideEnded: rideEnded,
      busy: busy,
      locationReady: locationReady,
      isGroup: isGroup,
    );

    expect(project(hasSession: false), isNull);
    expect(project(isLeader: false), isNull);
    expect(project(rideStarted: true), isNull);
    expect(project(rideEnded: true), isNull);

    final needsPermission = project(locationReady: false)!;
    expect(needsPermission.enabled, isFalse);
    expect(needsPermission.unavailableReason, contains('iPhone'));

    final saving = project(busy: true)!;
    expect(saving.enabled, isFalse);
    expect(saving.unavailableReason, contains('still being saved'));

    final solo = project()!;
    expect(solo.enabled, isTrue);
    expect(solo.warning, isNull);

    expect(project(isGroup: true)!.warning, isNull);
  });

  test(
    'a prepared-ride action appearing and disappearing jumps the throttle',
    () async {
      final calls = <MethodCall>[];
      var now = DateTime.utc(2026, 8, 3, 12);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final bridge = CarPlayBridge(channel: channel, clock: () => now);
      addTearDown(bridge.dispose);

      Future<void> publish({CarPlayRideStart? rideStart}) => bridge.publish(
        session: null,
        riderLocations: const [],
          activeHazards: const [],
        rideStart: rideStart,
      );

      await publish();
      now = now.add(const Duration(milliseconds: 100));
      await publish(
        rideStart: const CarPlayRideStart(
          enabled: true,
          detail: 'No route selected. Recording and sharing will start.',
        ),
      );
      now = now.add(const Duration(milliseconds: 100));
      await publish();

      expect(calls, hasLength(3));
      expect((calls[1].arguments as Map)['rideStart'], isNotNull);
      expect((calls[2].arguments as Map)['rideStart'], isNull);
    },
  );

  test('retries immediately after a native snapshot failure', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls += 1;
      if (calls == 1) {
        throw PlatformException(code: 'carplay_unavailable');
      }
      return null;
    });
    final bridge = CarPlayBridge(
      channel: channel,
      clock: () => DateTime.utc(2026, 8, 3, 12),
    );
    addTearDown(bridge.dispose);

    Future<void> publish() => bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
    );

    await publish();
    await publish();

    expect(calls, 2);
  });

  test(
    'projects the longest route path for the native navigation map',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final bridge = CarPlayBridge(channel: channel);
      addTearDown(bridge.dispose);
      final route = ImportedRoute(
        id: 'route-42',
        name: 'Friday to the Ferry',
        importedAt: DateTime.utc(2026, 7, 29),
        sourceFileName: 'friday.gpx',
        paths: const [
          RoutePath(
            kind: RoutePathKind.route,
            points: [
              GeoPoint(latitude: 51.45, longitude: -2.58),
              GeoPoint(latitude: 51.451, longitude: -2.58),
            ],
          ),
          RoutePath(
            kind: RoutePathKind.track,
            points: [
              GeoPoint(latitude: 51.45, longitude: -2.58),
              GeoPoint(latitude: 51.46, longitude: -2.57),
              GeoPoint(latitude: 51.47, longitude: -2.56),
            ],
          ),
        ],
        waypoints: const [],
      );

      await bridge.publish(
        session: null,
        riderLocations: const [],
          activeHazards: const [],
        route: route,
        routeName: route.name,
        followRider: true,
        guidanceTitle: 'Turn left',
        guidanceRoadName: 'A420',
        guidanceDistanceMeters: 275,
        distanceUnit: DistanceUnit.miles,
      );

      final arguments = Map<String, Object?>.from(
        calls.single.arguments as Map,
      );
      expect(arguments['routeId'], 'route-42');
      expect(arguments['followRider'], isTrue);
      expect(arguments['guidanceRoadName'], 'A420');
      expect(arguments['guidanceDistanceMeters'], 275);
      // The estimate the car's ETA card renders. Present because this call
      // supplies a speed; null rather than 0 when it cannot be computed (#452).
      expect(
        arguments['guidanceSecondsRemaining'],
        anyOf(isNull, isA<double>()),
      );
      expect(arguments['distanceUnit'], 'miles');
      expect(arguments['routePoints'], [
        {'latitude': 51.45, 'longitude': -2.58},
        {'latitude': 51.46, 'longitude': -2.57},
        {'latitude': 51.47, 'longitude': -2.56},
      ]);
    },
  );

  test('projects route progress for matching CarPlay route styling', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final bridge = CarPlayBridge(channel: channel);
    addTearDown(bridge.dispose);

    await bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
      routeProgress: const RouteProgressGeometry(
        riddenPaths: [
          [
            GeoPoint(latitude: 51.45, longitude: -2.58),
            GeoPoint(latitude: 51.46, longitude: -2.57),
          ],
        ],
        remainingPaths: [
          [
            GeoPoint(latitude: 51.46, longitude: -2.57),
            GeoPoint(latitude: 51.47, longitude: -2.56),
          ],
        ],
        progressMeters: 1200,
        totalMeters: 2500,
      ),
    );

    final arguments = Map<String, Object?>.from(received!.arguments as Map);
    expect(arguments['routeProgressMeters'], 1200);
    expect(arguments['routeTotalMeters'], 2500);
    expect(arguments['riddenRoutePoints'], [
      {'latitude': 51.45, 'longitude': -2.58},
      {'latitude': 51.46, 'longitude': -2.57},
    ]);
    expect(arguments['remainingRoutePoints'], [
      {'latitude': 51.46, 'longitude': -2.57},
      {'latitude': 51.47, 'longitude': -2.56},
    ]);
  });

  test('projects route and next-stop estimates for CarPlay', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final bridge = CarPlayBridge(channel: channel);
    addTearDown(bridge.dispose);
    final arrival = DateTime.utc(2026, 8, 14, 15, 42);
    final waypointArrival = DateTime.utc(2026, 8, 14, 15, 20);

    await bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
      distanceUnit: DistanceUnit.miles,
      journeyProgress: RouteJourneyProgress(
        remainingDistanceMeters: 16093.44,
        remainingTime: const Duration(minutes: 42),
        arrivalTime: arrival,
        nextWaypointName: 'Chippenham',
        nextWaypointDistanceMeters: 8046.72,
        nextWaypointArrivalTime: waypointArrival,
      ),
    );

    final arguments = Map<String, Object?>.from(received!.arguments as Map);
    expect(arguments['journeyProgress'], {
      'remainingDistanceMeters': 16093.44,
      'remainingSeconds': 2520,
      'arrivalTimeMillis': arrival.millisecondsSinceEpoch,
      'nextWaypointName': 'Chippenham',
      'nextWaypointDistanceMeters': 8046.72,
      'nextWaypointArrivalTimeMillis': waypointArrival.millisecondsSinceEpoch,
    });
  });

  test(
    'publishes the phone navigation viewport without snapshot lag',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final bridge = CarPlayBridge(channel: channel);
      addTearDown(bridge.dispose);

      await bridge.publishViewport(
        const NavigationCameraViewport(
          latitude: 51.46,
          longitude: -2.57,
          zoom: 15.25,
          tilt: 42,
          bearing: 123,
          sourceViewportHeightPixels: 760,
          sourceViewportWidthPixels: 390,
          riderViewportFraction: 0.7,
          riderHorizontalViewportFraction: 2 / 3,
          leftHandTraffic: true,
          mapStyleUrl: 'https://tiles.example.com/day',
          mapStyleJson: '{"version":8,"sources":{},"layers":[]}',
        ),
      );

      expect(calls.first.method, 'updateMapStyle');
      expect(calls.first.arguments, {
        'styleJson': '{"version":8,"sources":{},"layers":[]}',
        'fallbackStyleUrl': 'https://tiles.example.com/day',
      });
      expect(calls.last.method, 'updateViewport');
      expect(calls.last.arguments, {
        'latitude': 51.46,
        'longitude': -2.57,
        'zoom': 15.25,
        'tilt': 42,
        'bearing': 123,
        'sourceViewportHeightPixels': 760,
        'sourceViewportWidthPixels': 390,
        'riderViewportFraction': 0.7,
        'riderHorizontalViewportFraction': 2 / 3,
        'leftHandTraffic': true,
        'mapStyleUrl': 'https://tiles.example.com/day',
      });
    },
  );

  test('publishes the phone rider symbol and identity colour', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final bridge = CarPlayBridge(channel: channel);
    addTearDown(bridge.dispose);
    final now = DateTime.utc(2026, 8, 3, 12);

    await bridge.publish(
      session: null,
      riderLocations: [
        RiderLocation(
          riderId: 'oliver',
          displayName: 'Oliver Holt',
          role: RideRole.rider,
          sample: LocationSample(
            position: const presence.GeoPoint(
              latitude: 51.45,
              longitude: -2.58,
            ),
            recordedAt: now,
            accuracyMeters: 6,
          ),
          receivedAt: now,
          motorcycleStyle: MotorcycleIconStyle.cafeRacer,
          riderSymbol: const RiderSymbol.initials(
            customInitials: 'OH',
            initialsInk: RiderInitialsInk.purple,
          ),
          riderColor: RiderColor.white,
        ),
      ],
      activeHazards: const [],
    );

    final rider =
        ((received!.arguments as Map)['riders'] as List).single as Map;
    expect(rider['riderSymbol'], 'initials:v1:T0g:purple');
    expect(rider['motorcycleStyle'], 'cafeRacer');
    expect(rider['riderColor'], 'white');
  });

  test(
    'projects a self-contained local rider and resolved map style',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return null;
      });
      final bridge = CarPlayBridge(channel: channel);
      addTearDown(bridge.dispose);
      final joinedAt = DateTime.utc(2026, 8, 3, 12);

      await bridge.publish(
        session: RideSession(
          rideId: 'ride-1',
          rideCode: '123456',
          inviteSecret: 'secret',
          joinToken: 'token',
          localRiderId: 'oliver',
          displayName: 'Oliver Holt',
          role: RideRole.lead,
          joinedAt: joinedAt,
          riderSymbol: const RiderSymbol.initials(),
          riderColor: RiderColor.orange,
        ),
        riderLocations: const [],
          activeHazards: const [],
        basemap: const BasemapConfiguration(
          styleUrl: 'https://tiles.example.com/day',
        ),
        mapStyleJson: '{"version":8,"sources":{},"layers":[]}',
        localPosition: const GeoPoint(latitude: 51.45, longitude: -2.58),
        localHeadingDegrees: 123,
      );

      final snapshot = received!.arguments as Map;
      expect(
        (snapshot['basemap'] as Map)['styleJson'],
        contains('"version":8'),
      );
      expect(snapshot['localPosition'], {
        'latitude': 51.45,
        'longitude': -2.58,
        'headingDegrees': 123.0,
      });
      expect(snapshot['localRider'], {
        'riderId': 'oliver',
        'label': 'Oliver Holt',
        'isLocal': true,
        'role': 'Lead',
        'riderSymbol': 'initials',
        'motorcycleStyle': 'adventureTourer',
        'riderColor': 'orange',
        'latitude': 51.45,
        'longitude': -2.58,
        'headingDegrees': 123.0,
      });
    },
  );

  test('replays the latest style and viewport when CarPlay connects', () async {
    final calls = <MethodCall>[];
    var refreshes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final bridge = CarPlayBridge(
      channel: channel,
      onStateRequested: () async {
        refreshes += 1;
      },
    );
    addTearDown(bridge.dispose);

    await bridge.publishViewport(
      const NavigationCameraViewport(
        latitude: 51.45,
        longitude: -2.58,
        zoom: 15,
        tilt: 30,
        bearing: 90,
        sourceViewportHeightPixels: 760,
        sourceViewportWidthPixels: 390,
        riderViewportFraction: 0.7,
        riderHorizontalViewportFraction: 2 / 3,
        leftHandTraffic: false,
        mapStyleUrl: 'https://tiles.example.com/day',
        mapStyleJson: '{"version":8,"sources":{},"layers":[]}',
      ),
    );
    calls.clear();

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('requestState')),
      (_) {},
    );

    expect(refreshes, 1);
    expect(calls.map((call) => call.method), [
      'updateMapStyle',
      'updateViewport',
    ]);
  });

  // Issue #128: one rider self-selects the role, the leader asks another, and
  // both carry RideRole.rider in the journal. The phone map already
  // resolves that to one back-marker; a head unit showing two is telling the
  // leader the group has two backs.
  test('carries both basemap styles to the head unit', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final bridge = CarPlayBridge(channel: channel);
    addTearDown(bridge.dispose);

    await bridge.publish(
      session: null,
      riderLocations: const [],
      activeHazards: const [],
      basemap: const BasemapConfiguration(
        styleUrl: 'https://tiles.example.com/day',
        darkStyleUrl: 'https://tiles.example.com/night',
      ),
    );

    expect((received!.arguments as Map)['basemap'], {
      'styleUrl': 'https://tiles.example.com/day',
      'darkStyleUrl': 'https://tiles.example.com/night',
      'selectedStyleUrl': 'https://tiles.example.com/day',
      'dark': false,
    });
  });

  // A build that configures only one style must not leave the car with an
  // empty URL and a blank map in whichever mode it happens to be in.
  test(
    'falls back to the day style when no dark style is configured',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return null;
      });
      final bridge = CarPlayBridge(channel: channel);
      addTearDown(bridge.dispose);

      await bridge.publish(
        session: null,
        riderLocations: const [],
          activeHazards: const [],
        basemap: const BasemapConfiguration(
          styleUrl: 'https://tiles.example.com/day',
        ),
      );

      expect((received!.arguments as Map)['basemap'], {
        'styleUrl': 'https://tiles.example.com/day',
        'darkStyleUrl': 'https://tiles.example.com/day',
        'selectedStyleUrl': 'https://tiles.example.com/day',
        'dark': false,
      });
    },
  );

  test('relays only rider-reportable CarPlay hazards', () async {
    final reports = <HazardType>[];
    final bridge = CarPlayBridge(
      channel: channel,
      onHazardReported: (type) async => reports.add(type),
    );
    addTearDown(bridge.dispose);

    Future<void> report(Object? arguments) => messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('reportHazard', arguments)),
      (_) {},
    );

    await report({'type': 'speedCamera'});
    await report({'type': 'policeActivity'});
    await report({'type': 'other'});
    await report({'type': 'notARealHazard'});
    await report({'type': 42});
    await report('pothole');

    expect(reports, [
      HazardType.speedCamera,
      HazardType.policeActivity,
      HazardType.other,
    ]);
  });

  test('relays a confirmed prepared-ride start request', () async {
    var starts = 0;
    final bridge = CarPlayBridge(
      channel: channel,
      onRideStartRequested: () async {
        starts += 1;
      },
    );
    addTearDown(bridge.dispose);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('startPreparedRide')),
      (_) {},
    );

    expect(starts, 1);
  });

  test('relays a CarPlay-confirmed leave request to the ride owner', () async {
    var leaves = 0;
    final bridge = CarPlayBridge(
      channel: channel,
      onLeaveRequested: () async {
        leaves += 1;
      },
    );
    addTearDown(bridge.dispose);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('leaveRide')),
      (_) {},
    );

    expect(leaves, 1);
  });

  test('searches only a submitted CarPlay destination query', () async {
    final queries = <String>[];
    final bridge = CarPlayBridge(
      channel: channel,
      onDestinationSearch: (query) async {
        queries.add(query);
        return const [
          CarPlayDestination(
            label: 'Chippenham, Wiltshire',
            point: GeoPoint(latitude: 51.46, longitude: -2.12),
          ),
        ];
      },
    );
    addTearDown(bridge.dispose);

    final response = await invokeDartChannel(
      messenger,
      channel,
      const MethodCall('searchDestinations', {'query': '  Chippenham  '}),
    );

    expect(queries, ['Chippenham']);
    expect(response, {
      'results': [
        {
          'label': 'Chippenham, Wiltshire',
          'latitude': 51.46,
          'longitude': -2.12,
        },
      ],
      'error': null,
    });
  });

  test('relays an exact destination, ride type, and free-roam start', () async {
    final plans = <(CarPlayDestination, bool?)>[];
    var freeRoamStarts = 0;
    final bridge = CarPlayBridge(
      channel: channel,
      onDestinationSelected: (destination, groupRide) async {
        plans.add((destination, groupRide));
      },
      onFreeRoamRequested: () async {
        freeRoamStarts += 1;
      },
    );
    addTearDown(bridge.dispose);

    final planned = await invokeDartChannel(
      messenger,
      channel,
      const MethodCall('planDestination', {
        'label': 'Chippenham, Wiltshire',
        'latitude': 51.46,
        'longitude': -2.12,
        'groupRide': true,
      }),
    );
    final invalid = await invokeDartChannel(
      messenger,
      channel,
      const MethodCall('planDestination', {
        'label': 'Invalid',
        'latitude': 95,
        'longitude': -2.12,
      }),
    );
    final freeRoam = await invokeDartChannel(
      messenger,
      channel,
      const MethodCall('startFreeRoam'),
    );

    expect(planned, {'ok': true, 'error': null});
    expect(invalid, {
      'ok': false,
      'error': 'That destination is invalid. Search again.',
    });
    expect(plans, hasLength(1));
    expect(plans.single.$1.label, 'Chippenham, Wiltshire');
    expect(plans.single.$1.point.latitude, 51.46);
    expect(plans.single.$2, isTrue);
    expect(freeRoam, {'ok': true, 'error': null});
    expect(freeRoamStarts, 1);
  });

  test('a retiring surface cannot clear the next surface handler', () async {
    var firstStarts = 0;
    var secondStarts = 0;
    final first = CarPlayBridge(
      channel: channel,
      onFreeRoamRequested: () async => firstStarts += 1,
    );
    final second = CarPlayBridge(
      channel: channel,
      onFreeRoamRequested: () async => secondStarts += 1,
    );
    addTearDown(second.dispose);

    // Mirrors Flutter's child replacement: the new shell has already installed
    // its handler when the old shell is finally unmounted.
    await first.dispose();
    final response = await invokeDartChannel(
      messenger,
      channel,
      const MethodCall('startFreeRoam'),
    );

    expect(response, {'ok': true, 'error': null});
    expect(firstStarts, 0);
    expect(secondStarts, 1);
  });
}

Future<Object?> invokeDartChannel(
  TestDefaultBinaryMessenger messenger,
  MethodChannel channel,
  MethodCall call,
) {
  final response = Completer<Object?>();
  messenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(call),
    (data) {
      response.complete(
        data == null ? null : channel.codec.decodeEnvelope(data),
      );
    },
  );
  return response.future;
}
