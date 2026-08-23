import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/chase_vehicle_controller.dart';
import '../../controllers/distance_unit_controller.dart';
import '../../controllers/completed_rides_controller.dart';
import '../../controllers/map_style_mode_controller.dart';
import '../../controllers/ride_code_preference_controller.dart';
import '../../controllers/ride_controller.dart';
import '../../controllers/route_progress_display_controller.dart';
import '../../controllers/rider_profile_controller.dart';
import '../../controllers/shared_route_controller.dart';
import '../../controllers/speed_limit_display_controller.dart';
import '../../controllers/ride_diagnostics_controller.dart';
import '../../controllers/spoken_guidance_controller.dart';
import '../../domain/imported_route.dart' show GeoPoint, ImportedRoute;
import '../../domain/geo_point.dart' as awareness_geo;
import '../../domain/landing_zone.dart';
import '../../domain/map_style_mode.dart';
import '../../domain/flight_role.dart';
import '../../services/road_routing.dart';
import 'home_destination_search.dart';
import 'home_map_backdrop.dart';
import 'home_ride_actions.dart';
import 'scan_invitation_screen.dart';
import '../../controllers/test_control_controller.dart';
import '../../domain/join_invite.dart';
import '../../domain/recorded_route_store.dart';
import '../../domain/ride_coordination_mode.dart';
import '../../internet/plan_directory.dart';
import '../../services/build_identity.dart';
import '../../services/basemap_configuration.dart';
import '../../services/carplay_bridge.dart';
import '../../services/gpx_import_source.dart';
import '../../services/forecast_plan_importer.dart';
import '../../services/flight_planner_launcher.dart';
import '../../services/stored_route_library.dart';
import '../../services/landing_zone_library.dart';
import '../map/ride_map_feature.dart';
import '../map/stored_route_picker.dart';
import '../ride/previous_rides_screen.dart';
import '../ride/route_recorder_screen.dart';
import '../settings/about_build_sheet.dart';
import '../settings/emergency_info_sheet.dart';
import '../settings/unit_settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.distanceUnits,
    required this.mapStyleMode,
    required this.rideCodePreference,
    required this.riderProfile,
    required this.sharedRoutes,
    required this.speedLimitDisplay,
    this.chaseVehicle,
    this.routeProgressDisplay,
    required this.recordedRoutes,
    required this.completedRides,
    this.planDirectory,
    this.testControl,
    this.spokenGuidance,
    this.rideDiagnostics,
    this.restoringRideCode,
    this.restorationError,
    this.onRetryRestoration,
    this.openJoinGroup = false,
    this.onJoinGroupOpened,
    this.enableNativeServices = true,
    this.flightPlannerLauncher = const FlightPlannerLauncher(),
  });

  final RideController controller;
  final DistanceUnitController distanceUnits;
  final MapStyleModeController mapStyleMode;
  final RideCodePreferenceController rideCodePreference;
  final RiderProfileController riderProfile;
  final SharedRouteController sharedRoutes;
  final SpeedLimitDisplayController speedLimitDisplay;
  final ChaseVehicleController? chaseVehicle;
  final RouteProgressDisplayController? routeProgressDisplay;
  final RecordedRouteStore recordedRoutes;
  final CompletedRidesController completedRides;
  final PlanDirectory? planDirectory;

  /// Null unless this build carries the test-control define; only forwarded to
  /// the settings sheet.
  final TestControlController? testControl;

  /// Whether turn instructions are spoken (#286). Forwarded to the settings
  /// sheet, which is where a rider opts in.
  final SpokenGuidanceController? spokenGuidance;

  /// Null in an ordinary build. Threaded so the Settings sheet opened from
  /// *here* offers the recorder too — wiring only the ride shell's sheet is
  /// what hid it from a tester who had never started a ride (#419).
  final RideDiagnosticsController? rideDiagnostics;

  final String? restoringRideCode;
  final Object? restorationError;
  final VoidCallback? onRetryRestoration;

  /// Set while an unstarted solo session is being replaced from the map. The
  /// ordinary join sheet opens as soon as Home owns the screen again (#261).
  final bool openJoinGroup;
  final VoidCallback? onJoinGroupOpened;

  /// False in widget tests and plugin-less builds; the map backdrop stands
  /// down rather than waiting on a platform map that will never load.
  final bool enableNativeServices;

  /// Opens the shared production pilot planner in the platform browser view.
  /// Injected in tests so discoverability and failure handling do not require a
  /// native browser plugin.
  final FlightPlannerLauncher flightPlannerLauncher;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _buildIdentity = BuildIdentity.fromEnvironment();
  bool _joinGroupOpenScheduled = false;
  late final CarPlayBridge _carPlayBridge;
  String? _carPlayMapStyleJson;
  final _landingZone = ValueNotifier<MapLandingZone?>(null);
  LandingZoneTarget? _landingTarget;
  LandingZoneLibrary? _landingZoneLibrary;
  List<LandingZoneTarget> _recentLandingZones = const [];
  bool _selectingLandingZone = false;
  double _landingRadiusMeters = 500;

  @override
  void initState() {
    super.initState();
    _carPlayBridge = CarPlayBridge(
      onDestinationSearch: _searchCarPlayDestinations,
      onDestinationSelected: _planCarPlayDestination,
      onFreeRoamRequested: _startCarPlayFreeRoam,
      onStateRequested: () async => _publishHomeCarPlayState(),
    );
    _position.addListener(_publishHomeCarPlayState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishHomeCarPlayState();
    });
    unawaited(_loadLandingZones());
    if (widget.openJoinGroup) {
      _scheduleJoinGroupSheet();
      return;
    }
    final choice = widget.riderProfile.takePendingRideChoice();
    if (choice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showRideSheet(
            context,
            creating: choice == OnboardingRideChoice.create,
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishHomeCarPlayState();
    });
    if (!oldWidget.openJoinGroup && widget.openJoinGroup) {
      _scheduleJoinGroupSheet();
    }
  }

  void _scheduleJoinGroupSheet() {
    if (_joinGroupOpenScheduled) return;
    _joinGroupOpenScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      widget.onJoinGroupOpened?.call();
      await _showRideSheet(context, creating: false);
      _joinGroupOpenScheduled = false;
    });
  }

  /// Where the rider is, shared with the map below so a searched destination can
  /// be routed from here (#431).
  final _position = ValueNotifier<GeoPoint?>(null);

  @override
  void dispose() {
    // This screen had nothing to dispose until #431 gave it a notifier it shares
    // with the map and a client it lends to the geocoder.
    _position.removeListener(_publishHomeCarPlayState);
    unawaited(_carPlayBridge.dispose());
    _position.dispose();
    _landingZone.dispose();
    _routingClient.close();
    super.dispose();
  }

  Future<void> _loadLandingZones() async {
    final library = await LandingZoneLibrary.open();
    if (!mounted) return;
    setState(() {
      _landingZoneLibrary = library;
      _recentLandingZones = library.load();
    });
  }

  Future<void> _setLandingZone(GeoPoint point, {String? label}) async {
    final target = LandingZoneTarget(
      center: awareness_geo.GeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
      radiusMeters: _landingRadiusMeters,
      label:
          label ??
          'Intended area · ${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)}',
      updatedAt: DateTime.now(),
    );
    _applyLandingZone(target);
    final library = _landingZoneLibrary;
    if (library == null) return;
    final recent = await library.remember(target);
    if (mounted) setState(() => _recentLandingZones = recent);
  }

  void _applyLandingZone(LandingZoneTarget target) {
    _landingTarget = target;
    _landingRadiusMeters = target.radiusMeters;
    _landingZone.value = _mapLandingZone(target);
    setState(() => _selectingLandingZone = false);
  }

  static MapLandingZone _mapLandingZone(LandingZoneTarget target) =>
      MapLandingZone(
        center: GeoPoint(
          latitude: target.center.latitude,
          longitude: target.center.longitude,
        ),
        radiusMeters: target.radiusMeters,
        label: target.label,
      );

  void _changeLandingRadius(double radius) {
    _landingRadiusMeters = radius;
    final current = _landingTarget;
    if (current != null) {
      final updated = LandingZoneTarget(
        center: current.center,
        radiusMeters: radius,
        label: current.label,
        updatedAt: DateTime.now(),
      );
      _landingTarget = updated;
      _landingZone.value = _mapLandingZone(updated);
    }
    setState(() {});
  }

  /// True while a route is being planned, which disables the actions so a rider
  /// cannot start a second ride on top of the one being arranged.
  bool _planningDestination = false;

  /// Built once, and deliberately one instance: `NominatimDestinationSearchService`
  /// caches by query, so planning a route to a result the rider just searched for
  /// is a cache hit rather than a second call to a public geocoder that asks for
  /// no more than one a second.
  final _routingClient = http.Client();

  late final DestinationRoutePlanner _destinationPlanner = () {
    final configuration = RoutingConfiguration.fromEnvironment();
    return DestinationRoutePlanner(
      searchService: NominatimDestinationSearchService(
        client: _routingClient,
        baseUrl: configuration.geocodingBaseUrl,
      ),
      routingService: OsrmRoadRoutingService(
        client: _routingClient,
        baseUrl: configuration.routingBaseUrl,
      ),
    );
  }();

  BasemapConfiguration get _homeBasemap =>
      BasemapConfiguration.fromEnvironment().forBrightness(
        dark: widget.mapStyleMode.resolveDark(
          MediaQuery.platformBrightnessOf(context),
        ),
        restrainedLightStyle:
            widget.mapStyleMode.dayStyle == DayMapStyle.restrained,
      );

  void _publishHomeCarPlayState() {
    if (!mounted) return;
    final position = _position.value;
    unawaited(
      _carPlayBridge.publish(
        session: null,
        riderLocations: const [],
        activeHazards: const [],
        rideState: _planningDestination
            ? 'Planning route…'
            : 'Ready to plan or free roam',
        surfaceMode: CarPlaySurfaceMode.home,
        canPlanRoute: true,
        canFreeRoam: true,
        followRider: position != null,
        distanceUnit: widget.distanceUnits.value,
        basemap: _homeBasemap,
        mapStyleJson: _carPlayMapStyleJson,
        localPosition: position,
        localRider: CarPlayLocalRider(
          riderId: widget.riderProfile.installationId,
          displayName: widget.riderProfile.displayName,
          motorcycleStyle: widget.riderProfile.motorcycleStyle,
          riderSymbol: widget.riderProfile.riderSymbol,
          riderColor: widget.riderProfile.riderColor,
        ),
      ),
    );
  }

  Future<List<CarPlayDestination>> _searchCarPlayDestinations(
    String query,
  ) async => [
    for (final match in await _destinationPlanner.searchService.search(query))
      CarPlayDestination(label: match.label, point: match.point),
  ];

  Future<void> _planCarPlayDestination(
    CarPlayDestination destination,
    bool? groupRide,
  ) async {
    if (_planningDestination || widget.controller.busy) {
      throw const FormatException('Flight setup is already in progress.');
    }
    final origin = _position.value;
    if (origin == null) {
      throw const FormatException(
        'Show your location on the iPhone before planning from CarPlay.',
      );
    }
    if (groupRide == null) {
      throw const FormatException(
        'Choose a solo or crew flight and try again.',
      );
    }
    final controller = widget.controller;
    final profile = widget.riderProfile;
    setState(() => _planningDestination = true);
    _publishHomeCarPlayState();
    try {
      final plan = await _destinationPlanner.planForReview(
        origin: origin,
        query: destination.label,
        selectedDestination: DestinationMatch(
          label: destination.label,
          point: destination.point,
        ),
        distanceUnit: widget.distanceUnits.value,
      );
      await controller.createRide(
        profile.displayName,
        motorcycleStyle: profile.motorcycleStyle,
        riderSymbol: profile.riderSymbol,
        riderColor: profile.riderColor,
        coordinationMode: groupRide
            ? RideCoordinationMode.keepTogether
            : RideCoordinationMode.solo,
        rideName: destination.label,
      );
      // Publish the exact selected route before the active shell restores. The
      // authoritative journal then drives both phone and CarPlay without a
      // phone-only review sheet blocking the in-car flow.
      await controller.publishRoute(plan.route);
    } finally {
      if (mounted) {
        setState(() => _planningDestination = false);
        _publishHomeCarPlayState();
      }
    }
  }

  Future<void> _startCarPlayFreeRoam() async {
    if (_planningDestination || widget.controller.busy) {
      throw const FormatException('Flight setup is already in progress.');
    }
    if (_position.value == null) {
      throw const FormatException(
        'Show your location on the iPhone before starting free roam.',
      );
    }
    final controller = widget.controller;
    final profile = widget.riderProfile;
    await controller.createRide(
      profile.displayName,
      motorcycleStyle: profile.motorcycleStyle,
      riderSymbol: profile.riderSymbol,
      riderColor: profile.riderColor,
      coordinationMode: RideCoordinationMode.solo,
      rideName: 'Free roam',
    );
    await controller.startRide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The app opens on the map and the map is the *surface*, not a backdrop
      // (#426). #405 asked for this and #407 delivered a map behind a
      // full-screen panel — a brand mark, a heading, a paragraph, four buttons,
      // two links and a footer over a gradient covering the whole screen. From
      // the ride: "I don't want the start screen at all. I want the selection of
      // starting a ride to happen from the map view."
      //
      // So there is no panel and no scrim. What is left standing on the map is
      // one bar of actions at the bottom, the two controls at the top right, and
      // notices only when there is something to say.
      body: Stack(
        fit: StackFit.expand,
        children: [
          HomeMapBackdrop(
            mapStyleMode: widget.mapStyleMode,
            speedLimitDisplay: widget.speedLimitDisplay,
            distanceUnit: widget.distanceUnits.value,
            completedRideStore: widget.completedRides,
            enableNativeServices: widget.enableNativeServices,
            // So the map's own "Show my location" control sits above the action
            // bar rather than under it.
            bottomInset: HomeRideActions.reservedHeight,
            position: _position,
            landingZone: _landingZone,
            onMapTap: _selectingLandingZone ? _setLandingZone : null,
            onMapStyleResolved: (styleJson) {
              _carPlayMapStyleJson = styleJson;
              final basemap = _homeBasemap;
              unawaited(
                _carPlayBridge.publishMapStyle(
                  styleJson: styleJson,
                  fallbackStyleUrl: basemap.styleUrl,
                ),
              );
              _publishHomeCarPlayState();
            },
          ),
          SafeArea(
            child: Stack(
              children: [
                // Notices, and nothing when there are none. Each of these used
                // to sit in the scrolling column of a full-screen panel, which
                // is why the panel existed at all; they are now cards on the map
                // that appear and go.
                Positioned(
                  top: 6,
                  left: 12,
                  child: FilledButton.tonalIcon(
                    key: const Key('search-landing-area'),
                    onPressed: () => unawaited(_searchLandingArea()),
                    icon: const Icon(Icons.search),
                    label: const Text('Search area'),
                  ),
                ),
                Positioned(
                  top: 60,
                  left: 12,
                  right: 12,
                  child: _HomeNotices(children: _notices(context)),
                ),
                Positioned(
                  top: 4,
                  right: 8,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Emergency info',
                        onPressed: () => EmergencyInfoSheet.show(
                          context,
                          widget.riderProfile,
                        ),
                        icon: const Icon(Icons.medical_information_outlined),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => UnitSettingsSheet.show(
                          context,
                          widget.distanceUnits,
                          widget.mapStyleMode,
                          widget.riderProfile,
                          speedLimitDisplay: widget.speedLimitDisplay,
                          chaseVehicle: widget.chaseVehicle,
                          routeProgressDisplay: widget.routeProgressDisplay,
                          testControl: widget.testControl,
                          spokenGuidance: widget.spokenGuidance,
                          rideDiagnostics: widget.rideDiagnostics,
                        ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: HomeRideActions(
              enabled:
                  !widget.controller.busy &&
                  !_planningDestination &&
                  !(widget.controller.rideSetAside &&
                      !widget.controller.rideEnded) &&
                  widget.onRetryRestoration == null,
              onCreate: () => _showRideSheet(context, creating: true),
              onJoin: () => _showRideSheet(context, creating: false),
              onMore: () => unawaited(_showMoreActions(context)),
              landingZone: _landingZone.value,
              selectingLandingZone: _selectingLandingZone,
              radiusMeters: _landingRadiusMeters,
              recentLandingZoneCount: _recentLandingZones.length,
              onSelectLandingZone: () =>
                  setState(() => _selectingLandingZone = true),
              onCancelSelection: () =>
                  setState(() => _selectingLandingZone = false),
              onRadiusChanged: _changeLandingRadius,
              onPreviousLandingZones: _recentLandingZones.isEmpty
                  ? null
                  : () => unawaited(_showPreviousLandingZones()),
            ),
          ),
        ],
      ),
    );
  }

  /// The banners that have something to say right now.
  ///
  /// Returned as a list rather than built inline so "are there any" is a question
  /// the layout can answer — a notices area that reserved space for nothing would
  /// be a small panel, which is the thing being removed.
  List<Widget> _notices(BuildContext context) => [
    TesterUpdateBanner(identity: _buildIdentity),
    if (widget.onRetryRestoration != null)
      _RideRestorationBanner(
        rideCode: widget.restoringRideCode,
        error: widget.restorationError,
        onRetry: widget.onRetryRestoration!,
      ),
    if (widget.controller.endedRideSetAside)
      _SetAsideRideBanner(
        rideCode: widget.controller.session!.rideCode,
        running: false,
        onReopen: widget.controller.reopenEndedRide,
      ),
    if (widget.controller.rideSetAside && !widget.controller.rideEnded)
      _SetAsideRideBanner(
        rideCode: widget.controller.session!.rideCode,
        running: true,
        onReopen: widget.controller.reopenEndedRide,
      ),
    if (widget.sharedRoutes.pending case final file?)
      _PendingSharedRouteBanner(
        fileName: file.name,
        onDismiss: widget.sharedRoutes.clearPending,
      ),
    if (widget.sharedRoutes.plannerLinkStatus != PlannerLinkStatus.idle)
      _PlannerLinkStatusBanner(
        status: widget.sharedRoutes.plannerLinkStatus,
        message:
            widget.sharedRoutes.plannerLinkMessage ?? 'Loading shared route…',
        canRetry: widget.sharedRoutes.canRetryPlannerLink,
        onRetry: () => unawaited(widget.sharedRoutes.retryPlannerLink()),
        onDismiss: widget.sharedRoutes.clearPlannerLinkNotice,
      ),
  ];

  /// The occasional actions, behind one button.
  ///
  /// Each of these was a permanent row on the old panel. None is used often enough
  /// to be worth a strip of map, and together they were most of what made the
  /// panel full-screen.
  Future<void> _showMoreActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF171D25),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const Key('open-flight-planner'),
              leading: const Icon(Icons.air_outlined),
              title: const Text('Plan a balloon flight'),
              subtitle: const Text(
                'Wind route, landing envelope and timed altitude profile',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_openFlightPlanner());
              },
            ),
            ListTile(
              key: const Key('start-flight-replay'),
              leading: const Icon(Icons.science_outlined),
              title: const Text('Replay the Fiesta flight'),
              subtitle: const Text(
                'Recorded wind, balloon track and chase route · stays on this phone',
              ),
              enabled:
                  !widget.controller.busy && widget.onRetryRestoration == null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.controller.createSimulationRide();
              },
            ),
            ListTile(
              key: const Key('record-a-route-button'),
              leading: const Icon(Icons.fiber_manual_record_outlined),
              title: const Text('Record a chase route'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  RouteRecorderScreen.show(context, widget.recordedRoutes),
                );
              },
            ),
            ListTile(
              key: const Key('flight-library-button'),
              leading: const Icon(Icons.route_outlined),
              title: const Text('Flight library'),
              subtitle: Text(
                widget.completedRides.rides.isEmpty
                    ? 'Recorded chase routes and previous flights'
                    : 'Recorded routes and ${widget.completedRides.rides.length} previous flight${widget.completedRides.rides.length == 1 ? '' : 's'}',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_openRideLibrary(context));
              },
            ),
            const Divider(height: 8),
            ListTile(
              key: const Key('home-build-identity'),
              leading: const Icon(Icons.info_outline),
              title: Text(
                '${_buildIdentity.versionLabel} · '
                '${_buildIdentity.track.label}',
              ),
              subtitle: const Text('No account required'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  AboutBuildSheet.show(context, identity: _buildIdentity),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFlightPlanner() async {
    var opened = false;
    try {
      opened = await widget.flightPlannerLauncher.open();
    } on Object {
      opened = false;
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the flight planner. Check your connection and try again.',
        ),
      ),
    );
  }

  Future<void> _searchLandingArea() async {
    final choice = await LandingZoneSearchSheet.show(
      context,
      searchService: _destinationPlanner.searchService,
    );
    if (choice == null || !mounted) return;
    await _setLandingZone(choice.point, label: choice.label);
  }

  Future<void> _showPreviousLandingZones() async {
    final selected = await showModalBottomSheet<LandingZoneTarget>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF171D25),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Text(
                'Previous landing areas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                'Reusing the pin does not confirm current access, permission or conditions.',
                style: TextStyle(color: Color(0xFFABB5C1)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final target in _recentLandingZones)
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(target.label),
                      subtitle: Text(
                        '${target.radiusMeters < 1000 ? '${target.radiusMeters.toInt()} m' : '${(target.radiusMeters / 1000).toStringAsFixed(1)} km'} radius',
                      ),
                      onTap: () => Navigator.of(context).pop(target),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) _applyLandingZone(selected);
  }

  Future<void> _showRideSheet(
    BuildContext context, {
    required bool creating,
    PendingInAppRoute? pendingInAppRoute,
  }) async {
    widget.controller.clearError();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF171D25),
      builder: (sheetContext) => _RideForm(
        controller: widget.controller,
        rideCodePreference: widget.rideCodePreference,
        riderProfile: widget.riderProfile,
        sharedRoutes: widget.sharedRoutes,
        planDirectory: widget.planDirectory,
        creating: creating,
        pendingInAppRoute: pendingInAppRoute,
        initialLandingZone: creating ? _landingTarget : null,
        onComplete: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  Future<void> _openRideLibrary(BuildContext launchContext) async {
    final library = StoredRouteLibrary(
      recordedRoutes: widget.recordedRoutes,
      completedRides: widget.completedRides,
    );
    final selection = await StoredRoutePickerScreen.show(
      launchContext,
      library: library,
      distanceUnit: widget.distanceUnits.value,
      openPreviousRideArchive: (libraryContext) => PreviousRidesScreen.show(
        libraryContext,
        widget.completedRides,
        widget.distanceUnits,
      ),
    );
    if (selection == null || !mounted) return;
    final prepared = library.prepare(selection);
    await _showRideSheet(
      context,
      creating: true,
      pendingInAppRoute: PendingInAppRoute(
        route: prepared.route,
        reviewNotes: prepared.notes,
      ),
    );
  }
}

