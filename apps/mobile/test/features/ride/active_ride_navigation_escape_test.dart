import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/app/balloon_crumbs_app.dart';
import 'package:balloon_crumbs/controllers/completed_rides_controller.dart';
import 'package:balloon_crumbs/controllers/distance_unit_controller.dart';
import 'package:balloon_crumbs/controllers/map_style_mode_controller.dart';
import 'package:balloon_crumbs/controllers/ride_code_preference_controller.dart';
import 'package:balloon_crumbs/controllers/ride_controller.dart';
import 'package:balloon_crumbs/controllers/rider_profile_controller.dart';
import 'package:balloon_crumbs/controllers/shared_route_controller.dart';
import 'package:balloon_crumbs/controllers/speed_limit_display_controller.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/data/in_memory_session_store.dart';
import 'package:balloon_crumbs/domain/completed_ride_store.dart';
import 'package:balloon_crumbs/domain/recorded_route_store.dart';
import 'package:balloon_crumbs/services/nearby_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Its own file on purpose.
///
/// The state this exercises is reached by running a whole simulated ride, and
/// it did not survive sharing a file with the other shell tests: the ride
/// refused to start at all once earlier tests had run against the same
/// process-wide controllers. A separate file is a separate isolate, so the
/// ride this drives is the only ride there has ever been.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _riderProfile = await RiderProfileController.load();
    await _riderProfile.completeOnboarding(
      displayName: 'Oliver',
      craftStyle: _riderProfile.craftStyle,
      riderColor: _riderProfile.riderColor,
      educationSkipped: false,
      rideChoice: OnboardingRideChoice.create,
    );
    _riderProfile.takePendingRideChoice();
    _sharedRoutes = await SharedRouteController.load();
    _speedLimitDisplay = SpeedLimitDisplayController.inMemory();
    _mapStyleMode = await MapStyleModeController.load();
    _rideCodePreference = RideCodePreferenceController.memory();
    _completedRides = await CompletedRidesController.load(
      InMemoryCompletedRideStore(),
    );
  });

  testWidgets('a moving pilot keeps the role navigation visible', (
    tester,
  ) async {
    // The defect: once a ride is under way on the map tab with a route and a
    // navigation fix, `hideWhileMoving` removes the whole navigation bar. Its
    // condition includes `_selectedIndex == 0`, so hiding the only control that
    // could change the index kept it hidden for the rest of the ride — Ride and
    // Settings were gone until the ride ended.
    //
    // It needs a *moving* ride with a route to appear, which is why a
    // stationary phone never showed it. That is the #133 pattern again.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await controller.createSimulationRide();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));
    expect(tester.takeException(), isNull, reason: 'initial shell');
    Future<void> pumpUntil(bool Function() satisfied) async {
      for (var attempt = 0; attempt < 60 && !satisfied(); attempt += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Same opening as the simulation test above: the lab tab has to reach
    // READY before the ride can be started.
    await pumpUntil(
      () => find.byIcon(Icons.science_outlined).evaluate().isNotEmpty,
    );
    await tester.tap(find.byIcon(Icons.science_outlined));
    await pumpUntil(() => find.text('READY').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull, reason: 'replay screen');
    await tester.tap(find.byKey(const Key('start-ride-button')));
    // Which dialogs the start puts up depends on whether the bundled demo
    // route has finished loading and whether anyone holds TEC, and that varies
    // with what ran before this test. Answer whichever appears rather than
    // assuming an order.
    const startButtons = [
      'start-without-route-button',
      'start-without-tec-button',
      'confirm-start-ride-button',
    ];
    for (var attempt = 0; attempt < 40 && !controller.rideStarted; attempt++) {
      var tapped = false;
      for (final key in startButtons) {
        final button = find.byKey(Key(key));
        if (button.evaluate().isNotEmpty) {
          await tester.tap(button);
          tapped = true;
          break;
        }
      }
      await tester.pump(
        tapped ? Duration.zero : const Duration(milliseconds: 100),
      );
    }
    expect(controller.rideStarted, isTrue);
    expect(tester.takeException(), isNull, reason: 'flight start');
    // The bikes have to be moving, not merely started: the navigation fix that
    // hides the bar comes from a simulated position.
    await pumpUntil(() => find.text('RUNNING').evaluate().isNotEmpty);
    expect(find.text('RUNNING'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'running replay');

    // Back to the map, which is where a rider actually rides.
    await tester.tap(find.text('Map').last);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'map tab');

    // A balloon role is not a road-navigation role. It keeps the main role
    // destinations visible even while the replay is moving; only a chase
    // driver's glance-limited road view may collapse this chrome.
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byType(NavigationBar),
      findsOneWidget,
      reason: 'a moving pilot must not inherit the driver-only chrome',
    );
    expect(find.byKey(const Key('ride-menu-button')), findsNothing);

    await tester.tap(find.text('Flight').last);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'flight tab');
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

late RiderProfileController _riderProfile;
late SharedRouteController _sharedRoutes;
late SpeedLimitDisplayController _speedLimitDisplay;
late MapStyleModeController _mapStyleMode;
late RideCodePreferenceController _rideCodePreference;
late CompletedRidesController _completedRides;
final _recordedRoutes = InMemoryRecordedRouteStore();

BalloonCrumbsApp _app(RideController controller) => BalloonCrumbsApp(
  controller: controller,
  distanceUnits: DistanceUnitController.forLocale(const Locale('en', 'GB')),
  mapStyleMode: _mapStyleMode,
  rideCodePreference: _rideCodePreference,
  riderProfile: _riderProfile,
  sharedRoutes: _sharedRoutes,
  speedLimitDisplay: _speedLimitDisplay,
  recordedRoutes: _recordedRoutes,
  completedRides: _completedRides,
  enableNativeServices: false,
);

Future<RideController> _controller() async {
  final controller = RideController(
    InMemoryEventStore(),
    InMemorySessionStore(),
    const _FakeNearbyBridge(),
  );
  await controller.initialize();
  return controller;
}

class _FakeNearbyBridge extends NearbyBridge {
  const _FakeNearbyBridge();

  @override
  Future<NearbyCapabilities> capabilities() async => const NearbyCapabilities(
    platform: 'test',
    nativeBridgeReady: true,
    nearbyApiLinked: false,
    status: 'phase0',
  );
}