class _RideRestorationBanner extends StatelessWidget {
  const _RideRestorationBanner({
    required this.rideCode,
    required this.error,
    required this.onRetry,
  });

  final String? rideCode;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    final ride = rideCode == null ? 'your saved flight' : 'flight $rideCode';
    return Container(
      key: const Key('ride-restoration-banner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2530),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: failed
              ? Theme.of(context).colorScheme.error
              : const Color(0xFF3B4654),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed)
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            )
          else
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failed ? 'Could not restore $ride' : 'Still restoring $ride',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  failed
                      ? 'The home screen remains available. Retry before '
                            'creating or joining another flight.'
                      : 'The home screen remains available while its journal '
                            'loads. Flight actions will unlock when it is ready.',
                ),
                if (failed) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('retry-ride-restoration'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry restore'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetAsideRideBanner extends StatelessWidget {
  const _SetAsideRideBanner({
    required this.rideCode,
    required this.running,
    required this.onReopen,
  });

  final String rideCode;
  final bool running;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('set-aside-ride-banner'),
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1D2530),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF3B4654)),
    ),
    child: Row(
      children: [
        const Icon(Icons.flag_outlined, color: Color(0xFFFFB15C)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                running
                    ? 'Flight $rideCode is still active'
                    : 'Flight $rideCode has ended',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                running
                    ? 'Location sharing is paused while this flight is set aside.'
                    : 'Its summary and replay are still here.',
                style: TextStyle(color: Color(0xFFABB5C1), fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          key: const Key('reopen-set-aside-ride'),
          onPressed: onReopen,
          child: Text(running ? 'Return' : 'Open'),
        ),
      ],
    ),
  );
}

/// A GPX file opened from another app (Files, Mail, a route planner's share
/// sheet) has nowhere to go yet - there is no ride to attach a route to until
/// one exists. Surfaces that instead of silently discarding it.
class _PendingSharedRouteBanner extends StatelessWidget {
  const _PendingSharedRouteBanner({
    required this.fileName,
    required this.onDismiss,
  });

  final String fileName;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1D2530),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF3B4654)),
    ),
    child: Row(
      children: [
        const Icon(Icons.map_outlined, color: Color(0xFFFFB15C)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'Start or join a flight, then reopen it to use this route.',
                style: TextStyle(color: Color(0xFFABB5C1), fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Dismiss',
          onPressed: onDismiss,
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    ),
  );
}

class _PlannerLinkStatusBanner extends StatelessWidget {
  const _PlannerLinkStatusBanner({
    required this.status,
    required this.message,
    required this.canRetry,
    required this.onRetry,
    required this.onDismiss,
  });

  final PlannerLinkStatus status;
  final String message;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('planner-link-status'),
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1D2530),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: status == PlannerLinkStatus.error
            ? const Color(0xFFD96A6A)
            : const Color(0xFF3B4654),
      ),
    ),
    child: Row(
      children: [
        if (status == PlannerLinkStatus.loading)
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          const Icon(Icons.link_off, color: Color(0xFFFFB15C)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFFD2D9E1), fontSize: 13),
          ),
        ),
        if (canRetry)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        if (status == PlannerLinkStatus.error)
          IconButton(
            tooltip: 'Dismiss route link message',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 20),
          ),
      ],
    ),
  );
}

class _RideForm extends StatefulWidget {
  const _RideForm({
    required this.controller,
    required this.rideCodePreference,
    required this.riderProfile,
    required this.sharedRoutes,
    required this.planDirectory,
    required this.creating,
    required this.onComplete,
    this.pendingInAppRoute,
    this.initialLandingZone,
  });

  final RideController controller;
  final RideCodePreferenceController rideCodePreference;
  final RiderProfileController riderProfile;
  final SharedRouteController sharedRoutes;
  final PlanDirectory? planDirectory;
  final bool creating;
  final VoidCallback onComplete;
  final PendingInAppRoute? pendingInAppRoute;
  final LandingZoneTarget? initialLandingZone;

  @override
  State<_RideForm> createState() => _RideFormState();
}

class _RideFormState extends State<_RideForm> with WidgetsBindingObserver {
  late final _nameController = TextEditingController(
    text: widget.riderProfile.displayName,
  );
  late final _codeController = TextEditingController(
    text: widget.creating ? null : widget.rideCodePreference.savedCode,
  );
  final _rideNameController = TextEditingController();
  final _planCodeController = TextEditingController();
  final _vehicleLabelController = TextEditingController(text: 'Land Rover');
  final _codeFocusNode = FocusNode();
  final _codeFieldKey = GlobalKey();
  RideCoordinationMode _selectedCoordinationMode =
      RideCoordinationMode.keepTogether;
  FlightRole _selectedJoinRole = FlightRole.chaseCrew;

  /// Set once a created ride's code needs sharing before handing off to the
  /// map - the moment a leader most needs it, with people waiting nearby.
  bool _showShareStep = false;
  bool _checkingPlanCode = false;
  String? _planCodeError;
  PickedGpxFile? _pendingPlanFile;
  ImportedRoute? _pendingStructuredPlan;

  /// Captured when pasted text includes a join token alongside the six
  /// digits - see [parseJoinInvite]. Typing the code by hand leaves this
  /// null, which still works but only via the rate-limited fallback.
  String? _pastedJoinToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _codeFocusNode.addListener(_keepCodeFieldVisible);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeFocusNode.removeListener(_keepCodeFieldVisible);
    _codeFocusNode.dispose();
    _nameController.dispose();
    _codeController.dispose();
    _rideNameController.dispose();
    _planCodeController.dispose();
    _vehicleLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showShareStep) {
      return _ShareCodeStep(
        controller: widget.controller,
        onContinue: _finishCreating,
      );
    }
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.rideCodePreference,
      ]),
      builder: (context, _) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          key: const Key('ride-form-scroll-view'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.creating ? 'Create a private flight' : 'Join the crew',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                widget.creating
                    ? 'You will become the pilot and get a six-digit code to share.'
                    : 'Choose your job, then enter the six-digit code shared by the pilot. You need a connection once to join, then the app keeps using the secure relay.',
                style: const TextStyle(color: Color(0xFFABB5C1)),
              ),
              const SizedBox(height: 24),
              if (widget.creating) ...[
                Text(
                  'Who is taking part?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  key: const Key('ride-scope-selector'),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.person_outline),
                      label: Text('Solo'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.groups_2_outlined),
                      label: Text('Group'),
                    ),
                  ],
                  selected: {_selectedCoordinationMode.isGroup},
                  onSelectionChanged: (selection) => setState(() {
                    _selectedCoordinationMode = selection.first
                        ? RideCoordinationMode.keepTogether
                        : RideCoordinationMode.solo;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedCoordinationMode.description,
                  style: const TextStyle(
                    color: Color(0xFFABB5C1),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rideNameController,
                  maxLength: 32,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Flight name (optional)',
                    hintText: 'e.g. Bath evening flight',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('planned-route-code-field'),
                  controller: _planCodeController,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  maxLength: 16,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(16),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Forecast plan code (optional)',
                    hintText: 'e.g. 7F3K9QRT',
                    helperText:
                        'From the web planner. The forecast opens for review after the flight is created.',
                    errorText: _planCodeError,
                    counterText: '',
                    suffixIcon: const Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!widget.creating) ...[
                Text(
                  'Your role in this flight',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('join-role-balloon-crew'),
                      selected: _selectedJoinRole == FlightRole.balloonCrew,
                      avatar: const Icon(Icons.air, size: 18),
                      label: const Text('Balloon crew'),
                      onSelected: (_) => setState(
                        () => _selectedJoinRole = FlightRole.balloonCrew,
                      ),
                    ),
                    ChoiceChip(
                      key: const Key('join-role-chase-driver'),
                      selected: _selectedJoinRole == FlightRole.chaseDriver,
                      avatar: const Icon(Icons.directions_car, size: 18),
                      label: const Text('Driver'),
                      onSelected: (_) => setState(
                        () => _selectedJoinRole = FlightRole.chaseDriver,
                      ),
                    ),
                    ChoiceChip(
                      key: const Key('join-role-chase-crew'),
                      selected: _selectedJoinRole == FlightRole.chaseCrew,
                      avatar: const Icon(Icons.groups_2_outlined, size: 18),
                      label: const Text('Chase crew'),
                      onSelected: (_) => setState(
                        () => _selectedJoinRole = FlightRole.chaseCrew,
                      ),
                    ),
                  ],
                ),
                if (_selectedJoinRole.isChasing) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('join-vehicle-label-field'),
                    controller: _vehicleLabelController,
                    maxLength: 32,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Chase vehicle',
                      helperText:
                          'Use the same name as crewmates in this vehicle.',
                      hintText: 'e.g. Land Rover',
                      counterText: '',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
              TextField(
                key: const Key('rider-name-field'),
                controller: _nameController,
                autofocus: true,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Crew name',
                  hintText: 'How the crew will recognise you',
                  counterText: '',
                ),
              ),
              if (!widget.creating) ...[
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _codeFieldKey,
                  child: TextField(
                    key: const Key('ride-code-field'),
                    controller: _codeController,
                    focusNode: _codeFocusNode,
                    scrollPadding: const EdgeInsets.only(bottom: 112),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!widget.controller.busy) _submit();
                    },
                    autocorrect: false,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Six-digit flight code',
                      hintText: '123456',
                      helperText: widget.rideCodePreference.savedCode == null
                          ? null
                          : 'Saved from your last successful join',
                      counterText: '',
                      // Scanning sits beside pasting rather than replacing it.
                      // A camera is the only join path that works with no signal
                      // (#279), and must never become the only path at all.
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const Key('scan-invitation-button'),
                            tooltip: 'Scan an invitation code',
                            onPressed: _scanInvitation,
                            icon: const Icon(Icons.qr_code_scanner),
                          ),
                          IconButton(
                            tooltip: 'Paste flight code',
                            onPressed: _pasteRideCode,
                            icon: const Icon(Icons.content_paste),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // The same action as the camera icon in the field above, said
                // out loud.
                //
                // #279 shipped QR joining and #306 found it had not been
                // delivered: the owner concluded it was missing entirely,
                // because the only affordance was an unlabelled icon and a
                // tooltip, and a tooltip does not appear when you tap a phone.
                // The icon stays for riders who have learned it; this is the
                // one a rider who has never seen the app can read.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('scan-invitation-labelled-button'),
                    onPressed: _scanInvitation,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan an invitation code'),
                  ),
                ),
                CheckboxListTile(
                  key: const Key('keep-ride-code'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: widget.rideCodePreference.keepCode,
                  onChanged: (value) {
                    if (value != null) {
                      widget.rideCodePreference.setKeepCode(value);
                    }
                  },
                  title: const Text('Keep this code for next time'),
                  subtitle: const Text(
                    'Only the six-digit code is saved. Invitation secrets are not.',
                  ),
                ),
                if (widget.rideCodePreference.savedCode != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('forget-saved-ride-code'),
                      onPressed: _forgetSavedCode,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Forget saved code'),
                    ),
                  ),
              ],
              if (widget.controller.errorMessage case final String message) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                // A connection or service failure is worth another go, and there
                // was nothing to press: the rider read a sentence about a relay
                // handshake and had to guess (#208).
                if (widget.controller.errorIsRetryable)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('retry-ride-submit'),
                      onPressed: widget.controller.busy || _checkingPlanCode
                          ? null
                          : () {
                              widget.controller.clearError();
                              unawaited(_submit());
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: widget.controller.busy || _checkingPlanCode
                    ? null
                    : _submit,
                child: widget.controller.busy || _checkingPlanCode
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.creating
                            ? 'Create private flight'
                            : 'Join flight',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text;
    if (widget.creating) {
      final code = _planCodeController.text.trim();
      _pendingPlanFile = null;
      _pendingStructuredPlan = null;
      if (code.isNotEmpty) {
        setState(() {
          _checkingPlanCode = true;
          _planCodeError = null;
        });
        final ownedDirectory = widget.planDirectory == null
            ? HttpPlanDirectory.fromEnvironment()
            : null;
        try {
          final plan = await (widget.planDirectory ?? ownedDirectory!).fetch(
            code,
          );
          final structured = plan.forecastPlan;
          if (structured == null) {
            _pendingPlanFile = PickedGpxFile(
              name: '${plan.name ?? 'planned-route'}.gpx',
              bytes: Uint8List.fromList(utf8.encode(plan.gpx)),
            );
          } else {
            _pendingStructuredPlan = const ForecastPlanImporter().import(
              structured,
              importedAt: DateTime.now(),
              sourceFileName: '${plan.name ?? 'planned-route'}.forecast-plan',
            );
          }
        } on PlanDirectoryException catch (error) {
          if (mounted) setState(() => _planCodeError = error.message);
          return;
        } on Object {
          if (mounted) {
            setState(
              () => _planCodeError =
                  'The forecast plan could not be loaded. Check your connection and try again.',
            );
          }
          return;
        } finally {
          ownedDirectory?.close();
          if (mounted) setState(() => _checkingPlanCode = false);
        }
      }
      await widget.controller.createRide(
        name,
        motorcycleStyle: widget.riderProfile.motorcycleStyle,
        riderSymbol: widget.riderProfile.riderSymbol,
        riderColor: widget.riderProfile.riderColor,
        coordinationMode: _selectedCoordinationMode,
        rideName: _rideNameController.text,
      );
      if (widget.controller.hasActiveRide) {
        final target = widget.initialLandingZone;
        if (target != null) await widget.controller.setLandingZone(target);
      }
    } else {
      final code = _codeController.text.trim();
      await widget.controller.joinRide(
        code,
        name,
        flightRole: _selectedJoinRole,
        vehicleLabel: _vehicleLabelController.text,
        motorcycleStyle: widget.riderProfile.motorcycleStyle,
        riderSymbol: widget.riderProfile.riderSymbol,
        riderColor: widget.riderProfile.riderColor,
        joinToken: _pastedJoinToken,
      );
      if (widget.controller.hasActiveRide) {
        await widget.rideCodePreference.rememberSuccessfulJoin(code);
      } else if (widget.controller.errorMessage?.startsWith(
            'That flight code is not active.',
          ) ??
          false) {
        await widget.rideCodePreference.clearIfInactive(code);
      }
    }
    if (widget.controller.hasActiveRide && mounted) {
      await widget.riderProfile.save(
        displayName: name.trim(),
        motorcycleStyle: widget.riderProfile.motorcycleStyle,
        riderSymbol: widget.riderProfile.riderSymbol,
        riderColor: widget.riderProfile.riderColor,
      );
      if (widget.creating) {
        if (_selectedCoordinationMode.isGroup) {
          setState(() => _showShareStep = true);
        } else {
          _finishCreating();
        }
      } else {
        widget.onComplete();
      }
    }
  }

  void _finishCreating() {
    if (_pendingStructuredPlan case final route?) {
      widget.sharedRoutes.stagePendingInAppRoute(route);
      _pendingStructuredPlan = null;
    } else if (_pendingPlanFile case final file?) {
      widget.sharedRoutes.stagePending(file);
      _pendingPlanFile = null;
    } else if (widget.pendingInAppRoute case final route?) {
      widget.sharedRoutes.stagePendingInAppRoute(
        route.route,
        reviewNotes: route.reviewNotes,
      );
    }
    widget.onComplete();
  }

  @override
  void didChangeMetrics() {
    if (!_codeFocusNode.hasFocus) return;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) _keepCodeFieldVisible();
    });
  }

  void _keepCodeFieldVisible() {
    if (!_codeFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldContext = _codeFieldKey.currentContext;
      if (!mounted || fieldContext == null) return;
      Scrollable.ensureVisible(
        fieldContext,
        alignment: 0.55,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _forgetSavedCode() async {
    final savedCode = widget.rideCodePreference.savedCode;
    await widget.rideCodePreference.clear();
    if (_codeController.text == savedCode) _codeController.clear();
  }

  /// Scans an invitation and joins from it, with no relay lookup (#279).
  ///
  /// The whole point is that this works with no signal, so it joins directly from
  /// the scanned credentials rather than filling in the code field and going
  /// through the online path - which would defeat it.
  Future<void> _scanInvitation() async {
    final invitation = await ScanInvitationScreen.show(context);
    if (invitation == null || !mounted) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      // Ask for the name rather than joining as nobody: the roster is how a group
      // finds each other.
      setState(() => _codeController.text = invitation.rideCode);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Add your crew name, then join.')),
      );
      return;
    }
    await widget.controller.joinRideFromInvitation(
      invitation,
      name,
      flightRole: _selectedJoinRole,
      vehicleLabel: _vehicleLabelController.text,
      motorcycleStyle: widget.riderProfile.motorcycleStyle,
      riderSymbol: widget.riderProfile.riderSymbol,
      riderColor: widget.riderProfile.riderColor,
    );
    if (!mounted) return;
    if (widget.controller.hasActiveRide) {
      await widget.rideCodePreference.rememberSuccessfulJoin(
        invitation.rideCode,
      );
    }
  }

  Future<void> _pasteRideCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    final invite = parseJoinInvite(text);
    final code = invite.code ?? text;
    _pastedJoinToken = invite.token;
    _codeController.text = code;
    _codeController.selection = TextSelection.collapsed(offset: code.length);
  }
}

/// Shown immediately after creating a ride - the moment a leader most needs
/// the code, with riders waiting nearby, rather than requiring a trip
/// through the active Ride page to find it.
class _ShareCodeStep extends StatelessWidget {
  const _ShareCodeStep({required this.controller, required this.onContinue});

  final RideController controller;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final code = session?.rideCode ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF6ED89A), size: 40),
          const SizedBox(height: 16),
          Text(
            session?.rideName ?? 'Flight created',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Share this code so the group can join.',
            style: TextStyle(color: Color(0xFFABB5C1)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF111720),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A3441)),
            ),
            child: Center(
              child: Text(
                code,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 34,
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: controller.rideCodeShareText,
                      subject: 'Join my Balloon Crumbs group',
                    ),
                  ),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          TextButton(
            onPressed: onContinue,
            child: const Text('Continue to flight'),
          ),
        ],
      ),
    );
  }
}

/// The notices area: compact cards on the map, and nothing at all when there is
/// nothing to say (#426).
///
/// The old home screen carried these in the scrolling column of a full-screen
/// panel, which is most of why the panel was full-screen. They still need a home —
/// a restoration failure, a set-aside ride, a pending shared route and a planner
/// link all matter — but not one that reserves space when empty.
///
/// Scrollable because several can be live at once and the map must not be pushed
/// off the screen by a stack of them.
class _HomeNotices extends StatelessWidget {
  const _HomeNotices({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final visible = children.where((child) => child is! SizedBox).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      // A third of the screen at most. A notice is worth interrupting the map
      // for; four notices are not worth losing it.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height / 3,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in visible)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: child),
          ],
        ),
      ),
    );
  }
}
