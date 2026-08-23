import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/chase_vehicle_controller.dart';
import '../../domain/chase_vehicle.dart';
import '../../controllers/distance_unit_controller.dart';
import '../../controllers/foreground_location_controller.dart';
import '../../controllers/internet_relay_controller.dart';
import '../../controllers/map_style_mode_controller.dart';
import '../../controllers/nearby_relay_controller.dart';
import '../../controllers/observer_access_controller.dart';
import '../../controllers/pre_start_presence_controller.dart';
import '../../controllers/ride_controller.dart';
import '../../controllers/route_progress_display_controller.dart';
import '../../controllers/ride_push_notification_controller.dart';
import '../../controllers/ride_simulation_controller.dart';
import '../../controllers/rider_profile_controller.dart';
import '../../controllers/shared_route_controller.dart';
import '../../controllers/spoken_guidance_controller.dart';
import '../../controllers/speed_limit_display_controller.dart';
import '../../controllers/test_control_controller.dart';
import '../../controllers/situational_awareness_controller.dart';
import '../../data/in_memory_event_store.dart';
import '../../data/json_file_route_store.dart';
import '../../data/secure_observer_grant_store.dart';
import '../../domain/event_store.dart';
import '../../domain/completed_ride_store.dart';
import '../../domain/flight_replay.dart';
import '../../domain/flight_role.dart';
import '../../domain/geo_point.dart' as awareness_geo;
import '../../domain/hazard.dart';
import '../../domain/imported_route.dart' as route_domain;
import '../../domain/landing_zone.dart';
import '../../domain/live_route_state.dart';
import '../../domain/operational_boundary.dart';
import '../../domain/map_style_mode.dart';
import '../../domain/quick_message.dart';
import '../../domain/ride_coordination_mode.dart';
import '../../domain/ride_event.dart';
import '../../domain/ride_role.dart';
import '../../domain/ride_session.dart';
import '../../domain/rider_location.dart';
import '../../domain/rider_color.dart';
import '../../domain/route_store.dart';
import '../../internet/internet_relay_client.dart';
import '../../internet/internet_relay_worker.dart';
import '../../internet/observer_access_client.dart';
import '../../internet/push_registration_client.dart';
import '../../internet/shared_preferences_internet_cursor_store.dart';
import '../../relay/live_presence.dart';
import '../../relay/native_nearby_transport.dart';
import '../../relay/relay_engine.dart';
import '../../relay/sqlite_relay_queue.dart';
import '../../services/carplay_bridge.dart';
import '../../services/chase_guidance_target.dart';
import '../../services/fiesta_flight_loader.dart';
import '../../services/geo_calculations.dart';
import '../../services/spoken_audio_mode.dart';
import '../../services/spoken_guidance_schedule.dart';
import '../../services/spoken_guidance.dart';
import '../../services/test_control_registry.dart';
import '../../services/basemap_configuration.dart';
import '../../services/device_location_source.dart';
import '../../services/external_hazard_provider.dart';
import '../../services/fixed_speed_camera_catalogue.dart';
import '../../services/fixed_speed_camera_provider.dart';
import '../../services/gpx_import_source.dart';
import '../../services/measurement_formatter.dart';
import '../../services/native_push_token_source.dart';
import '../../services/open_meteo_wind.dart';
import '../../services/operational_boundary_monitor.dart';
import '../../services/position_report_policy.dart';
import '../../services/received_quick_message.dart';
import '../../services/navigation_guidance.dart';
import '../../services/ride_completion_detector.dart';
import '../../services/route_progress.dart';
import '../../services/route_journey_progress.dart';
import '../../services/ride_membership.dart';
import '../../services/ride_screen_awake.dart';
import '../../controllers/ride_diagnostics_controller.dart';
import '../../services/ride_diagnostics_log_writer.dart';
import '../../services/ride_diagnostics_recorder.dart';
import '../../services/ride_diagnostics_transition.dart';
import '../../services/ride_summary_exporter.dart';
import '../../services/enforcement_alert_detector.dart';
import '../../services/hazard_map_relevance.dart';
import '../../services/relay_traffic_hazard_provider.dart';
import '../../services/relay_traffic_reroute_provider.dart';
import '../../services/rider_contact_share.dart';
import '../../services/road_routing.dart';
import '../../services/ride_connectivity_summary.dart';
import '../../services/trail_display_simplifier.dart';
import '../map/hazard_map_symbol.dart';
import '../map/maneuver_diagnostics.dart';
import '../map/maneuver_list_screen.dart';
import '../map/craft_icon.dart';
import '../map/ride_map.dart';
import '../map/route_confirmation_sheet.dart';
import '../settings/emergency_info_sheet.dart';
import '../settings/notification_preferences_sheet.dart';
import '../settings/unit_settings_sheet.dart';
import 'ice_share_inbox_sheet.dart';
import '../situational_awareness/situational_awareness_screen.dart';
import '../simulation/ride_simulation_screen.dart';
import 'end_ride_confirmation.dart';
import 'ended_ride_screen.dart';
import 'observer_access_sheet.dart';
import 'ride_dashboard.dart';
import 'ride_roster_sheet.dart';

/// Whether a newly calculated route should wait before replacing the current
/// junction instruction.
///
/// The only thing an observer link publishes.
///
/// Its argument list is the privacy boundary: an observer is a separate
/// authorisation decision (#36), so nothing that a rider shared *inside* the
/// ride is an input here. That covers the ICE contact, a rejoin breadcrumb
/// (#128) and a rider's own phone number (#188) — none of them has a parameter
/// to populate, by accident or otherwise.
@visibleForTesting
ObserverPublishedSnapshot buildLocalObserverSnapshot({
  required RideSession session,
  required DateTime snapshotGeneratedAt,
  required String rideStatus,
  required DateTime statusUpdatedAt,
  required DateTime assistanceUpdatedAt,
  required LocationSample? localLocation,
  required ObserverPublishedAssistance? assistance,
}) {
  return ObserverPublishedSnapshot(
    subjectName: session.displayName,
    snapshotGeneratedAt: snapshotGeneratedAt,
    rideStatus: rideStatus,
    statusUpdatedAt: statusUpdatedAt,
    assistanceUpdatedAt: assistanceUpdatedAt,
    position: localLocation == null
        ? null
        : ObserverPublishedPosition(
            latitude: localLocation.position.latitude,
            longitude: localLocation.position.longitude,
            accuracyMeters: localLocation.accuracyMeters,
            recordedAt: localLocation.recordedAt,
          ),
    assistance: assistance,
  );
}

/// The leader-published, bounded whole-group watcher snapshot.
///
/// This deliberately accepts only the reconciled live roster, current rendered
/// positions and planned route. Durable events, trails, nearby identifiers,
/// contact/ICE state and ride credentials are not inputs, so they cannot leak
/// into a watcher response by accident.
@visibleForTesting
ObserverPublishedSnapshot buildGroupObserverSnapshot({
  required RideSession session,
  required DateTime snapshotGeneratedAt,
  required String rideStatus,
  required DateTime statusUpdatedAt,
  required DateTime assistanceUpdatedAt,
  required Iterable<RideParticipant> liveParticipants,
  required Iterable<RiderLocation> renderedPositions,
  required LocationSample? localLocation,
  required route_domain.ImportedRoute? route,
}) {
  final positionsByRider = {
    for (final location in renderedPositions) location.riderId: location.sample,
  };
  if (localLocation != null) {
    positionsByRider[session.localRiderId] = localLocation;
  }
  final participants = liveParticipants
      .take(50)
      .map((participant) {
        final sample = positionsByRider[participant.riderId];
        final color = participant.riderColor.color
            .toARGB32()
            .toRadixString(16)
            .padLeft(8, '0')
            .substring(2)
            .toUpperCase();
        return ObserverPublishedGroupParticipant(
          displayName: _boundedObserverText(participant.displayName, 80),
          role: participant.role.name,
          color: '#$color',
          position: sample == null
              ? null
              : ObserverPublishedPosition(
                  latitude: sample.position.latitude,
                  longitude: sample.position.longitude,
                  accuracyMeters: sample.accuracyMeters,
                  recordedAt: sample.recordedAt,
                ),
        );
      })
      .toList(growable: false);
  final routePoints = _boundedObserverRoutePoints(route);
  return ObserverPublishedSnapshot(
    scope: ObserverAccessScope.group,
    subjectName: _boundedObserverText(
      session.rideName ?? 'Flight coordinated by ${session.displayName}',
      80,
    ),
    snapshotGeneratedAt: snapshotGeneratedAt,
    rideStatus: rideStatus,
    statusUpdatedAt: statusUpdatedAt,
    assistanceUpdatedAt: assistanceUpdatedAt,
    participants: participants,
    route: route == null || routePoints.length < 2
        ? null
        : ObserverPublishedRoute(
            name: _boundedObserverText(route.name, 80),
            points: routePoints,
          ),
  );
}

String _boundedObserverText(String value, int maximumLength) {
  final trimmed = value.trim();
  if (trimmed.length <= maximumLength) return trimmed;
  return trimmed.substring(0, maximumLength);
}

List<ObserverPublishedRoutePoint> _boundedObserverRoutePoints(
  route_domain.ImportedRoute? route, {
  int maximum = 500,
}) {
  if (route == null || maximum < 2) return const [];
  final source = [
    for (final path in route.paths)
      for (final point in path.points) point,
    if (route.paths.isEmpty)
      for (final waypoint in route.waypoints) waypoint.point,
  ];
  if (source.length < 2) return const [];
  final indexes = source.length <= maximum
      ? List<int>.generate(source.length, (index) => index)
      : List<int>.generate(
          maximum,
          (index) => (index * (source.length - 1) / (maximum - 1)).round(),
        );
  return List.unmodifiable([
    for (final index in indexes)
      ObserverPublishedRoutePoint(
        latitude: source[index].latitude,
        longitude: source[index].longitude,
      ),
  ]);
}

/// Owns the active-ride feature lifecycle and keeps each feature independently
/// testable. Native permissions are requested only by the installed app, not by
/// widget tests that construct [BalloonCrumbsApp].
class ActiveRideShell extends StatefulWidget {
  const ActiveRideShell({
    super.key,
    required this.rideController,
    required this.distanceUnits,
    required this.mapStyleMode,
    required this.eventStore,
    required this.enableNativeServices,
    required this.riderProfile,
    required this.sharedRoutes,
    required this.speedLimitDisplay,
    this.chaseVehicle,
    this.routeProgressDisplay,
    this.completedRideStore,
    this.screenWakeLock = const WakelockPlusScreenWakeLock(),
    this.screenWakeReassertInterval = const Duration(seconds: 15),
    this.pushTokenSource,
    this.pushRegistrationApi,
    this.testControl,
    this.testControlRegistry,
    this.spokenGuidance,
    this.rideDiagnostics,
    this.onJoinGroupRequested,
  });

  final RideController rideController;

  /// Both null unless this build carries the test-control define. The shell
  /// forwards [testControl] to the settings sheet and publishes each
  /// situational-awareness controller it creates into [testControlRegistry], so
  /// the driven surface always talks to the live one.
  final TestControlController? testControl;
  final TestControlRegistry? testControlRegistry;

  /// Whether turn instructions are spoken. Null in surfaces that do not offer it,
  /// which is treated as off (#286).
  final SpokenGuidanceController? spokenGuidance;

  /// Records what the app said beside what the bike did (#419). Null, or off,
  /// in every ordinary build.
  final RideDiagnosticsController? rideDiagnostics;

  /// Returns an unstarted solo rider to the established group-join sheet.
  /// The shell owns leaving because it must stop its ride-scoped services first;
  /// the app owns opening Home's sheet after this shell has been removed (#261).
  final VoidCallback? onJoinGroupRequested;

  final DistanceUnitController distanceUnits;
  final MapStyleModeController mapStyleMode;
  final EventStore eventStore;
  final bool enableNativeServices;
  final RiderProfileController riderProfile;
  final SharedRouteController sharedRoutes;
  final SpeedLimitDisplayController speedLimitDisplay;
  final ChaseVehicleController? chaseVehicle;
  final RouteProgressDisplayController? routeProgressDisplay;
  final CompletedRideStore? completedRideStore;
  final ScreenWakeLock screenWakeLock;
  final Duration screenWakeReassertInterval;
  final PushTokenSource? pushTokenSource;
  final PushRegistrationApi? pushRegistrationApi;

  /// Drives the end-of-ride catalogued-road rating card (#159). Null in a build
  /// with no catalogue service configured, and the card is then never built.

  @override
  State<ActiveRideShell> createState() => _ActiveRideShellState();
}

/// Prevents an active ride from mounting the map against its legacy global
/// fallback while the ride-scoped route store is still opening.
///
/// Returning only the store for the current ride type also ensures a genuinely
/// new ride cannot inherit another ride's selected route.
@visibleForTesting
RouteStore? activeRideMapStoreWhenReady({
  required bool initializing,
  required bool isSimulation,
  required RouteStore? rideRouteStore,
  required RouteStore? simulationRouteStore,
}) {
  if (initializing) return null;
  return isSimulation ? simulationRouteStore : rideRouteStore;
}

/// What the ride map should present of the quick messages in the journal, and
/// the most urgent one per sender so their marker can say what they raised.
///
/// [ReceivedQuickMessageReducer] decides what is admissible; this decides what
/// is still *this rider's* to act on, and works out where each sender is:
///
/// * another rider's message stays until this phone acknowledges it, so a rider
///   who glances away cannot lose it;
/// * this rider's own message appears only once somebody has acknowledged it,
///   as a receipt — nobody needs their own alert read back to them;
/// * the sender's **live** fix is preferred, because where they are now is what
///   a leader turning round needs, falling back to the fix relayed with the
///   message. A rider stopped for fuel is not moving, and their location events
///   age out of the 30-minute retention band long before the two-hour message
///   does, so the relayed fix is what outlasts them.
///
/// Extracted so the decision a two-device test exercises is testable without
/// two devices (#151).
@visibleForTesting
({
  List<RideQuickMessageAlert> alerts,
  Map<String, ReceivedQuickMessage> bySender,
})
presentableQuickMessageAlerts({
  required Iterable<ReceivedQuickMessage> messages,
  required String localRiderId,
  required awareness_geo.GeoPoint? readerPosition,
  Map<String, awareness_geo.GeoPoint> livePositions = const {},
  List<awareness_geo.GeoPoint> route = const [],
}) {
  final alerts = <RideQuickMessageAlert>[];
  final bySender = <String, ReceivedQuickMessage>{};
  // The same rider saying the same thing again is one fact, not another prompt.
  // Keyed by sender and the label the rider actually reads, so someone who
  // raises `Stopped` three times is acknowledged once (#178), a `Stopped` and a
  // `Mechanical` from them stay separate because those are two things to know,
  // and a kind this build has never heard of still groups by its own words.
  final repeatsOfIndex = <({String senderRiderId, String label}), int>{};
  for (final message in messages) {
    if (message.raisedFromLocalRider) {
      if (!message.isAcknowledged) continue;
    } else {
      if (message.acknowledgedBy(localRiderId)) continue;
      bySender.putIfAbsent(message.senderRiderId, () => message);
      final key = (senderRiderId: message.senderRiderId, label: message.label);
      final existing = repeatsOfIndex[key];
      if (existing != null) {
        final kept = alerts[existing];
        alerts[existing] = RideQuickMessageAlert(
          message: kept.message,
          origin: kept.origin,
          repeats: [...kept.repeats, message],
        );
        continue;
      }
      repeatsOfIndex[key] = alerts.length;
    }
    final live = livePositions[message.senderRiderId];
    alerts.add(
      RideQuickMessageAlert(
        message: message,
        origin: QuickMessageOrigin.between(
          readerPosition: readerPosition,
          senderPosition: live ?? message.raisedAtPosition,
          route: route,
          positionIsLive: live != null,
        ),
      ),
    );
  }
  return (
    alerts: List.unmodifiable(alerts),
    bySender: Map.unmodifiable(bySender),
  );
}

/// The labelled action surface embedded directly in the Ride destination.
///
/// These actions used to sit behind a hamburger on both the map and dashboard.
/// Keeping them on the page means there is no second navigation system to
/// discover, while the moving map keeps only its large riding-time controls.
class _RideActionsPanel extends StatelessWidget {
  const _RideActionsPanel({
    required this.canChangeRoute,
    required this.onAlertsAndReports,
    required this.onShareSummary,
    required this.onOpenRoster,
    required this.onShareRoster,
    required this.onChangeRoute,
    required this.canChangeLandingZone,
    required this.landingZoneLabel,
    required this.onChangeLandingZone,
    required this.boundaryCount,
    required this.canEditBoundaries,
    required this.onOperationalBoundaries,
    required this.canChooseChaseGuidance,
    required this.chaseGuidanceLabel,
    required this.onChooseChaseGuidance,
    required this.maneuverCount,
    required this.onShowManeuvers,
    required this.onEmergencyInfo,
    required this.onNotifications,
    required this.canManageObserverAccess,
    required this.onObserverAccess,
    required this.canShareIceInfo,
    required this.onShareIceInfo,
    required this.receivedIceShareCount,
    required this.onViewIceShares,
    required this.hasOwnPhoneNumber,
    required this.ownPhoneNumberShared,
    required this.ownPhoneNumberRecipientLabel,
    required this.onShareOwnPhoneNumber,
    required this.ridePaused,
    required this.canToggleRidePause,
    required this.onToggleRidePause,
    required this.onLeaveOrEndRide,
    required this.coordinationMode,
  });

  final bool canChangeRoute;
  final VoidCallback onAlertsAndReports;
  final VoidCallback onShareSummary;
  final VoidCallback onOpenRoster;
  final VoidCallback onShareRoster;
  final VoidCallback onChangeRoute;
  final bool canChangeLandingZone;
  final String? landingZoneLabel;
  final VoidCallback onChangeLandingZone;
  final int boundaryCount;
  final bool canEditBoundaries;
  final VoidCallback onOperationalBoundaries;
  final bool canChooseChaseGuidance;
  final String? chaseGuidanceLabel;
  final VoidCallback onChooseChaseGuidance;
  final int maneuverCount;
  final VoidCallback onShowManeuvers;
  final VoidCallback onEmergencyInfo;
  final VoidCallback onNotifications;
  final bool canManageObserverAccess;
  final VoidCallback onObserverAccess;
  final bool canShareIceInfo;
  final VoidCallback onShareIceInfo;
  final int receivedIceShareCount;
  final VoidCallback onViewIceShares;

  /// #188. The tile is always shown, because "you have not added a number" is
  /// worth saying: a rider who never sees the control cannot know the option
  /// exists, and the emergency sheet's silence would look like a fault.
  final bool hasOwnPhoneNumber;
  final bool ownPhoneNumberShared;
  final String ownPhoneNumberRecipientLabel;
  final VoidCallback onShareOwnPhoneNumber;
  final bool ridePaused;
  final bool canToggleRidePause;
  final VoidCallback onToggleRidePause;
  final VoidCallback onLeaveOrEndRide;

  /// Whether this ride has anyone else in it. A solo ride is still led by the
  /// rider, so every surface that branches on "am I the leader" says group
  /// things to somebody riding alone unless it is told otherwise (#362).
  final RideCoordinationMode coordinationMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Flight actions',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Route, crew, sharing and flight controls are all on this page.',
            style: TextStyle(color: Color(0xFF98A3B1)),
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const Key('ride-actions-alerts'),
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('Alerts and reports'),
            subtitle: const Text('Road alerts and traffic alternatives'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onAlertsAndReports,
          ),
          ListTile(
            key: const Key('ride-actions-share-summary'),
            leading: const Icon(Icons.summarize_outlined),
            title: const Text('Share flight summary'),
            subtitle: const Text('Current flight details and recorded route'),
            onTap: onShareSummary,
          ),
          const Divider(height: 20),
          if (maneuverCount > 0)
            ListTile(
              key: const Key('ride-menu-maneuvers'),
              leading: const Icon(Icons.list_alt),
              title: const Text('All turns'),
              subtitle: Text(
                '$maneuverCount instruction${maneuverCount == 1 ? '' : 's'} '
                'for this route',
              ),
              onTap: onShowManeuvers,
            ),
          ListTile(
            key: const Key('ride-menu-open-roster'),
            leading: const Icon(Icons.groups_2_outlined),
            title: const Text('Flight crew'),
            subtitle: const Text('Presence, freshness and relay evidence'),
            onTap: onOpenRoster,
          ),
          if (canChangeRoute)
            ListTile(
              key: const Key('ride-menu-change-route'),
              leading: const Icon(Icons.edit_road_outlined),
              title: const Text('Change route'),
              subtitle: const Text(
                'Plan a destination, import a GPX file, or load the demo route',
              ),
              onTap: onChangeRoute,
            ),
          if (canChangeLandingZone)
            ListTile(
              key: const Key('flight-menu-change-landing-zone'),
              leading: const Icon(Icons.flag_outlined),
              title: Text(
                landingZoneLabel == null
                    ? 'Set intended landing area'
                    : 'Update intended landing area',
              ),
              subtitle: Text(
                landingZoneLabel ??
                    'Choose an approximate area and radius on the map',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: onChangeLandingZone,
            ),
          ListTile(
            key: const Key('flight-menu-operational-boundaries'),
            leading: const Icon(Icons.polyline_outlined),
            title: const Text('Boundaries and altitude alerts'),
            subtitle: Text(
              boundaryCount == 0
                  ? canEditBoundaries
                        ? 'Add advisory lines, areas or high/low altitude limits'
                        : 'No advisory boundaries have been shared by the pilot'
                  : '$boundaryCount shared advisor${boundaryCount == 1 ? 'y' : 'ies'} · alerts on this device',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOperationalBoundaries,
          ),
          if (canChooseChaseGuidance)
            ListTile(
              key: const Key('flight-menu-chase-guidance-target'),
              leading: const Icon(Icons.assistant_direction_outlined),
              title: const Text('Chase guidance target'),
              subtitle: Text(
                chaseGuidanceLabel ??
                    'Choose the landing area or a road rendezvous near the balloon',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onChooseChaseGuidance,
            ),
          if (canManageObserverAccess)
            ListTile(
              key: const Key('ride-menu-observer-access'),
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Share watcher link'),
              subtitle: const Text(
                'Private, read-only web view for a trusted contact',
              ),
              onTap: onObserverAccess,
            ),
          ExpansionTile(
            key: const Key('ride-more-options'),
            leading: const Icon(Icons.more_horiz),
            title: const Text('Contacts and other sharing'),
            subtitle: const Text('Less common flight setup'),
            children: [
              ListTile(
                key: const Key('ride-menu-share-roster'),
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Share crew list'),
                subtitle: const Text(
                  'Names and roles, to paste into a group chat you create',
                ),
                onTap: onShareRoster,
              ),
              ListTile(
                key: const Key('ride-menu-emergency-info'),
                leading: const Icon(Icons.medical_information_outlined),
                title: const Text('Emergency info'),
                subtitle: const Text('Edit your details and sharing settings'),
                onTap: onEmergencyInfo,
              ),
              ListTile(
                key: const Key('ride-menu-notifications'),
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Flight notifications'),
                subtitle: const Text(
                  'Background alert permission and preferences',
                ),
                onTap: onNotifications,
              ),
              if (canShareIceInfo)
                ListTile(
                  key: const Key('ride-menu-share-ice-info'),
                  leading: const Icon(Icons.contact_emergency_outlined),
                  title: const Text('Share my emergency contact'),
                  subtitle: const Text('Shares it with the whole group, now'),
                  onTap: onShareIceInfo,
                ),
              ListTile(
                key: const Key('ride-menu-share-own-number'),
                leading: const Icon(Icons.phone_forwarded_outlined),
                title: Text(
                  ownPhoneNumberShared
                      ? 'Your number is shared'
                      : 'Share my phone number',
                ),
                subtitle: Text(
                  !hasOwnPhoneNumber
                      ? 'Optional. Add your number first, so they can ring you '
                            'if you stop'
                      : ownPhoneNumberShared
                      ? 'Sent to $ownPhoneNumberRecipientLabel for this flight. '
                            'Cleared when the flight ends'
                      : 'Gives it to $ownPhoneNumberRecipientLabel for this '
                            'flight only',
                ),
                onTap: onShareOwnPhoneNumber,
              ),
              ListTile(
                key: const Key('ride-menu-view-ice-shares'),
                leading: Badge(
                  isLabelVisible: receivedIceShareCount > 0,
                  label: Text('$receivedIceShareCount'),
                  child: const Icon(Icons.contacts_outlined),
                ),
                title: const Text('Shared emergency contacts'),
                subtitle: const Text('From other crew, for this flight only'),
                onTap: onViewIceShares,
              ),
            ],
          ),
          if (canToggleRidePause) const Divider(height: 20),
          if (canToggleRidePause)
            ListTile(
              key: const Key('ride-menu-toggle-pause'),
              leading: Icon(ridePaused ? Icons.play_arrow : Icons.pause),
              title: Text(ridePaused ? 'Resume flight' : 'Pause flight'),
              subtitle: Text(
                coordinationMode.isGroup
                    ? 'Pauses tracking and progress for the whole group'
                    : 'Pauses tracking and progress',
              ),
              onTap: onToggleRidePause,
            ),
          ListTile(
            key: const Key('ride-actions-leave-or-end'),
            leading: const Icon(Icons.logout),
            title: Text(
              coordinationMode.isGroup ? 'Leave or end flight' : 'End flight',
            ),
            subtitle: Text(
              coordinationMode.isGroup
                  ? 'Coordinators can end it for everyone; other crew leave alone'
                  : 'Ends your flight and stops recording',
            ),
            onTap: onLeaveOrEndRide,
          ),
        ],
      ),
    );
  }
}

class _PreStartRidePanel extends StatelessWidget {
  const _PreStartRidePanel({
    required this.rideCode,
    required this.participants,
    required this.coordinationMode,
    required this.isLeader,
    required this.busy,
    required this.routeName,
    required this.onStartRide,
    required this.onChooseRoute,
    this.onJoinGroup,
  });

  final String rideCode;
  final List<RideParticipant> participants;
  final RideCoordinationMode coordinationMode;
  final bool isLeader;
  final bool busy;
  final String? routeName;
  final VoidCallback onStartRide;
  final VoidCallback onChooseRoute;
  final VoidCallback? onJoinGroup;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF17212B),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  coordinationMode == RideCoordinationMode.solo
                      ? Icons.person_outline
                      : Icons.groups_outlined,
                  color: const Color(0xFFFFC857),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        coordinationMode == RideCoordinationMode.solo
                            ? 'Ready for solo flight'
                            : 'Waiting to start',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        coordinationMode == RideCoordinationMode.solo
                            ? 'Tracking begins when you start'
                            : 'Flight $rideCode · Current positions only until the coordinator starts',
                        style: const TextStyle(
                          color: Color(0xFFA9B4C2),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLeader)
                  const Text(
                    'LEADER STARTS',
                    style: TextStyle(
                      color: Color(0xFFFFC857),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            if (isLeader) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (coordinationMode == RideCoordinationMode.solo &&
                      onJoinGroup != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('join-group-before-start-button'),
                        onPressed: busy ? null : onJoinGroup,
                        icon: const Icon(Icons.group_add_outlined),
                        label: const Text('Join group'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('start-ride-button'),
                      onPressed: busy ? null : onStartRide,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start flight'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                  routeName == null
                      ? Icons.route_outlined
                      : Icons.check_circle_outline,
                  size: 18,
                  color: routeName == null
                      ? const Color(0xFFFFC857)
                      : const Color(0xFF6ED89A),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    routeName == null
                        ? 'No route selected'
                        : 'Route: $routeName',
                    maxLines: 2,
                    style: const TextStyle(
                      color: Color(0xFFD4DCE6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isLeader)
                  TextButton(
                    key: const Key('pre-start-choose-route'),
                    onPressed: busy ? null : onChooseRoute,
                    child: Text(routeName == null ? 'Choose route' : 'Change'),
                  ),
              ],
            ),
            if (coordinationMode.isGroup) ...[
              const SizedBox(height: 4),
              Row(
                key: const Key('pre-start-roster'),
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 17,
                    color: Color(0xFFA9B4C2),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${participants.length} ready'
                      '${participants.isEmpty ? '' : ' · ${participants.map((participant) => '${participant.displayName}${participant.isLocal ? ' (you)' : ''}').join(', ')}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA9B4C2),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// One destination of the active ride, named once.
///
/// The navigation bar, the landscape rail and the ride menu all read this list,
/// so they cannot disagree about what exists or what it is called. That matters
/// because the ride menu is the *only* way to reach these while the rider is
/// moving (#404): a copy that drifted would strand the rider at exactly the
/// moment the bar is gone.
class RideDestination {
  const RideDestination({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// Position in the shell's `switch`, which differs between an ordinary ride
  /// and a simulation because Ride Lab is inserted at 1.
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The destinations of an active ride, in bar order.
///
/// [simulation] inserts Ride Lab, which shifts everything after it — which is
/// why the index is carried rather than inferred by a caller counting.
List<RideDestination> rideDestinations({required bool simulation}) {
  var index = 0;
  RideDestination next(String label, IconData icon, IconData selectedIcon) =>
      RideDestination(
        index: index++,
        label: label,
        icon: icon,
        selectedIcon: selectedIcon,
      );
  return [
    next('Map', Icons.map_outlined, Icons.map),
    if (simulation) next('Replay', Icons.science_outlined, Icons.science),
    next('Flight', Icons.air_outlined, Icons.air),
    next('Settings', Icons.settings_outlined, Icons.settings),
  ];
}

enum _StartRideDecision { cancel, chooseRoute, start }

@visibleForTesting
enum RideExitDecision { cancel, leave, endForEveryone }

@visibleForTesting
enum RideCompletionDecision { continueRide, endForEveryone }

@visibleForTesting
/// [isSolo] collapses the choice rather than rewording it. A rider alone has no
/// group to leave and nobody to end anything *for*: "leave only this phone" and
/// "end for everyone" are the same act, and offering both asked them to choose
/// between two descriptions of it while telling them they were about to affect
/// people who were not there (#362).
Future<RideExitDecision?> showRideExitDialog(
  BuildContext context, {
  required bool isLeader,
  bool isSolo = false,
}) => showDialog<RideExitDecision>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(
      isSolo
          ? 'End this flight?'
          : isLeader
          ? 'Leave or end this flight?'
          : 'Leave this flight?',
    ),
    content: Text(
      isSolo
          ? 'Your flight ends and location sharing stops on this phone.'
          : isLeader
          ? 'Leave only this phone, or end the group flight for everyone.'
          : 'Your location sharing will stop on this phone. The group flight '
                'will continue for everyone else.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, RideExitDecision.cancel),
        child: const Text('Cancel'),
      ),
      if (!isSolo)
        TextButton(
          key: const Key('leave-only-this-phone'),
          onPressed: () => Navigator.pop(dialogContext, RideExitDecision.leave),
          child: Text(isLeader ? 'Leave only' : 'Leave flight'),
        ),
      if (isLeader)
        FilledButton(
          key: const Key('end-ride-for-everyone'),
          onPressed: () =>
              Navigator.pop(dialogContext, RideExitDecision.endForEveryone),
          child: Text(isSolo ? 'End flight' : 'End for everyone'),
        ),
    ],
  ),
);

@visibleForTesting
Future<RideCompletionDecision?> showRideCompletionDialog(
  BuildContext context, {
  required RideCompletionAssessment assessment,
  required bool relayCanCarryReopen,
}) => showDialog<RideCompletionDecision>(
  context: context,
  barrierDismissible: false,
  builder: (dialogContext) => AlertDialog(
    key: const Key('ride-completion-suggestion'),
    icon: const Icon(Icons.flag_circle_outlined),
    title: const Text('Has everyone finished?'),
    content: Text(
      '${assessment.arrivedRiderCount} of ${assessment.riderCount} crew members have '
      'fresh positions within ${assessment.destinationRadiusMeters.round()} m '
      'of the destination, and '
      '${(assessment.routeProgressFraction * 100).clamp(0, 100).round()}% of '
      'the route has been completed.\n\n'
      '${relayCanCarryReopen ? 'If this is wrong, the coordinator can resume this flight within 24 hours without changing its code.' : 'This relay cannot resume an ended flight on the other phones. Only end when the whole crew is definitely finished.'}',
    ),
    actions: [
      TextButton(
        key: const Key('continue-completed-ride'),
        onPressed: () =>
            Navigator.pop(dialogContext, RideCompletionDecision.continueRide),
        child: const Text('Continue flight'),
      ),
      FilledButton(
        key: const Key('confirm-completed-ride'),
        onPressed: () =>
            Navigator.pop(dialogContext, RideCompletionDecision.endForEveryone),
        child: const Text('End for everyone'),
      ),
    ],
  ),
);

class _OperationalBoundaryDraft {
  _OperationalBoundaryDraft({
    required this.id,
    required this.label,
    required this.kind,
    required this.source,
    this.lowerAltitudeMeters,
    this.upperAltitudeMeters,
    this.altitudeDatum = AltitudeDatum.wgs84Geoid,
  });

  final String id;
  final String label;
  final OperationalBoundaryKind kind;
  final String source;
  final double? lowerAltitudeMeters;
  final double? upperAltitudeMeters;
  final AltitudeDatum altitudeDatum;
  final List<route_domain.GeoPoint> points = [];
}

class _ActiveRideShellState extends State<ActiveRideShell>
    with WidgetsBindingObserver {
  final _mapPosition = ValueNotifier<route_domain.GeoPoint?>(null);
  final _mapNavigationPosition = ValueNotifier<MapNavigationPosition?>(null);
  final _mapOverlays = ValueNotifier<List<MapOverlayMarker>>(const []);
  final _riderTrails = ValueNotifier<List<MapOverlayTrace>>(const []);
  final _carPlayRouteProgressTracker = RouteProgressTracker();
  final _carPlayJourneyProgressTracker = RouteJourneyProgressTracker();
  final _trailSimplifier = const TrailDisplaySimplifier();
  final _balloonTrailSimplifier = const TrailDisplaySimplifier(
    preserveAltitudeProfile: true,
  );
  final _enforcementAlert = ValueNotifier<EnforcementAlert?>(null);

  /// The arrival being offered to the rider, or null when there is nothing to
  /// offer. Replaces the modal that used to cover the map at the one moment a
  /// rider still needed it (#380).
  final _rideCompletionSuggestion = ValueNotifier<RideCompletionAssessment?>(
    null,
  );

  /// Quick messages the ride map should be presenting, most urgent first (#151).
  ///
  /// Already filtered to what this rider still has to act on: another rider's
  /// message drops out the moment this phone acknowledges it, and this rider's
  /// own message only appears once somebody has acknowledged it, as a receipt.
  final _quickMessageAlerts = ValueNotifier<List<RideQuickMessageAlert>>(
    const [],
  );
  final _dismissedQuickMessageInterruptIds = <String>{};
  final _dismissedQuickMessageReceiptIds = <String>{};

  // The active-ride tabs are a `switch` on the selected index, not an
  // IndexedStack, so moving to Ride details and back disposes and rebuilds the
  // map. Anything the rider has decided that lives in the map's own State is
  // therefore undone by a tab change - which is what a tester hit: cleared
  // enforcement alerts coming back, and an accepted route-start leg having to be
  // accepted again (#282). These live here because this shell outlives the tabs.
  String? _dismissedEnforcementAlertId;
  route_domain.ImportedRoute? _routeStartConnector;

  /// The voice for turn prompts.
  ///
  /// This was declared and never assigned, so it was null for the whole life of
  /// every ride and `_speakGuidance` returned at its first guard: a rider who
  /// turned spoken guidance on got silence, with the setting saved and read and
  /// nothing behind it (#361).
  ///
  /// Built eagerly now, and safely: `SpokenGuidanceSpeaker` does not touch the
  /// engine until something is actually spoken, and it checks `enabled` first,
  /// so a rider who leaves the option off still never has a speech engine
  /// initialised behind their back.
  SpokenGuidanceSpeaker? _spokenGuidance;

  /// Every staged prompt already spoken, so a stage is not repeated on each fix
  /// and the early one does not suppress the ones after it (#410).
  final _spokenGuidanceKeys = <String>{};

  /// The manoeuvre the rider was last being guided towards, and where it was.
  ///
  /// Kept so "am I clear of the junction I just went through" can be answered
  /// without new progress plumbing: it is the straight-line distance from here to
  /// there, which is what #429's clearance rule needs.
  String? _guidanceManeuverIdentity;
  route_domain.GeoPoint? _passedManeuverPosition;
  route_domain.GeoPoint? _lastGuidanceManeuverPosition;

  /// Null unless an instrumented build has recording switched on (#419).
  ///
  /// Held rather than consulted through the controller on every fix so the
  /// hot paths below are one null check, not a preference read: the recorder
  /// must not change the timing it exists to measure.
  RideDiagnosticsRecorder? _diagnostics;

  /// Keeps the stored copy of [_diagnostics] in step (#456).
  ///
  /// Built lazily rather than in `initState` because it is keyed on the ride id,
  /// and a shell can exist before its session does.
  RideDiagnosticsLogWriter? _diagnosticsWriter;
  final _trailRecorder = RiderTrailRecorder();
  final _publishedEventIds = <String>{};
  final _warnings = <String>{};
  static const _backgroundLocationWarning =
      'Background GPS is limited. In iPhone Settings, allow Location → Always '
      'before using another navigation app; otherwise your group position and '
      'recorded trail may pause.';
  final _rideCompletionDetector = RideCompletionDetector();
  bool _completionPromptedForArrival = false;

  /// Progress along the active route, used only to arm the automatic ride end.
  ///
  /// Deliberately the shell's own tracker rather than the map's: completion has
  /// to work when the map is not the visible tab, and the map's tracker is tied
  /// to that widget's lifecycle. Both are monotonic and fed the same fixes, so
  /// they agree.
  final _completionProgressTracker = RouteProgressTracker();

  /// Recorded travelled trails, composed into the map's one trail channel.
  List<MapOverlayTrace> _recordedTrailTraces = const [];
  List<MapOverlayTrace> _operationalBoundaryTraces = const [];
  final _operationalBoundaryMonitor = OperationalBoundaryMonitor();

  /// TEC requests this phone has already put in front of the rider, so an
  /// unanswered request does not reopen its dialog on every rebuild.

  late final RideScreenAwakeCoordinator _screenAwakeCoordinator;

  SituationalAwarenessController? _awarenessController;

  /// The bundled fixed-camera layer, read once and kept for the life of the
  /// shell. A missing or unreadable asset leaves this an empty catalogue rather
  /// than failing the ride: no camera warnings is a degraded ride, no ride is
  /// not.
  FixedSpeedCameraCatalogue? _fixedSpeedCameras;
  CarPlayBridge? _carPlayBridge;
  String? _carPlayMapStyleJson;
  late final http.Client _carPlayRoutingClient;
  late final http.Client _windForecastClient;
  late final RoadRoutingService _simulationRoutingService;
  late final DestinationRoutePlanner _carPlayDestinationPlanner;
  ForegroundLocationController? _locationController;
  NearbyRelayController? _relayController;
  InternetRelayController? _internetRelayController;
  ObserverAccessController? _observerAccessController;
  RidePushNotificationController? _pushNotificationController;
  PreStartPresenceController? _preStartPresenceController;
  SharedPreferencesInternetCursorStore? _internetCursorStore;
  RideSimulationController? _simulationController;
  RelayTrafficRerouteProvider? _trafficRerouteProvider;
  SharedPreferences? _trafficReroutePreferences;
  InMemoryRouteStore? _simulationRouteStore;

  /// The bundled Fiesta ride, held so the simulation controller can play the
  /// balloon back against the clock rather than dragging it along the road.
  BalloonFlight? _balloonFlight;
  WindForecastController? _windForecastController;
  final ValueNotifier<MapLandingZone?> _simulationLandingZone = ValueNotifier(
    null,
  );
  final ValueNotifier<MapLandingZone?> _sharedLandingZone = ValueNotifier(null);
  bool _selectingLandingZone = false;
  _OperationalBoundaryDraft? _operationalBoundaryDraft;
  double _landingRadiusMeters = 500;
  ChaseGuidanceTarget? _chaseGuidanceTarget;
  bool _chaseGuidanceRouting = false;
  DateTime? _lastChaseGuidanceRouteAt;
  awareness_geo.GeoPoint? _lastChaseGuidanceTarget;
  int _chaseGuidanceRouteSequence = 0;
  static const _chaseGuidanceResolver = ChaseGuidanceTargetResolver();
  static const _chaseGuidanceReroutePolicy = ChaseGuidanceReroutePolicy();
  String? _recordedWindContextFingerprint;
  bool _simulationRerouteInFlight = false;
  Duration? _lastSimulationRerouteElapsed;
  awareness_geo.GeoPoint? _lastSimulationRerouteLanding;
  int _simulationRerouteSequence = 0;
  RouteStore? _rideRouteStore;
  StreamSubscription<RideEvent>? _receivedEventSubscription;
  StreamSubscription<RideEvent>? _internetReceivedEventSubscription;
  StreamSubscription<PushOpenRequest>? _pushOpenSubscription;
  Timer? _stalenessTimer;
  Timer? _externalHazardTimer;
  Timer? _simulationAwarenessTimer;
  int _observedNearbyPublishEventCount = -1;
  bool _nearbyPublishWorkPending = true;
  bool _nearbyPublishInFlight = false;
  String? _routeFingerprint;
  String? _trailLifecycleFingerprint;
  String? _appliedAuthoritativeRouteRevision;
  String? _simulationRouteFingerprint;
  LiveRouteState _liveRoutes = const LiveRouteState();
  route_domain.ImportedRoute? _simulationChaseRoute;
  NavigationGuidance? _latestNavigationGuidance;
  TrafficRerouteSuppression? _trafficRerouteSuppression;
  String? _lastTrafficOfferFingerprint;
  String? _trafficRerouteError;
  int _routeGeneration = 0;
  int _selectedIndex = 0;
  Object? _changeRouteRequestToken;
  PickedGpxFile? _pendingSharedGpxFile;
  PendingInAppRoute? _pendingInAppRoute;
  DateTime? _lastSimulationNavigationUpdateAt;
  DateTime? _lastSimulationOverlayUpdateAt;
  LocationSample? _latestObserverLocationSample;

  /// Decides which device fixes become durable position reports (#166).
  ///
  /// It gates the journal only. The observer snapshot and the ephemeral presence
  /// channel above it see every fix, so a rider stays continuously visible while
  /// the expensive half of reporting follows distance travelled.
  final PositionReportGate _positionReportGate = PositionReportGate();
  bool _loading = true;
  bool _relayConfigured = false;
  bool _publishingRouteChange = false;
  bool _rideEndHandled = false;
  bool _autoEndingRide = false;
  bool _simulationPausedByRide = false;
  bool _trafficRerouting = false;
  bool _observedRideStarted = false;
  bool _localRideStartInProgress = false;
  bool _rideStartFlowInProgress = false;
  RideRole? _lastPushRole;

  bool get _isSimulation => widget.rideController.session?.isSimulation == true;

  /// The route this device actively follows. The shared aircraft forecast and
  /// a chase vehicle's road route are deliberately separate sources of truth.
  route_domain.ImportedRoute? get _activeRoute {
    if (_isSimulation) return _simulationChaseRoute;
    final role = widget.rideController.session?.flightRole;
    return role == null ? null : _liveRoutes.activeFor(role);
  }

  set _activeRoute(route_domain.ImportedRoute? route) {
    if (_isSimulation) {
      _simulationChaseRoute = route;
      return;
    }
    final role = widget.rideController.session?.flightRole;
    if (role?.isChasing == true) {
      _liveRoutes = _liveRoutes.withVehicleRoadRoute(route);
    } else {
      _liveRoutes = _liveRoutes.withSharedFlightPlan(route);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Headless and test surfaces have no audio to speak through, and must not
    // construct a platform speech engine.
    if (widget.rideDiagnostics?.isOn ?? false) {
      _startDiagnostics(rideDiagnosticsStartedNote);
    }
    // Read on every change, not once here: the switch used to be sampled in
    // `initState` alone, so turning recording on mid-ride — through the ride
    // menu, the door closest to hand while riding — showed it on and recorded
    // nothing (#457).
    widget.rideDiagnostics?.addListener(_onRideDiagnosticsChanged);
    if (widget.enableNativeServices && widget.spokenGuidance != null) {
      _spokenGuidance = SpokenGuidanceSpeaker(
        widget.spokenGuidance!.createEngine(onOutput: _recordSpeechOutput),
      );
      widget.spokenGuidance!.addListener(_onSpokenGuidanceChanged);
    }
    _observedRideStarted =
        widget.rideController.rideStarted && !widget.rideController.rideEnded;
    if (_observedRideStarted) unawaited(_warmNaturalVoiceIfNeeded());
    _screenAwakeCoordinator = RideScreenAwakeCoordinator(
      wakeLock: widget.screenWakeLock,
      reassertInterval: widget.screenWakeReassertInterval,
      onError: (error, _) {
        if (kDebugMode) debugPrint('Could not enforce ride wake lock: $error');
      },
    )..start();
    final carPlayRouting = RoutingConfiguration.fromEnvironment();
    _carPlayRoutingClient = http.Client();
    _windForecastClient = http.Client();
    _simulationRoutingService = PreferenceAwareRoadRoutingService(
      osrm: OsrmRoadRoutingService(
        client: _carPlayRoutingClient,
        baseUrl: carPlayRouting.routingBaseUrl,
      ),
      valhalla: ValhallaRoadRoutingService(
        client: _carPlayRoutingClient,
        routeUrl: carPlayRouting.valhallaRoutingUrl,
      ),
    );
    _carPlayDestinationPlanner = DestinationRoutePlanner(
      searchService: NominatimDestinationSearchService(
        client: _carPlayRoutingClient,
        baseUrl: carPlayRouting.geocodingBaseUrl,
      ),
      routingService: _simulationRoutingService,
    );
    widget.rideController.addListener(_onRideControllerChanged);
    _syncSharedLandingZone();
    _syncOperationalBoundaries();
    widget.sharedRoutes.addListener(_onSharedRoutesChanged);
    _capturePlannerLinkError();
    if (widget.sharedRoutes.pending case final file?) {
      if (widget.rideController.hasFlightAuthority) {
        _selectedIndex = 0;
        _changeRouteRequestToken = Object();
        _pendingSharedGpxFile = file;
      } else {
        _warnings.add('Only the pilot can replace the shared flight forecast.');
      }
      _clearSharedRoutePending();
    } else if (widget.sharedRoutes.pendingInAppRoute case final route?) {
      if (widget.rideController.hasFlightAuthority) {
        _selectedIndex = 0;
        _changeRouteRequestToken = Object();
        _pendingInAppRoute = route;
      } else {
        _warnings.add('Only the pilot can replace the shared flight forecast.');
      }
      _clearSharedRoutePending();
    }
    unawaited(_initialize());
    _carPlayBridge = CarPlayBridge(
      onEmergencyTriggered: _sendEmergencyMapAlert,
      onLeaveRequested: _leaveRide,
      onHazardReported: _reportHazardFromMap,
      onRideStartRequested: _startPreparedRideFromCarPlay,
      onDestinationSearch: _searchCarPlayDestinations,
      onDestinationSelected: _planCarPlayDestination,
      onStateRequested: () async {
        if (!mounted) return;
        _updateMapOverlays(updateDerivedState: false);
      },
    );
  }

  /// A GPX file can arrive (via the platform's "Open in..." delivery) while
  /// this ride is already on screen - e.g. resuming from background. Reuses
  /// the same request path as the Ride page's "Change route", just with the
  /// file already in hand instead of asking the map to show its picker.
  void _onSharedRoutesChanged() {
    if (!mounted) return;
    final warningAdded = _capturePlannerLinkError();
    final file = widget.sharedRoutes.pending;
    final inAppRoute = widget.sharedRoutes.pendingInAppRoute;
    if (file == null && inAppRoute == null) {
      if (warningAdded) setState(() {});
      return;
    }
    if (!widget.rideController.hasFlightAuthority) {
      _warnings.add('Only the pilot can replace the shared flight forecast.');
      _clearSharedRoutePending();
      setState(() {});
      return;
    }
    setState(() {
      _selectedIndex = 0;
      _changeRouteRequestToken = Object();
      _pendingSharedGpxFile = file;
      _pendingInAppRoute = inAppRoute;
    });
    _clearSharedRoutePending();
  }

  bool _capturePlannerLinkError() {
    if (widget.sharedRoutes.plannerLinkStatus != PlannerLinkStatus.error) {
      return false;
    }
    final message = widget.sharedRoutes.plannerLinkMessage;
    if (message == null) return false;
    final code = widget.sharedRoutes.plannerLinkCode;
    return _warnings.add(
      'Shared route link: $message'
      '${code == null ? '' : ' You can still enter code $code from Change route → Load a planned route.'}',
    );
  }

  /// Deferred a frame so this never calls notifyListeners() back into
  /// SharedRouteController from inside its own listener dispatch (this method
  /// runs either from that listener, or from initState before the first
  /// frame - neither is a safe place to notify synchronously).
  void _clearSharedRoutePending() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.sharedRoutes.clearPending();
    });
  }

  Future<void> _initialize() async {
    route_domain.ImportedRoute? route;
    var publishStoredLeaderRoute = false;
    if (_isSimulation) {
      try {
        // Ride Lab currently replays one local chase road route alongside the
        // balloon track. Production keeps those route purposes separate.
        const loader = BundledFiestaFlightLoader();
        route = await loader.loadChaseRoute();
        _balloonFlight = await loader.load();
        _simulationRouteStore = InMemoryRouteStore(route);
        final flight = _balloonFlight!;
        _windForecastController = WindForecastController(
          OpenMeteoWindProvider(client: _windForecastClient),
          initialField: _bundledWindForecast(flight),
        );
        _windForecastController!.addListener(_onWindForecastChanged);
        _onWindForecastChanged();
        if (widget.enableNativeServices) {
          unawaited(_windForecastController!.refresh(flight.launch));
        }
        _warnings.add(
          'Flight replay keeps device GPS, internet relay and nearby radios '
          'disabled. Its forecast wind may use Open-Meteo.',
        );
      } on Object catch (error) {
        _warnings.add('The simulation route could not be loaded: $error');
      }
    } else if (widget.enableNativeServices) {
      _windForecastController = WindForecastController(
        OpenMeteoWindProvider(client: _windForecastClient),
      );
      _windForecastController!.addListener(_onWindForecastChanged);
      try {
        final session = widget.rideController.session;
        if (session != null) {
          _rideRouteStore = await JsonFileRouteStore.openForRide(
            session.rideId,
          ).timeout(_localRouteRestoreTimeout);
          final storedRoute = await _rideRouteStore!.loadActiveRoute().timeout(
            _localRouteRestoreTimeout,
          );
          final authoritative = widget.rideController.authoritativeRouteState;
          _appliedAuthoritativeRouteRevision = authoritative.revisionId;
          if (session.flightRole.isChasing) {
            // This store belongs to this device, so on a chaser it contains
            // road guidance. The relay's authoritative route is the shared
            // aircraft forecast and must never replace it.
            _liveRoutes = LiveRouteState(
              sharedFlightPlan: authoritative.hasDecision
                  ? authoritative.route
                  : null,
              vehicleRoadRoute: storedRoute,
            );
          } else {
            final sharedPlan = authoritative.hasDecision
                ? authoritative.route
                : storedRoute;
            _liveRoutes = LiveRouteState(sharedFlightPlan: sharedPlan);
            if (authoritative.hasDecision) {
              if (sharedPlan == null) {
                await _rideRouteStore!.clearActiveRoute();
              } else {
                await _rideRouteStore!.saveActiveRoute(sharedPlan);
              }
            } else {
              publishStoredLeaderRoute =
                  widget.rideController.hasFlightAuthority &&
                  sharedPlan != null;
            }
          }
          route = _activeRoute;
        }
      } on Object catch (error) {
        // Never fall back to the legacy app-wide route file. A failed
        // ride-scoped store should leave this ride empty instead of reviving
        // a route chosen for an earlier ride.
        _rideRouteStore = InMemoryRouteStore();
        _warnings.add('Route storage could not be opened: $error');
        final authoritative = widget.rideController.authoritativeRouteState;
        _appliedAuthoritativeRouteRevision = authoritative.revisionId;
        if (authoritative.hasDecision) {
          _liveRoutes = _liveRoutes.withSharedFlightPlan(authoritative.route);
        }
        route = _activeRoute;
      }
    }

    if (_isSimulation) _activeRoute = route;
    if (!mounted) return;

    // The map depends only on its ride-scoped route store. It must not leave a
    // full-screen spinner up while GPS, push, internet presence or nearby
    // transport start in the background. This frame is the escape hatch for a
    // transport plugin that never returns on a particular Android phone
    // (#209).
    setState(() => _loading = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      await _initializeTrafficRerouting();
    } on Object catch (error) {
      _warnings.add('Traffic preferences could not be restored: $error');
    }
    try {
      await _restoreChaseGuidanceTarget();
    } on Object catch (error) {
      _warnings.add('Chase guidance preference could not be restored: $error');
    }
    try {
      await _replaceAwarenessController(route);
    } on Object catch (error) {
      _warnings.add('Flight map history could not be restored: $error');
    }
    if (_isSimulation) {
      try {
        await _replaceSimulationController(route);
      } on Object catch (error) {
        _warnings.add('Flight replay could not be restored: $error');
      }
    }
    if (publishStoredLeaderRoute && route != null) {
      try {
        await widget.rideController.publishRoute(route);
        _appliedAuthoritativeRouteRevision =
            widget.rideController.authoritativeRouteState.revisionId;
      } on Object catch (error) {
        _warnings.add(
          'The stored flight forecast could not be published: $error',
        );
      }
    }
    if (!mounted) return;

    if (widget.enableNativeServices && !_isSimulation) {
      final session = widget.rideController.session;
      final groupRide = widget.rideController.coordinationMode.isGroup;
      if (groupRide && widget.rideController.hasFlightAuthority) {
        try {
          await widget.rideController.publishRideCode();
        } on RideCodeDirectoryException catch (error) {
          _warnings.add('Flight code is not ready yet: ${error.message}');
        }
      }
      _stalenessTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        widget.rideController.refreshMembershipFreshness();
        final awareness = _awarenessController;
        if (awareness != null) unawaited(awareness.refreshStaleness());
      });
      _externalHazardTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        final awareness = _awarenessController;
        if (awareness != null) {
          unawaited(awareness.refreshExternalHazards());
        }
      });
      final locationController = ForegroundLocationController(
        DeviceLocationSource(),
        (sample) async {
          _latestObserverLocationSample = sample;
          _publishObserverSnapshot();
          // One decision, taken once, for both halves of reporting: distance
          // travelled, a turn, or the keep-alive timer (#166).
          final reported = _positionReportGate.consider(sample);
          // Every fix goes to the ephemeral presence channel, in both phases,
          // so this rider stays continuously visible to the group. The durable
          // journal still only receives post-start fixes.
          final currentSession = widget.rideController.session;
          if (currentSession != null) {
            _preStartPresenceController?.updateLocalPosition(
              RiderLocation(
                riderId: currentSession.localRiderId,
                displayName: currentSession.displayName,
                role: currentSession.role,
                sample: sample,
                receivedAt: DateTime.now(),
                motorcycleStyle: currentSession.motorcycleStyle,
                riderSymbol: currentSession.riderSymbol,
                riderColor: currentSession.riderColor,
              ),
              // A withheld fix is still held as the newest position and still
              // goes out on the next presence tick; it just does not bring that
              // tick forward. Presence itself never waits for movement.
              publishImmediately: reported != null,
            );
          }
          final startedAt = widget.rideController.rideStartedAt;
          if (startedAt == null || sample.recordedAt.isBefore(startedAt)) {
            return;
          }
          // A withheld fix is not a lost fix: the presence channel above has it,
          // so the only thing not happening here is a journal event nobody
          // needed.
          if (reported == null) return;
          final awareness = _awarenessController;
          if (awareness != null) {
            await awareness.recordLocalLocation(sample);
          }
        },
        onSampleError: (error, stackTrace) {
          if (kDebugMode) {
            debugPrint(
              'Could not persist a location update; continuing: '
              '$error\n$stackTrace',
            );
          }
          final added = _warnings.add(
            'A location update could not be saved. Live GPS is continuing.',
          );
          if (added && mounted) setState(() {});
        },
      );
      _locationController = locationController;
      locationController.addListener(_onDeviceLocationChanged);
      try {
        await locationController.initialize();
      } on Object catch (error) {
        _warnings.add('Location capability check failed: $error');
      }
      if (widget.rideController.rideStarted &&
          !widget.rideController.rideEnded) {
        await _resumeLocationForActiveRide();
      } else {
        await _startLocationForPreStartMap();
      }

      if (session != null) {
        final cursorStore = SharedPreferencesInternetCursorStore();
        _internetCursorStore = cursorStore;
        final internetRelayController = InternetRelayController(
          InternetRelayWorker(
            api: HttpInternetRelayClient(
              configuration: InternetRelayConfiguration.fromEnvironment(),
              client: http.Client(),
            ),
            eventStore: widget.eventStore,
            cursorStore: cursorStore,
          ),
        );
        _internetRelayController = internetRelayController;
        _internetReceivedEventSubscription = internetRelayController
            .receivedEvents
            .listen(
              (event) =>
                  _onReceivedEvent(event, RideTransportEvidence.internetRelay),
            );
        await internetRelayController.start(session);
        final observerConfiguration =
            ObserverAccessConfiguration.fromEnvironment();
        if (observerConfiguration.configurationError == null) {
          _observerAccessController = ObserverAccessController(
            HttpObserverAccessClient(
              configuration: observerConfiguration,
              client: http.Client(),
            ),
            const SecureObserverGrantStore(),
          );
          await _observerAccessController!.attach(session);
          if (_observerAccessController!.hasActiveGrants) {
            await locationController.resumeIfAuthorized();
            _publishObserverSnapshot();
          }
        }
        if (groupRide) {
          final pushNotificationController = RidePushNotificationController(
            tokenSource:
                widget.pushTokenSource ??
                NativePushTokenSource(
                  NativePushConfiguration.fromEnvironment(),
                ),
            registrationApi:
                widget.pushRegistrationApi ??
                HttpPushRegistrationClient(
                  configuration: InternetRelayConfiguration.fromEnvironment(),
                  client: http.Client(),
                ),
            preferencesStore: await SharedPreferences.getInstance(),
          );
          _pushNotificationController = pushNotificationController;
          pushNotificationController.addListener(
            _onPushNotificationStatusChanged,
          );
          _pushOpenSubscription = pushNotificationController.openedNotifications
              .listen(_onPushNotificationOpened);
          await pushNotificationController.start(session);
          _lastPushRole = session.role;
          final preStartPresenceController = PreStartPresenceController(
            HttpPreStartPresenceClient(
              configuration: InternetRelayConfiguration.fromEnvironment(),
              client: http.Client(),
            ),
          );
          _preStartPresenceController = preStartPresenceController;
          preStartPresenceController.addListener(_onPreStartPresenceChanged);
          // Presence runs for the whole ride, not only before the start. It is
          // what keeps a rider visible across `rideStarted` and what makes a
          // rider who joins an already-started ride appear immediately.
          if (!widget.rideController.rideEnded) {
            await preStartPresenceController.start(session);
          }
        }
      }
      if (groupRide && session != null && session.inviteSecret.length >= 16) {
        final relayController = NearbyRelayController(
          RelayEngine(
            transport: NativeNearbyTransport(),
            eventStore: widget.eventStore,
            queue: SqliteRelayQueue(),
          ),
        );
        _relayController = relayController;
        _receivedEventSubscription = relayController.receivedEvents.listen(
          (event) => _onReceivedEvent(event, RideTransportEvidence.nearbyRelay),
        );
        try {
          await relayController.start(session);
          _relayConfigured = true;
          await _preStartPresenceController?.attachNearby(relayController);
        } on Object catch (error) {
          _warnings.add('Nearby relay could not start: $error');
        }
      }
    }

    if (!mounted) return;
    if (widget.rideController.rideEnded) {
      await _handleRideEnded();
    }
    _schedulePublish();
  }

  /// Route storage is local and normally opens in milliseconds. If the
  /// platform file-service call itself wedges, fall back to an empty in-memory
  /// store so the rider gets controls rather than an indefinite map spinner.
  static const _localRouteRestoreTimeout = Duration(seconds: 2);

  Future<void> _initializeTrafficRerouting() async {
    if (_isSimulation || !widget.enableNativeServices) return;
    _trafficRerouteProvider = RelayTrafficRerouteProvider(
      configuration: InternetRelayConfiguration.fromEnvironment(),
    );
    final preferences = await SharedPreferences.getInstance();
    _trafficReroutePreferences = preferences;
    final value = preferences.getString(_trafficRerouteSuppressionKey);
    if (value == null) return;
    final suppression = TrafficRerouteSuppression.tryDecode(value);
    if (suppression == null || !suppression.until.isAfter(DateTime.now())) {
      await preferences.remove(_trafficRerouteSuppressionKey);
      return;
    }
    _trafficRerouteSuppression = suppression;
  }

  String get _trafficRerouteSuppressionKey =>
      'traffic-reroute-suppression:'
      '${widget.rideController.session?.rideId ?? 'none'}';

  String get _chaseGuidancePreferenceKey =>
      'chase-guidance-target:'
      '${widget.rideController.session?.rideId ?? 'none'}';

  bool get _isChaserPerspective =>
      widget.rideController.session?.flightRole.isChasing == true;

  Future<void> _restoreChaseGuidanceTarget() async {
    if (!_isChaserPerspective) return;
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_chaseGuidancePreferenceKey);
    _chaseGuidanceTarget = ChaseGuidanceTarget.values
        .where((target) => target.name == stored)
        .firstOrNull;
    _chaseGuidanceTarget ??= widget.rideController.landingZone == null
        ? ChaseGuidanceTarget.balloon
        : ChaseGuidanceTarget.landingArea;
  }

  /// Publishes a rider's own enforcement sighting to the group.
  ///
  /// Reported as [HazardSeverity.serious] so it reaches the same advance
  /// warning the provider feed drives; the shorter enforcement expiry in
  /// [HazardExpiryPolicy] keeps a moved-on van from warning riders all day.
  Future<void> _reportHazardFromMap(HazardType type) async {
    final awareness = _awarenessController;
    if (awareness == null) {
      throw const FormatException('This flight is not tracking hazards yet.');
    }
    await awareness.reportHazard(type: type, severity: HazardSeverity.serious);
  }

  List<HazardReport> get _trafficRerouteHazards {
    if (widget.rideController.localFlightRole != FlightRole.chaseDriver ||
        !widget.rideController.rideStarted ||
        _activeRoute == null) {
      return const [];
    }
    final now = DateTime.now();
    final hazards =
        _awarenessController?.activeHazards
            .where(
              (hazard) =>
                  hazard.source == HazardSource.externalProvider &&
                  hazard.providerId == 'tomtom-traffic' &&
                  // Enforcement is warned about, never routed around: a camera
                  // is not an obstruction and the group's route is not the
                  // place to act on one.
                  !enforcementHazardTypes.contains(hazard.type) &&
                  hazard.severity.index >= HazardSeverity.serious.index,
            )
            .take(10)
            .toList(growable: false) ??
        const <HazardReport>[];
    if (hazards.isEmpty) return hazards;
    if (_trafficRerouteSuppression?.suppresses(hazards, now) == true) {
      return const [];
    }
    return hazards;
  }

  Future<void> _dismissTrafficAlternative() async {
    final hazards = _trafficRerouteHazards;
    if (hazards.isEmpty) return;
    await _suppressTrafficIncidents(hazards);
    if (mounted) {
      setState(() {
        _trafficRerouteError = null;
        _lastTrafficOfferFingerprint = null;
      });
    }
  }

  Future<void> _suppressTrafficIncidents(List<HazardReport> hazards) async {
    if (hazards.isEmpty) return;
    final suppression = TrafficRerouteSuppression.forHazards(hazards);
    _trafficRerouteSuppression = suppression;
    await _trafficReroutePreferences?.setString(
      _trafficRerouteSuppressionKey,
      suppression.encode(),
    );
  }

  Future<void> _reviewTrafficAlternative() async {
    if (_trafficRerouting) return;
    final provider = _trafficRerouteProvider;
    final route = _activeRoute;
    final hazards = _trafficRerouteHazards;
    if (provider == null || route == null || hazards.isEmpty) return;
    setState(() {
      _trafficRerouting = true;
      _trafficRerouteError = null;
    });
    try {
      final preview = await provider.preview(
        route: route,
        currentPosition: _mapPosition.value,
        hazards: hazards,
      );
      if (!mounted) return;
      final formatter = MeasurementFormatter(widget.distanceUnits.value);
      final distanceDelta = preview.distanceDeltaMeters;
      final durationDelta = preview.durationDelta;
      final comparison =
          '${distanceDelta >= 0 ? '+' : '−'}'
          '${formatter.distance(distanceDelta.abs())}; '
          '${durationDelta.isNegative ? 'saves' : 'adds'} '
          '${_trafficDurationLabel(durationDelta.abs())}.';
      final action = await RouteConfirmationSheet.show(
        context,
        route: preview.route,
        distanceUnit: widget.distanceUnits.value,
        distanceMeters: preview.alternativeDistanceMeters,
        duration: preview.alternativeDuration,
        previousRoute: route,
        warnings: [
          hazards.first.details ??
              '${hazards.first.type.label} may affect the current route.',
          'TomTom traffic alternative: $comparison',
          if (preview.trafficDelaySaved > Duration.zero)
            'Estimated live-traffic delay avoided: '
                '${_trafficDurationLabel(preview.trafficDelaySaved)}.',
          'This vehicle keeps its current road route until you confirm.',
        ],
      );
      if (action != RouteConfirmationAction.confirm || !mounted) return;
      _liveRoutes = _liveRoutes.withVehicleRoadRoute(preview.route);
      await _rideRouteStore?.saveActiveRoute(preview.route);
      await _replaceAwarenessController(preview.route);
      await _suppressTrafficIncidents(hazards);
      if (mounted) {
        setState(() {
          _lastTrafficOfferFingerprint = null;
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _trafficRerouteError = error.message);
    } on Object {
      if (mounted) {
        setState(() {
          _trafficRerouteError =
              'The traffic alternative could not be calculated. '
              'The current route has not changed.';
        });
      }
    } finally {
      if (mounted) setState(() => _trafficRerouting = false);
    }
  }

  Future<void> _replaceAwarenessController(
    route_domain.ImportedRoute? route, {
    bool notify = true,
  }) async {
    final fingerprint = route == null
        ? 'none'
        : '${route.id}:${route.importedAt.toUtc().toIso8601String()}:'
              // The marker review decides which decision points the live
              // detector may suggest, so rejecting one has to rebuild it (#179).
              '${route.pathPointCount}';
    final lifecycleFingerprint =
        widget.rideController.rideStartedAt?.toUtc().toIso8601String() ??
        'open';
    final effectiveFingerprint =
        '$fingerprint:$lifecycleFingerprint:'
        '${widget.rideController.coordinationMode.name}';
    if (_awarenessController != null &&
        effectiveFingerprint == _routeFingerprint) {
      return;
    }
    final generation = ++_routeGeneration;
    final session = widget.rideController.session;
    if (session == null) return;

    final routeSegments =
        route?.paths
            .where((path) => path.points.length >= 2)
            .map(
              (path) => path.points
                  .map(
                    (point) => awareness_geo.GeoPoint(
                      latitude: point.latitude,
                      longitude: point.longitude,
                    ),
                  )
                  .toList(growable: false),
            )
            .toList(growable: false) ??
        const <List<awareness_geo.GeoPoint>>[];
    // Synthetic position updates are intentionally ephemeral. Writing five
    // riders to SQLite throughout a Ride Lab run makes the durable event
    // history grow quickly, which in turn slows down the phone.
    final awarenessEventStore = _isSimulation
        ? InMemoryEventStore()
        : widget.eventStore;
    // Waze is deliberately absent. #111 closed it as ineligible for the partner
    // feed with no other read API, so its card could never become available and
    // a tester reported the permanently-unavailable row as a fault (#175). The
    // adapter itself stays in the repository, where a closed investigation
    // belongs, and is exercised by its own test.
    final externalProviders = <ExternalHazardProvider>[
      if (session.flightRole == FlightRole.chaseDriver && !_isSimulation)
        RelayTrafficHazardProvider(
          configuration: InternetRelayConfiguration.fromEnvironment(),
        ),
      // Lead-gated for the same reason the relay feed is: a provider hazard
      // becomes a ride event that reaches the whole group, and every rider
      // deriving the same cameras from the same bundled asset would write the
      // same event once each. The ids are derived from the OpenStreetMap node
      // so they merge into one hazard either way, but there is no reason to
      // pay for it six times over.
      // Fixed cameras come from a bundled OpenStreetMap extract, so unlike the
      // relay feed they cost nothing to consult and work with no signal.
      //
      // Lead-gated for the same reason the relay feed is: a provider hazard
      // becomes a ride event that reaches the whole group, and every rider
      // deriving the same cameras from the same bundled asset would write the
      // same event once each. The ids are derived from the OpenStreetMap node
      // so they merge into one hazard either way, but there is no reason to pay
      // for it six times over.
      if (session.flightRole == FlightRole.chaseDriver)
        FixedSpeedCameraProvider(readCatalogue: _loadFixedSpeedCameras),
    ];
    final controller = SituationalAwarenessController(
      awarenessEventStore,
      session,
      route: routeSegments.expand((segment) => segment).toList(growable: false),
      externalProviders: externalProviders,
      rideStarted: widget.rideController.rideStarted,
      rideStartedAt: widget.rideController.rideStartedAt,
      onEventStored: widget.rideController.ingestStoredEvent,
    );
    await controller.initialize(restoredEvents: widget.rideController.events);
    if (!mounted || generation != _routeGeneration) {
      controller.dispose();
      return;
    }
    // Publish only after the generation check: a controller built for a
    // superseded route is disposed above, and driving a disposed controller is
    // exactly the stale-reference bug TestControlRegistry exists to avoid.
    widget.testControlRegistry?.publish(controller);

    final previous = _awarenessController;
    previous?.removeListener(_onAwarenessChanged);
    _awarenessController = controller;
    _routeFingerprint = effectiveFingerprint;
    // Replacing the awareness controller usually only means the route changed -
    // a leader reroute, say - and travelled history must survive that with no
    // gap or restart. Only a new ride lifecycle discards it, which is also what
    // keeps the pre-start no-trace rule intact (#35/#51).
    if (lifecycleFingerprint != _trailLifecycleFingerprint) {
      _trailLifecycleFingerprint = lifecycleFingerprint;
      _trailRecorder.clear();
      _recordedTrailTraces = const [];
    }
    _pushRiderTrails();
    controller.addListener(_onAwarenessChanged);
    if (session.flightRole == FlightRole.chaseDriver &&
        !_isSimulation &&
        widget.enableNativeServices) {
      unawaited(controller.refreshExternalHazards());
    }
    previous?.dispose();
    _updateMapOverlays();
    if (notify) setState(() {});
  }

  void _onRouteChanged(route_domain.ImportedRoute? route) {
    unawaited(_handleRouteChanged(route));
  }

  Future<void> _handleRouteChanged(route_domain.ImportedRoute? route) async {
    if (!_isSimulation && !widget.rideController.hasFlightAuthority) {
      _warnings.add('Only the pilot can replace the shared flight forecast.');
      await _applyAuthoritativeRouteDecision();
      if (mounted) setState(() {});
      return;
    }
    _publishingRouteChange = true;
    _activeRoute = route;
    try {
      await _replaceAwarenessController(route);
      if (_isSimulation) {
        await _replaceSimulationController(route);
        return;
      }
      if (route == null) {
        await widget.rideController.clearRoute();
      } else {
        await widget.rideController.publishRoute(route);
      }
      _appliedAuthoritativeRouteRevision =
          widget.rideController.authoritativeRouteState.revisionId;
      final store = _rideRouteStore;
      if (store != null) {
        if (route == null) {
          await store.clearActiveRoute();
        } else {
          await store.saveActiveRoute(route);
        }
      }
    } finally {
      _publishingRouteChange = false;
    }
  }

  Future<void> _applyAuthoritativeRouteDecision() async {
    if (_isSimulation || _publishingRouteChange) return;
    final state = widget.rideController.authoritativeRouteState;
    if (!state.hasDecision ||
        state.revisionId == _appliedAuthoritativeRouteRevision) {
      return;
    }
    _appliedAuthoritativeRouteRevision = state.revisionId;
    final route = state.route;
    _liveRoutes = _liveRoutes.withSharedFlightPlan(route);
    if (!_isChaserPerspective) {
      final store = _rideRouteStore;
      if (store != null) {
        if (route == null) {
          await store.clearActiveRoute();
        } else {
          await store.saveActiveRoute(route);
        }
      }
      await _replaceAwarenessController(route);
    }
    _pushRiderTrails();
    if (mounted) setState(() {});
    if (_isChaserPerspective && _chaseGuidanceTarget != null) {
      unawaited(_refreshChaseGuidanceIfNeeded(force: true));
    }
  }

  Future<void> _replaceSimulationController(
    route_domain.ImportedRoute? route, {
    bool notify = true,
  }) async {
    final fingerprint = route == null
        ? 'none'
        : '${route.id}:${route.importedAt.toUtc().toIso8601String()}:'
              // The marker review decides which decision points the live
              // detector may suggest, so rejecting one has to rebuild it (#179).
              '${route.pathPointCount}';
    final lifecycleFingerprint =
        widget.rideController.rideStartedAt?.toUtc().toIso8601String() ??
        'open';
    final effectiveFingerprint = '$fingerprint:$lifecycleFingerprint';
    if (_simulationController != null &&
        effectiveFingerprint == _simulationRouteFingerprint) {
      return;
    }
    final previous = _simulationController;
    _simulationController = null;
    _simulationRouteFingerprint = effectiveFingerprint;
    _lastSimulationNavigationUpdateAt = null;
    previous?.removeListener(_onSimulationVisualChanged);
    previous?.dispose();

    final awareness = _awarenessController;
    final session = widget.rideController.session;
    final simulationRoute = _simulationRoutePoints(route);
    if (awareness == null ||
        session == null ||
        !session.isSimulation ||
        simulationRoute.length < 2) {
      if (notify && mounted) setState(() {});
      return;
    }
    final controller = RideSimulationController(
      awareness,
      session: session,
      route: simulationRoute,
      balloonFlight: _balloonFlight,
      windForecastController: _windForecastController,
      // Old saved Ride Lab sessions can still carry the former five-rider
      // setting. The demo is now deliberately one balloon and one chase car.
      riderCount: RideSession.defaultSimulationRiderCount,
      rideStarted: widget.rideController.rideStarted,
    );
    _simulationController = controller;
    controller.addListener(_onSimulationVisualChanged);
    await controller.initialize();
    if (!mounted || _simulationController != controller) {
      controller.dispose();
      return;
    }
    if (widget.rideController.rideStarted &&
        !widget.rideController.ridePaused &&
        !widget.rideController.rideEnded) {
      controller.start();
    }
    _onSimulationVisualChanged();
    if (notify) setState(() {});
  }

  void _onSimulationVisualChanged() {
    if (!mounted || !_isSimulation) return;
    _updateSimulationLandingZone();
    unawaited(_rerouteSimulationChaseIfNeeded());
    final now = DateTime.now();
    final updateNavigationPosition =
        _lastSimulationNavigationUpdateAt == null ||
        now.difference(_lastSimulationNavigationUpdateAt!) >=
            const Duration(milliseconds: 200);
    if (updateNavigationPosition) {
      _lastSimulationNavigationUpdateAt = now;
    }
    final updateOverlayMarkers =
        _lastSimulationOverlayUpdateAt == null ||
        now.difference(_lastSimulationOverlayUpdateAt!) >=
            const Duration(milliseconds: 250);
    if (updateOverlayMarkers) _lastSimulationOverlayUpdateAt = now;
    _updateMapOverlays(
      // The map status card is derived from the same authenticated synthetic
      // fixes as the overlays. Without this, a restarted balloon view could
      // keep saying that the chase vehicle's location was unavailable.
      updateDerivedState: updateOverlayMarkers,
      updateOverlayMarkers: updateOverlayMarkers,
      updateNavigationPosition: updateNavigationPosition,
    );
  }

  void _updateSimulationLandingZone() {
    final simulation = _simulationController;
    final predicted = simulation?.predictedLandingZone;
    if (simulation == null || predicted == null) return;
    final field = _windForecastController?.field;
    final label = field?.isLiveForecast == true
        ? 'Forecast landing area · UKMO via Open-Meteo'
        : 'Forecast landing area · bundled wind fallback';
    final next = MapLandingZone(
      center: route_domain.GeoPoint(
        latitude: predicted.latitude,
        longitude: predicted.longitude,
      ),
      label: label,
      radiusMeters: 300,
    );
    final previous = _simulationLandingZone.value;
    if (previous != null &&
        GeoCalculations.distanceMeters(
              awareness_geo.GeoPoint(
                latitude: previous.center.latitude,
                longitude: previous.center.longitude,
              ),
              predicted,
            ) <
            10 &&
        previous.label == next.label) {
      return;
    }
    _simulationLandingZone.value = next;
  }

  Future<void> _rerouteSimulationChaseIfNeeded() async {
    final simulation = _simulationController;
    final landing = simulation?.predictedLandingZone;
    final chase = simulation?.chaseVehicle;
    if (!widget.enableNativeServices ||
        simulation == null ||
        landing == null ||
        chase == null ||
        _simulationRerouteInFlight ||
        !widget.rideController.rideStarted ||
        widget.rideController.ridePaused ||
        widget.rideController.rideEnded) {
      return;
    }
    final lastElapsed = _lastSimulationRerouteElapsed;
    final elapsedEnough =
        lastElapsed == null ||
        simulation.simulatedElapsed - lastElapsed >= const Duration(minutes: 5);
    final lastLanding = _lastSimulationRerouteLanding;
    final landingMoved =
        lastLanding == null ||
        GeoCalculations.distanceMeters(lastLanding, landing) >= 300;
    if (!elapsedEnough && !landingMoved) return;

    _simulationRerouteInFlight = true;
    // Record an attempt as well as a success. A temporary routing outage must
    // not turn the simulator's 100 ms update into a network request loop.
    _lastSimulationRerouteElapsed = simulation.simulatedElapsed;
    _lastSimulationRerouteLanding = landing;
    try {
      final result = await _simulationRoutingService.routeThrough([
        route_domain.GeoPoint(
          latitude: chase.position.latitude,
          longitude: chase.position.longitude,
        ),
        route_domain.GeoPoint(
          latitude: landing.latitude,
          longitude: landing.longitude,
        ),
      ], originBearingDegrees: chase.headingDegrees);
      if (!mounted || _simulationController != simulation) return;
      final route = route_domain.ImportedRoute(
        id: 'live-chase-route-${_simulationRerouteSequence++}',
        name: 'Live chase route to forecast landing area',
        description:
            'Recalculated from the Land Rover position to a road-accessible '
            'point serving the forecast landing area.',
        importedAt: DateTime.now(),
        sourceFileName: 'live-open-meteo-chase-route',
        paths: [
          route_domain.RoutePath(
            kind: route_domain.RoutePathKind.route,
            points: result.points,
          ),
        ],
        waypoints: const [],
        maneuvers: result.maneuvers,
      );
      await _simulationRouteStore?.saveActiveRoute(route);
      if (!mounted || _simulationController != simulation) return;
      _activeRoute = route;
      simulation.replaceChaseRoute(
        result.points
            .map(
              (point) => awareness_geo.GeoPoint(
                latitude: point.latitude,
                longitude: point.longitude,
              ),
            )
            .toList(growable: false),
      );
      setState(() {});
    } on Object catch (error) {
      final added = _warnings.add(
        'Live chase rerouting is unavailable; the last road route is still '
        'in use. $error',
      );
      if (added && mounted) setState(() {});
    } finally {
      _simulationRerouteInFlight = false;
    }
  }

  void _onAwarenessChanged() {
    if (_isSimulation) {
      _scheduleSimulationAwarenessUpdate();
      return;
    }
    _updateMapOverlays();
    unawaited(_refreshChaseGuidanceIfNeeded());
    _refreshTrafficOfferState();
    _schedulePublish();
  }

  void _refreshTrafficOfferState() {
    final fingerprint = trafficIncidentFingerprint(_trafficRerouteHazards);
    if (fingerprint == _lastTrafficOfferFingerprint) return;
    _lastTrafficOfferFingerprint = fingerprint;
    if (mounted) setState(() {});
  }

  void _scheduleSimulationAwarenessUpdate() {
    if (_simulationAwarenessTimer != null) return;
    _simulationAwarenessTimer = Timer(const Duration(milliseconds: 250), () {
      _simulationAwarenessTimer = null;
      if (!mounted) return;
      // Simulation awareness maintains its own in-memory location evidence.
      // Local marker actions update RideController directly, so reloading and
      // decoding the entire durable ride history here is unnecessary.
      _updateMapOverlays(
        updateDerivedState: true,
        updateNavigationPosition: false,
      );
    });
  }

  void _updateMapOverlays({
    bool updateDerivedState = true,
    bool updateOverlayMarkers = true,
    bool updateNavigationPosition = true,
  }) {
    final awareness = _awarenessController;
    if (awareness == null) return;
    final balloonDeviceIds = _isSimulation
        ? const <String>{}
        : (widget.rideController
                  .resolveCraftRoster()
                  .balloon
                  ?.deviceIds
                  .toSet() ??
              const <String>{});
    // One reconciled model for both ride phases and both transports, so nobody
    // disappears at the `rideStarted` transition, a late joiner appears at once,
    // and the count can never disagree with the drawn markers (#132).
    final livePresence = _isSimulation
        ? const <LiveRiderPresence>[]
        : _reconciledLivePresence();
    if (!_isSimulation) _publishLivePresence(livePresence);
    final liveView = widget.rideController.liveView;
    final participants = {
      for (final participant in liveView.participants)
        participant.riderId: participant,
    };
    final freshnessByRider = {
      for (final presence in livePresence) presence.riderId: presence,
    };
    final visibleRiderLocations = _isSimulation
        // Ride Lab has an authenticated in-memory roster rather than relay
        // participants. Filtering its fixes through the empty real roster
        // made every virtual rider disappear from TEC and CarPlay status.
        ? List<RiderLocation>.unmodifiable(awareness.riderLocations)
        : liveView.renderedPositions;
    final activeRiderIds = _isSimulation
        ? visibleRiderLocations.map((location) => location.riderId).toSet()
        : participants.values
              .where((participant) => participant.isEligibleForRouteAlerts)
              .map((participant) => participant.riderId)
              .toSet();
    final localLocation = visibleRiderLocations
        .where(
          (location) =>
              location.riderId == widget.rideController.session?.localRiderId,
        )
        .firstOrNull;
    final simulatedRiders = _isSimulation
        ? _simulationController?.riders
        : null;
    final simulatedLocal = simulatedRiders
        ?.where((rider) => rider.isLocal)
        .firstOrNull;
    // The authoritative post-start location journal must not ingest a fix
    // captured before the leader started the ride. The map can still retain
    // that foreground-only fix while it waits for the first post-start
    // movement sample, otherwise a stationary rider disappears and Follow me
    // incorrectly looks like a permission failure.
    final activeDeviceSample = _isSimulation
        ? null
        : _locationController?.activeSample;
    final localMapSample = _newestLocationSample(
      localLocation?.sample,
      activeDeviceSample,
    );
    final mapPoint = simulatedLocal != null
        ? route_domain.GeoPoint(
            latitude: simulatedLocal.position.latitude,
            longitude: simulatedLocal.position.longitude,
            elevationMeters: localMapSample?.altitudeMeters,
            altitudeSource:
                localMapSample?.altitudeSource ?? AltitudeSource.unknown,
            altitudeDatum:
                localMapSample?.altitudeDatum ?? AltitudeDatum.unknown,
            altitudeAccuracyMeters: localMapSample?.altitudeAccuracyMeters,
            recordedAt: localMapSample?.recordedAt,
          )
        : localMapSample == null
        ? null
        : route_domain.GeoPoint(
            latitude: localMapSample.position.latitude,
            longitude: localMapSample.position.longitude,
            elevationMeters: localMapSample.altitudeMeters,
            altitudeSource: localMapSample.altitudeSource,
            altitudeDatum: localMapSample.altitudeDatum,
            altitudeAccuracyMeters: localMapSample.altitudeAccuracyMeters,
            recordedAt: localMapSample.recordedAt,
          );
    final navigationRecordedAt = simulatedLocal == null
        ? localMapSample?.recordedAt
        : DateTime.now();
    if (updateNavigationPosition) {
      // #419's pairing compares the app's bearings against the rider's own
      // track, so it needs this phone's fixes — and only this phone's. Other
      // riders' positions are someone else's data and are never recorded.
      if (mapPoint != null) {
        _diagnostics?.observePosition(
          point: awareness_geo.GeoPoint(
            latitude: mapPoint.latitude,
            longitude: mapPoint.longitude,
          ),
          headingDegrees:
              simulatedLocal?.headingDegrees ?? localMapSample?.headingDegrees,
        );
      }
      _mapNavigationPosition.value = mapPoint == null
          ? null
          : MapNavigationPosition(
              point: mapPoint,
              recordedAt: navigationRecordedAt!,
              speedMetersPerSecond:
                  simulatedLocal?.speedMetersPerSecond ??
                  localMapSample!.speedMetersPerSecond,
              headingDegrees:
                  simulatedLocal?.headingDegrees ??
                  localMapSample!.headingDegrees,
              accuracyMeters: localMapSample?.accuracyMeters,
              altitudeMeters: localMapSample?.altitudeMeters,
              altitudeSource:
                  localMapSample?.altitudeSource ?? AltitudeSource.unknown,
              altitudeDatum:
                  localMapSample?.altitudeDatum ?? AltitudeDatum.unknown,
              altitudeAccuracyMeters: localMapSample?.altitudeAccuracyMeters,
              verticalSpeedMetersPerSecond:
                  localMapSample?.verticalSpeedMetersPerSecond,
              altitudeRecordedAt: localMapSample?.recordedAt,
            );
      _mapPosition.value = mapPoint;
    }

    // A simulation can finish between throttled overlay frames. Completion
    // needs to inspect the final GPS fixes even when no later overlay frame is
    // scheduled to arrive.
    unawaited(_maybeAutomaticallyEndRide(awareness, mapPoint));
    if (!updateOverlayMarkers) return;
    if (_isSimulation) {
      _updateSimulationRiderTrails(simulatedRiders ?? const []);
    } else if (updateDerivedState) {
      _updateRiderTrails(awareness);
    }

    // Issue #151. Resolved before the markers are built, because the rider who
    // raised something is the rider whose marker has to say so.
    final quickMessagesBySender = _refreshQuickMessageAlerts(
      localLocation: localLocation,
      visibleRiderLocations: visibleRiderLocations,
      route: awareness.route,
    );
    // Issue #135. Judged once, here, so the MapLibre renderer and the
    // flutter_map fallback are handed the same decision rather than each
    // deciding for itself what is ahead and what a camera looks like (#141).
    final now = DateTime.now();
    final hazardJudgements = const HazardMapRelevance().judgeAll(
      reports: awareness.activeHazards,
      riderPosition: localLocation?.sample.position,
      headingDegrees: localLocation?.sample.headingDegrees,
      route: awareness.route,
      now: now,
    );
    final overlays = <MapOverlayMarker>[
      for (final judgement in hazardJudgements)
        if (judgement.isVisible) _hazardOverlayMarker(judgement.report, now),
      ...(simulatedRiders == null
              ? visibleRiderLocations
                    .where(
                      (location) => location.riderId != localLocation?.riderId,
                    )
                    .map(
                      (location) => (
                        riderId: location.riderId,
                        displayName: location.displayName,
                        role: location.role,
                        motorcycleStyle:
                            balloonDeviceIds.contains(location.riderId)
                            ? CraftIconStyle.balloon
                            : location.motorcycleStyle,
                        riderSymbol: location.riderSymbol,
                        riderColor: location.riderColor,
                        altitudeMeters: location.sample.altitudeMeters,
                        point: route_domain.GeoPoint(
                          latitude: location.sample.position.latitude,
                          longitude: location.sample.position.longitude,
                          recordedAt: location.sample.recordedAt,
                        ),
                      ),
                    )
              : simulatedRiders
                    .where((rider) => !rider.isLocal)
                    .map(
                      (rider) => (
                        riderId: rider.id,
                        displayName: rider.displayName,
                        role: rider.role,
                        motorcycleStyle: rider.role == RideRole.lead
                            ? CraftIconStyle.balloon
                            : rider.motorcycleStyle,
                        riderSymbol: rider.riderSymbol,
                        riderColor: rider.riderColor,
                        altitudeMeters: rider.altitudeMeters,
                        point: route_domain.GeoPoint(
                          latitude: rider.position.latitude,
                          longitude: rider.position.longitude,
                        ),
                      ),
                    ))
          .map((location) {
            final isLead = location.role == RideRole.lead;
            final isBalloonCraft = _isSimulation
                ? isLead
                : balloonDeviceIds.contains(location.riderId);
            // A position past its freshness threshold is demoted explicitly in
            // the label. The identity fill remains stable across surfaces.
            final freshness =
                freshnessByRider[location.riderId]?.freshness ??
                PresenceFreshness.live;
            final ageSuffix = switch (freshness) {
              PresenceFreshness.live => null,
              PresenceFreshness.none => PresenceFreshness.none.label,
              _ =>
                freshnessByRider[location.riderId]?.freshnessLabel ??
                    freshness.label,
            };
            // Issue #151's map companion, kept deliberately minimal: the rider
            // who raised something already has a marker, so it says what they
            // raised rather than inventing a second symbol beside it.
            final raised = quickMessagesBySender[location.riderId];
            final roleSuffix = raised != null
                ? raised.label
                : isBalloonCraft
                ? 'Balloon'
                : isLead
                ? 'Lead'
                : null;
            final label = [
              location.displayName,
              ?roleSuffix,
              if (isBalloonCraft && location.altitudeMeters != null)
                '${location.altitudeMeters!.round()} m',
              ?ageSuffix,
            ].join(' · ');
            // The roster, both maps and trails share this one identity colour.
            // Role is already named in [label]; changing the fill made one
            // rider look like different people across surfaces (#250).
            final baseColor = location.riderColor.color;
            return MapOverlayMarker(
              id: 'rider-${location.riderId}',
              point: location.point,
              label: label,
              motorcycleStyle: location.motorcycleStyle,
              riderSymbol: location.riderSymbol,
              riderDisplayName: location.displayName,
              color: baseColor,
            );
          }),
    ];
    _mapOverlays.value = List.unmodifiable(overlays);
    final previousEnforcementAlert = _enforcementAlert.value;
    _enforcementAlert.value = const EnforcementAlertDetector().detect(
      position: localLocation?.sample.position,
      headingDegrees: localLocation?.sample.headingDegrees,
      speedMetersPerSecond: localLocation?.sample.speedMetersPerSecond,
      activeHazardId: previousEnforcementAlert?.hazard.id,
      route: awareness.route,
      hazards: awareness.activeHazards,
      now: now,
    );
    // #418 asks whether the warning clears itself on passing. That is a
    // transition, not a state, so both edges are recorded.
    _recordEnforcementTransition(
      previous: previousEnforcementAlert,
      current: _enforcementAlert.value,
    );
    _speakEnforcementWarning(previousEnforcementAlert, _enforcementAlert.value);
    _publishCarPlaySnapshot(
      awareness: awareness,
      visibleRiderLocations: visibleRiderLocations,
      activeRiderIds: activeRiderIds,
    );
  }

  /// Projects the ride onto CarPlay, including the back-marker.
  ///
  /// The TEC is resolved through its own reducer
  /// rather than read off the rider list, for the same reason every other
  /// surface does: "nobody is TEC", "registered but never reported" and "last
  /// fix too old to trust" are three different answers and a car screen must
  /// not blur them into a missing row. [_leaderStatus] then adds the gap and
  /// the trend, and is null for everyone who is not the leader — that means
  /// this device has no gap to show, never that there is no TEC.
  /// Reads the bundled fixed-camera layer.
  ///
  /// Never throws at the caller. A build with the asset stripped, or a file
  /// that fails to parse, yields an empty catalogue: the provider then reports
  /// itself unavailable and the ride carries on with rider sightings alone.
  Future<FixedSpeedCameraCatalogue> _loadFixedSpeedCameras() async {
    final cached = _fixedSpeedCameras;
    if (cached != null) return cached;
    try {
      return _fixedSpeedCameras = await FixedSpeedCameraCatalogue.load();
    } on Object catch (error, stackTrace) {
      debugPrint('Fixed camera catalogue unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
      return _fixedSpeedCameras = FixedSpeedCameraCatalogue.empty;
    }
  }

  void _publishCarPlaySnapshot({
    required SituationalAwarenessController awareness,
    required List<RiderLocation> visibleRiderLocations,
    required Set<String> activeRiderIds,
  }) {
    final bridge = _carPlayBridge;
    if (bridge == null) return;
    final session = widget.rideController.session;
    final navigationRoute = _activeRoute;
    final routeProgress = _carPlayRouteProgressTracker.update(
      navigationRoute,
      _mapPosition.value,
    );
    final selectedBasemap = BasemapConfiguration.fromEnvironment()
        .forBrightness(
          dark: widget.mapStyleMode.resolveDark(
            MediaQuery.platformBrightnessOf(context),
          ),
          restrainedLightStyle:
              widget.mapStyleMode.dayStyle == DayMapStyle.restrained,
        );
    final navigationPosition = _mapNavigationPosition.value;
    final localSpeedIsAgeing =
        navigationPosition != null &&
        DateTime.now().difference(navigationPosition.recordedAt) >=
            const Duration(seconds: 3);
    final journeyProgress = widget.routeProgressDisplay?.enabled == false
        ? null
        : _carPlayJourneyProgressTracker.update(
            route: navigationRoute,
            geometry: routeProgress,
            speedMetersPerSecond: localSpeedIsAgeing
                ? null
                : navigationPosition?.speedMetersPerSecond,
            now: DateTime.now(),
          );
    unawaited(
      bridge.publish(
        session: session,
        riderLocations: visibleRiderLocations,
        activeHazards: awareness.activeHazards,
        route: navigationRoute,
        routeName: navigationRoute?.name,
        rideState: _projectedRideState,
        followRider:
            widget.rideController.rideStarted &&
            !widget.rideController.rideEnded,
        guidanceTitle: _projectedGuidanceTitle,
        guidanceDetail: _projectedGuidanceDetail,
        guidanceRoadName: _latestNavigationGuidance?.roadLabel,
        guidanceDistanceMeters: _latestNavigationGuidance?.distanceMeters,
        distanceUnit: widget.distanceUnits.value,
        groupStatus: '${visibleRiderLocations.length} crew visible',
        rideStart: _carPlayRideStart,
        surfaceMode: widget.rideController.rideEnded
            ? CarPlaySurfaceMode.endedRide
            : widget.rideController.rideStarted
            ? CarPlaySurfaceMode.activeRide
            : CarPlaySurfaceMode.preRide,
        canPlanRoute:
            widget.rideController.isLocalRideLeader &&
            !widget.rideController.rideStarted &&
            !widget.rideController.rideEnded &&
            !widget.rideController.busy,
        basemap: selectedBasemap,
        mapStyleJson: _carPlayMapStyleJson,
        localPosition: _mapPosition.value,
        localHeadingDegrees: navigationPosition?.headingDegrees,
        localSpeedMetersPerSecond: navigationPosition?.speedMetersPerSecond,
        localSpeedIsAgeing: localSpeedIsAgeing,
        speedLimitEnabled:
            widget.rideController.rideStarted &&
            !widget.rideController.rideEnded &&
            widget.speedLimitDisplay.enabled,
        speedLimitStatus: widget.speedLimitDisplay.status.name,
        speedLimitMilesPerHour: widget.speedLimitDisplay.limit?.milesPerHour,
        speedLimitUnlimited: widget.speedLimitDisplay.limit?.unlimited ?? false,
        routeProgress: routeProgress,
        journeyProgress: journeyProgress,
      ),
    );
  }

  Future<List<CarPlayDestination>> _searchCarPlayDestinations(
    String query,
  ) async {
    final controller = widget.rideController;
    if (!controller.isLocalRideLeader ||
        controller.rideStarted ||
        controller.rideEnded ||
        controller.busy) {
      throw const FormatException(
        'Only the pilot or coordinator can plan a route before the flight starts.',
      );
    }
    return [
      for (final match in await _carPlayDestinationPlanner.searchService.search(
        query,
      ))
        CarPlayDestination(label: match.label, point: match.point),
    ];
  }

  Future<void> _planCarPlayDestination(
    CarPlayDestination destination,
    bool? groupRide,
  ) async {
    final controller = widget.rideController;
    if (!controller.isLocalRideLeader ||
        controller.rideStarted ||
        controller.rideEnded ||
        controller.busy) {
      throw const FormatException(
        'Only the pilot or coordinator can plan a route before the flight starts.',
      );
    }
    final origin = _mapPosition.value ?? await _acquireCurrentPosition();
    if (origin == null) {
      throw const FormatException(
        'Allow location access on the iPhone before planning from CarPlay.',
      );
    }
    final plan = await _carPlayDestinationPlanner.planForReview(
      origin: origin,
      query: destination.label,
      selectedDestination: DestinationMatch(
        label: destination.label,
        point: destination.point,
      ),
      distanceUnit: widget.distanceUnits.value,
    );
    await _handleRouteChanged(plan.route);
    if (mounted) _updateMapOverlays(updateDerivedState: false);
  }

  /// Publishes the quick messages the ride map has to present, and returns the
  /// most urgent one per sender so their marker can say what they raised.
  ///
  /// The reducer decides what is admissible; this decides what is still *this
  /// rider's* to act on, and works out where each sender is. Two position
  /// sources, in that order:
  ///
  /// * the sender's live fix, when they are still reporting one — where they are
  ///   now is what a leader turning round needs;
  /// * otherwise the fix relayed with the message, which is where they were when
  ///   they raised it. A rider stopped for fuel is not moving, and their location
  ///   events age out of the 30-minute band long before the message does.
  Map<String, ReceivedQuickMessage> _refreshQuickMessageAlerts({
    required RiderLocation? localLocation,
    required List<RiderLocation> visibleRiderLocations,
    required List<awareness_geo.GeoPoint> route,
  }) {
    final localRiderId = widget.rideController.session?.localRiderId;
    if (localRiderId == null) {
      _quickMessageAlerts.value = const [];
      return const {};
    }
    final presented = presentableQuickMessageAlerts(
      messages: widget.rideController.quickMessages,
      localRiderId: localRiderId,
      readerPosition: localLocation?.sample.position,
      livePositions: {
        for (final location in visibleRiderLocations)
          location.riderId: location.sample.position,
      },
      route: route,
    );
    _quickMessageAlerts.value = presented.alerts;
    return presented.bySender;
  }

  /// Acknowledges the presented message *and* every repeat it stands for, so a
  /// rider who cancels a `Stopped` is not asked again about the two identical
  /// ones behind it (#178).
  Future<void> _acknowledgeQuickMessage(ReceivedQuickMessage message) async {
    final alert = _quickMessageAlerts.value
        .where((candidate) => candidate.message.eventId == message.eventId)
        .firstOrNull;
    for (final outstanding in alert?.acknowledgeable ?? [message]) {
      await widget.rideController.acknowledgeQuickMessage(outstanding);
    }
    _updateMapOverlays(updateNavigationPosition: false);
  }

  Future<void> _maybeAutomaticallyEndRide(
    SituationalAwarenessController awareness,
    route_domain.GeoPoint? localPosition,
  ) async {
    if (_autoEndingRide ||
        !widget.rideController.rideStarted ||
        widget.rideController.rideEnded ||
        widget.rideController.ridePaused) {
      return;
    }
    final session = widget.rideController.session;
    // A real ride remains leader-owned. Ride Lab drives the entire virtual
    // group locally, so completion must work from its leader, follower and TEC
    // perspectives alike.
    if (session == null ||
        (!_isSimulation && !widget.rideController.hasFlightAuthority)) {
      return;
    }
    final route = _activeRoute;
    final destination = _routeDestination(route);
    if (destination == null) return;
    // Monotonic progress along the plan, not proximity to its last point. On a
    // loop the two are the same thing at the start line (#206).
    final progress = _completionProgressTracker.update(route, localPosition);
    final assessment = _rideCompletionDetector.assess(
      destination: awareness_geo.GeoPoint(
        latitude: destination.latitude,
        longitude: destination.longitude,
      ),
      riderLocations: awareness.riderLocations,
      now: DateTime.now(),
      routeProgressFraction: progress.totalMeters <= 0
          ? 0
          : progress.progressMeters / progress.totalMeters,
    );
    if (!assessment.ready) {
      _completionPromptedForArrival = false;
      _rideCompletionSuggestion.value = null;
      return;
    }
    // A dismissed suggestion stays dismissed while the group remains inside
    // the destination radius. Leaving and returning arms a fresh suggestion.
    if (_completionPromptedForArrival) return;
    _completionPromptedForArrival = true;
    // Offered, not imposed: the rider keeps the map and the guidance, and acts
    // on this when they are ready. Nothing is awaited here, so arrival no
    // longer holds the ride open behind a barrier.
    _rideCompletionSuggestion.value = assessment;
  }

  /// The rider waved the suggestion away.
  ///
  /// It stays away while the group remains inside the destination radius, which
  /// `_completionPromptedForArrival` already tracks; leaving and returning arms
  /// a fresh one, exactly as the modal behaved.
  void _dismissRideCompletionSuggestion() =>
      _rideCompletionSuggestion.value = null;

  /// The rider chose to end it for the group.
  ///
  /// Ending for everyone is irreversible for the group, so the confirmation
  /// carrying `endRideConsequence` stays. #380 was about the suggestion not
  /// blocking, not about removing the consequence.
  Future<void> _endRideFromCompletionSuggestion() async {
    if (_autoEndingRide) return;
    _autoEndingRide = true;
    try {
      if (!mounted) return;
      final decision = await showRideCompletionDialog(
        context,
        assessment: _rideCompletionSuggestion.value ?? _emptyAssessment,
        relayCanCarryReopen: _relayCanCarryReopen,
      );
      if (decision == RideCompletionDecision.endForEveryone) {
        _rideCompletionSuggestion.value = null;
        await widget.rideController.endRide();
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Could not end the completed ride: $error\n$stackTrace');
      }
    } finally {
      _autoEndingRide = false;
    }
  }

  static const _emptyAssessment = RideCompletionAssessment(
    routeProgressFraction: 0,
    minimumRouteProgressFraction: 0,
    destinationRadiusMeters: 0,
    riderCount: 0,
    freshRiderCount: 0,
    arrivedRiderCount: 0,
  );

  static route_domain.GeoPoint? _routeDestination(
    route_domain.ImportedRoute? route,
  ) {
    if (route == null) return null;
    for (final path in route.paths.reversed) {
      if (path.points.isNotEmpty) return path.points.last;
    }
    return route.waypoints.isEmpty ? null : route.waypoints.last.point;
  }

  /// Ride Lab drives the same trail model as a real ride, so the simulator can
  /// no longer show a leader track the live path never builds (#100).
  void _updateSimulationRiderTrails(List<SimulatedRiderSnapshot> riders) {
    final balloonSamples =
        _awarenessController?.leaderLocationSamples ?? const <LocationSample>[];
    _publishRiderTrails([
      for (final rider in riders)
        RiderTrail(
          riderId: rider.id,
          displayName: rider.displayName,
          kind: rider.role == RideRole.lead
              ? RiderTrailKind.balloonGroundTrack
              : RiderTrailKind.rider,
          // The balloon uses its authenticated emitted fixes rather than the
          // chase route's synthetic display trail. Besides showing where it
          // really drifted, this retains altitude metadata for the map.
          points: _trailRecorder.boundedTrail(
            rider.role == RideRole.lead
                ? _locationSamplePoints(balloonSamples)
                : _routePoints(rider.travelTrail),
          ),
        ),
    ]);
  }

  /// Records and publishes every eligible rider's travelled trail from position
  /// history alone.
  ///
  /// Route matching decides route progress and alerts; it never decides whether
  /// a trail is drawn. The leader's trail also draws on the awareness
  /// controller's leader history, which is rebuilt from the durable journal on
  /// restart, so it survives an app restart mid-ride as far as the journal
  /// allows.
  void _updateRiderTrails(SituationalAwarenessController awareness) {
    if (!widget.rideController.rideStarted) {
      _trailRecorder.clear();
      _publishRiderTrails(const []);
      return;
    }
    final balloonDeviceIds =
        widget.rideController.resolveCraftRoster().balloon?.deviceIds.toSet() ??
        const <String>{};
    _publishRiderTrails(
      _trailRecorder.update([
        for (final location in awareness.riderLocations)
          RiderTrailUpdate(
            riderId: location.riderId,
            displayName: location.displayName,
            position: route_domain.GeoPoint(
              latitude: location.sample.position.latitude,
              longitude: location.sample.position.longitude,
              elevationMeters: location.sample.altitudeMeters,
              altitudeSource: location.sample.altitudeSource,
              altitudeDatum: location.sample.altitudeDatum,
              altitudeAccuracyMeters: location.sample.altitudeAccuracyMeters,
              recordedAt: location.sample.recordedAt,
            ),
            isLeader: location.role == RideRole.lead,
            isBalloon: balloonDeviceIds.contains(location.riderId),
            isEligible:
                widget.rideController
                    .participantFor(location.riderId)
                    ?.isEligibleForLivePosition ==
                true,
            journalTrail: location.role == RideRole.lead
                ? [
                    for (final sample in awareness.leaderLocationSamples)
                      route_domain.GeoPoint(
                        latitude: sample.position.latitude,
                        longitude: sample.position.longitude,
                        elevationMeters: sample.altitudeMeters,
                        altitudeSource: sample.altitudeSource,
                        altitudeDatum: sample.altitudeDatum,
                        altitudeAccuracyMeters: sample.altitudeAccuracyMeters,
                        recordedAt: sample.recordedAt,
                      ),
                  ]
                : null,
          ),
      ]),
    );
  }

  static List<route_domain.GeoPoint> _routePoints(
    List<awareness_geo.GeoPoint> points,
  ) => [
    for (final point in points)
      route_domain.GeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
  ];

  static List<route_domain.GeoPoint> _locationSamplePoints(
    Iterable<LocationSample> samples,
  ) => [
    for (final sample in samples)
      route_domain.GeoPoint(
        latitude: sample.position.latitude,
        longitude: sample.position.longitude,
        elevationMeters: sample.altitudeMeters,
        altitudeSource: sample.altitudeSource,
        altitudeDatum: sample.altitudeDatum,
        altitudeAccuracyMeters: sample.altitudeAccuracyMeters,
        recordedAt: sample.recordedAt,
      ),
  ];

  void _publishRiderTrails(List<RiderTrail> trails) {
    _recordedTrailTraces = List.unmodifiable([
      for (final trail in trails.where((trail) => trail.isRenderable))
        for (final (index, points)
            in _trailRecorder
                .continuousSegments(trail.points)
                .where((segment) => segment.length >= 2)
                .indexed)
          MapOverlayTrace(
            id: index == 0
                ? 'trail-${trail.riderId}'
                : 'trail-${trail.riderId}-$index',
            points: points,
            label: switch (trail.kind) {
              RiderTrailKind.leader => '${trail.displayName} leader trail',
              RiderTrailKind.balloonGroundTrack =>
                '${trail.displayName} balloon ground track',
              RiderTrailKind.forecastTrack =>
                '${trail.displayName} flight forecast',
              RiderTrailKind.rider => '${trail.displayName} trail',
              RiderTrailKind.operationalBoundary =>
                '${trail.displayName} operational boundary',
              // RiderTrailRecorder only records where riders have been, so it
              // never produces a route-start connector; the map composes that
              // one itself.
              RiderTrailKind.routeStartConnector =>
                '${trail.displayName} route to start',
            },
            kind: trail.kind,
          ),
    ]);
    _pushRiderTrails();
  }

  /// Every trace is simplified for display here, once per change, rather than
  /// in a renderer or on every frame: this is the single point both map
  /// implementations read from, so the bound cannot apply to only one of them
  /// (#165).
  void _pushRiderTrails() {
    _riderTrails.value = List.unmodifiable([
      for (final trace in _recordedTrailTraces) _simplifiedForDisplay(trace),
      ..._sharedForecastTraces,
      ..._operationalBoundaryTraces,
    ]);
  }

  List<MapOverlayTrace> get _sharedForecastTraces {
    final plan = _liveRoutes.sharedFlightPlan;
    if (_isSimulation || plan == null) return const [];
    return [
      for (final (index, path) in plan.paths.indexed)
        if (path.points.length >= 2)
          MapOverlayTrace(
            id: 'shared-flight-forecast-$index',
            points: _trailSimplifier.simplify(path.points),
            label: path.name ?? '${plan.name} shared flight forecast',
            kind: RiderTrailKind.forecastTrack,
          ),
    ];
  }

  MapOverlayTrace _simplifiedForDisplay(MapOverlayTrace trace) {
    final simplified =
        (trace.kind == RiderTrailKind.balloonGroundTrack ||
                    trace.kind == RiderTrailKind.forecastTrack
                ? _balloonTrailSimplifier
                : _trailSimplifier)
            .simplify(trace.points);
    if (simplified.length == trace.points.length) return trace;
    return MapOverlayTrace(
      id: trace.id,
      points: simplified,
      label: trace.label,
      kind: trace.kind,
    );
  }

  /// One reported hazard as a map marker (#135).
  ///
  /// The symbol - shape, glyph, fill, freshness - is resolved here and travels
  /// on the marker, so both renderers draw the same thing and the tap text is
  /// the same sentence in both.
  static MapOverlayMarker _hazardOverlayMarker(
    HazardReport report,
    DateTime now,
  ) {
    final symbol = HazardMapSymbols.forReport(report, now: now);
    return MapOverlayMarker(
      id: 'hazard-${report.id}',
      point: route_domain.GeoPoint(
        latitude: report.position.latitude,
        longitude: report.position.longitude,
      ),
      label: HazardMapSymbols.describe(report, now: now),
      color: symbol.fill,
      hazardSymbol: symbol,
    );
  }

  /// The route Ride Lab flies, as awareness points: the densest path in the
  /// file, so a GPX carrying both a calculated track and its sparse waypoint
  /// route drives the simulation from the detailed one.
  static List<awareness_geo.GeoPoint> _simulationRoutePoints(
    route_domain.ImportedRoute? route,
  ) {
    if (route == null || route.paths.isEmpty) return const [];
    final longestPath = route.paths.reduce(
      (current, candidate) =>
          candidate.points.length > current.points.length ? candidate : current,
    );
    return longestPath.points
        .map(
          (point) => awareness_geo.GeoPoint(
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        )
        .toList(growable: false);
  }

  static WindForecastField _bundledWindForecast(BalloonFlight flight) {
    final vectors = [
      for (final layer in flight.windLayers)
        WindForecastVector(
          altitudeMetersMsl: flight.launchElevationMetres + layer.heightMetres,
          fromDegrees: layer.fromDegrees,
          speedKmh: layer.speedKmh,
        ),
    ];
    final sourceTime = DateTime.utc(2026, 8, 8, 6);
    return WindForecastField(
      columns: [
        for (final point in windForecastGrid(flight.launch))
          WindForecastColumn(position: point, vectors: vectors),
      ],
      validAt: sourceTime,
      fetchedAt: sourceTime,
      origin: WindForecastOrigin.bundledFallback,
      sourceLabel: 'Bundled Open-Meteo rehearsal wind',
    );
  }

  void _onWindForecastChanged() {
    final field = _windForecastController?.field;
    if (field == null ||
        !widget.rideController.isLocalRideLeader ||
        !widget.rideController.rideStarted ||
        widget.rideController.rideEnded ||
        field.columns.isEmpty) {
      return;
    }
    final fingerprint =
        '${field.origin.name}:${field.validAt.toUtc().toIso8601String()}:'
        '${field.fetchedAt.toUtc().toIso8601String()}';
    if (fingerprint == _recordedWindContextFingerprint) return;
    _recordedWindContextFingerprint = fingerprint;
    final current = _mapPosition.value;
    final column = current == null
        ? field.columns.first
        : field.columns.reduce(
            (first, second) =>
                GeoCalculations.distanceMeters(
                      first.position,
                      awareness_geo.GeoPoint(
                        latitude: current.latitude,
                        longitude: current.longitude,
                      ),
                    ) <=
                    GeoCalculations.distanceMeters(
                      second.position,
                      awareness_geo.GeoPoint(
                        latitude: current.latitude,
                        longitude: current.longitude,
                      ),
                    )
                ? first
                : second,
          );
    unawaited(
      widget.rideController.noteWindContext(
        FlightReplayWindContext(
          recordedAt: DateTime.now(),
          validAt: field.validAt,
          source: field.sourceLabel,
          // Both live Open-Meteo and the bundled Fiesta field are model output.
          isForecast: true,
          position: column.position,
          vectors: [
            for (final vector in column.vectors)
              FlightReplayWindVector(
                altitudeMetersMsl: vector.altitudeMetersMsl,
                fromDegrees: vector.fromDegrees,
                speedKmh: vector.speedKmh,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onReceivedEvent(
    RideEvent event,
    RideTransportEvidence transport,
  ) async {
    widget.rideController.noteTransportObservation(event.id, transport);
    if (_isSituationalEvent(event.type)) {
      final awareness = _awarenessController;
      if (awareness == null) {
        widget.rideController.ingestStoredEvent(event);
        return;
      }
      try {
        await awareness.ingestRemoteEvent(event);
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
            'Rejected received situational event: $error\n$stackTrace',
          );
        }
      }
    } else {
      widget.rideController.ingestStoredEvent(event);
    }
  }

  static bool _isSituationalEvent(RideEventType type) => switch (type) {
    RideEventType.riderLocationUpdated ||
    RideEventType.hazardReported ||
    RideEventType.hazardCleared => true,
    _ => false,
  };

  void _onRideControllerChanged() {
    _syncSharedLandingZone();
    _syncOperationalBoundaries();
    if (_isChaserPerspective && _chaseGuidanceTarget == null) {
      _chaseGuidanceTarget = widget.rideController.landingZone == null
          ? ChaseGuidanceTarget.balloon
          : ChaseGuidanceTarget.landingArea;
    }
    final session = widget.rideController.session;
    final rideStarted =
        widget.rideController.rideStarted && !widget.rideController.rideEnded;
    final rideJustStarted = rideStarted && !_observedRideStarted;
    _observedRideStarted = rideStarted;
    // The journal only accepts fixes from the start onwards, so the first fix
    // after the start has nothing to be measured against and must report
    // whatever the rider has or has not moved since.
    if (rideJustStarted) _positionReportGate.reset();
    if (rideJustStarted) unawaited(_warmNaturalVoiceIfNeeded());
    if (rideJustStarted) _onWindForecastChanged();
    if (session != null) {
      _awarenessController?.updateLocalSession(session);
      _observerAccessController?.updateSession(session);
      _updateMapOverlays();
      unawaited(_synchroniseRideControllers());
      if (rideJustStarted && !_localRideStartInProgress) {
        unawaited(_resumeLocationForActiveRide());
      }
      if (_lastPushRole != session.role) {
        _lastPushRole = session.role;
        unawaited(_pushNotificationController?.refreshRegistration());
      }
      _publishObserverSnapshot();
      unawaited(_refreshChaseGuidanceIfNeeded());
    }
    if (widget.rideController.rideEnded && !_rideEndHandled) {
      unawaited(_handleRideEnded());
    }
    _schedulePublish();
  }

  void _syncSharedLandingZone() {
    final target = widget.rideController.landingZone;
    if (target == null) {
      if (_sharedLandingZone.value != null) _sharedLandingZone.value = null;
      return;
    }
    _landingRadiusMeters = target.radiusMeters;
    final previous = _sharedLandingZone.value;
    if (previous != null &&
        previous.center.latitude == target.center.latitude &&
        previous.center.longitude == target.center.longitude &&
        previous.radiusMeters == target.radiusMeters &&
        previous.label == target.label) {
      return;
    }
    _sharedLandingZone.value = MapLandingZone(
      center: route_domain.GeoPoint(
        latitude: target.center.latitude,
        longitude: target.center.longitude,
      ),
      radiusMeters: target.radiusMeters,
      label: target.label,
    );
  }

  void _syncOperationalBoundaries() {
    final draft = _operationalBoundaryDraft;
    _operationalBoundaryTraces = List.unmodifiable([
      for (final boundary in widget.rideController.operationalBoundaries)
        if (boundary.kind != OperationalBoundaryKind.altitudeBand)
          MapOverlayTrace(
            id: 'operational-boundary-${boundary.id}',
            points: [
              for (final point in boundary.points)
                route_domain.GeoPoint(
                  latitude: point.latitude,
                  longitude: point.longitude,
                ),
              if (boundary.kind == OperationalBoundaryKind.area)
                route_domain.GeoPoint(
                  latitude: boundary.points.first.latitude,
                  longitude: boundary.points.first.longitude,
                ),
            ],
            label: '${boundary.label} · advisory · ${boundary.source}',
            kind: RiderTrailKind.operationalBoundary,
          ),
      if (draft != null && draft.points.length >= 2)
        MapOverlayTrace(
          id: 'operational-boundary-draft',
          points: [
            ...draft.points,
            if (draft.kind == OperationalBoundaryKind.area &&
                draft.points.length >= 3)
              draft.points.first,
          ],
          label: '${draft.label} draft',
          kind: RiderTrailKind.operationalBoundary,
        ),
    ]);
    _pushRiderTrails();
  }

  /// Starts location for the map before the ride does, so a rider can see
  /// themselves while the group is still gathering (#300).
  ///
  /// Location used to start only once the ride had, which left the pre-start map
  /// with no own position and no way to get one - reported as "before I started
  /// a ride I couldn't see my own position and there was no way to get it".
  /// Gathering is exactly when a group is checking who has arrived and where
  /// they are.
  ///
  /// **Starting the stream does not start recording.** Fixes reach the map
  /// through `_onDeviceLocationChanged`, which only redraws overlays;
  /// `SituationalAwarenessController.recordLocalLocation` refuses every sample
  /// until `rideStarted`, and relay publishing is driven by the event journal
  /// rather than by fixes. So nothing is journalled or shared before Start ride,
  /// which is the half of the request that must not be broken.
  ///
  /// Deliberately not [_resumeLocationForActiveRide]: that resets the
  /// position-report gate, which paces *sharing*, and there is nothing to pace
  /// yet. A failure here is also silent rather than a warning banner - #262 asks
  /// for a calmer pre-start screen, and Follow me still surfaces a genuine
  /// permission problem when the rider asks for it.
  Future<void> _startLocationForPreStartMap() async {
    final locationController = _locationController;
    if (locationController == null ||
        widget.rideController.rideStarted ||
        widget.rideController.rideEnded) {
      return;
    }
    try {
      await locationController.resumeIfAuthorized();
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Could not start GPS before the ride: $error\n$stackTrace');
      }
    }
  }

  Future<void> _resumeLocationForActiveRide() async {
    final locationController = _locationController;
    if (locationController == null ||
        !widget.rideController.rideStarted ||
        widget.rideController.rideEnded) {
      return;
    }
    // The gap since the last report is not travel, so the next fix reports
    // unconditionally rather than being measured against wherever this rider was
    // when sharing last stopped.
    _positionReportGate.reset();
    try {
      await locationController.resumeIfAuthorized();
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Could not resume live GPS: $error\n$stackTrace');
      }
      final added = _warnings.add(
        'Live GPS could not resume automatically. Use Follow me or Safety '
        'to try again.',
      );
      if (added && mounted) setState(() {});
    }
  }

  Future<void> _synchroniseRideControllers() async {
    await _replaceAwarenessController(_activeRoute);
    if (!mounted) return;
    if (_isSimulation) {
      await _replaceSimulationController(_activeRoute);
    } else {
      await _applyAuthoritativeRouteDecision();
    }
    _applyRidePauseState();
  }

  void _applyRidePauseState() {
    if (!_isSimulation) return;
    final simulation = _simulationController;
    if (simulation == null) return;
    final rideStarted =
        widget.rideController.rideStarted && !widget.rideController.rideEnded;
    final simulationHadStarted = simulation.rideStarted;
    simulation.setRideStarted(rideStarted);
    if (!rideStarted) {
      _simulationPausedByRide = false;
      return;
    }
    if (widget.rideController.ridePaused) {
      if (simulation.isRunning) {
        simulation.pause();
        _simulationPausedByRide = true;
      }
      return;
    }
    if (!simulationHadStarted || _simulationPausedByRide) {
      _simulationPausedByRide = false;
      simulation.start();
    }
  }

  Future<void> _handleRideEnded() async {
    if (_rideEndHandled) return;
    _rideEndHandled = true;
    _stalenessTimer?.cancel();
    _externalHazardTimer?.cancel();
    _simulationAwarenessTimer?.cancel();
    _stalenessTimer = null;
    _externalHazardTimer = null;
    await _preStartPresenceController?.stop();
    await _pushNotificationController?.stop();
    await _locationController?.stop();
  }

  /// Hands the reconciled presence to the one model every surface reads, along
  /// with whether this device can receive positions at all — so a missing marker
  /// is attributed to the transport rather than silently to the rider.
  void _publishLivePresence(List<LiveRiderPresence> presence) {
    widget.rideController.observeLivePresence(
      presence,
      // The roster still names the riders who have left, which is how their
      // record survives a departure even if their membership events never
      // reached this phone's journal (#144). It adds nobody to the live count.
      roster: _preStartPresenceController?.roster ?? const [],
      positionChannelUnavailable:
          _preStartPresenceController?.unavailableReason != null,
    );
  }

  void _onPreStartPresenceChanged() {
    if (!mounted) return;
    // Presence is the channel that does not depend on the bulk event batch, so
    // it is what tells the roster a rider has joined.
    _publishLivePresence(_reconciledLivePresence());
    // A capability refusal, a rejected credential or an older peer used to turn
    // live positions off with no visible reason at all.
    var changed = false;
    for (final limitation
        in _preStartPresenceController?.limitations ?? const []) {
      if (_warnings.add(limitation.message)) changed = true;
    }
    _updateMapOverlays();
    if (changed && mounted) setState(() {});
  }

  /// One reconciled live-position model: the durable journal, the internet
  /// presence channel, the nearby presence channel and the relay's
  /// cursor-independent roster, merged newest-sample-wins.
  List<LiveRiderPresence> _reconciledLivePresence() {
    final session = widget.rideController.session;
    if (session == null || _isSimulation) return const [];
    final presence = _preStartPresenceController;
    return const LivePresenceReconciler().reconcile(
      now: DateTime.now(),
      localRiderId: session.localRiderId,
      journal: _awarenessController?.riderLocations ?? const [],
      internetPresence: presence?.internetLocations ?? const [],
      nearbyPresence: presence?.nearbyLocations ?? const [],
      roster: presence?.roster ?? const [],
      // A peer's position is aged on the relay's clock, not this phone's.
      relayClockOffset: presence?.relayClockOffset ?? Duration.zero,
    );
  }

  void _onDeviceLocationChanged() {
    if (!mounted) return;
    final status = _locationController?.status;
    final warningChanged =
        status != null && status.canSample && !status.backgroundCapable
        ? _warnings.add(_backgroundLocationWarning)
        : _warnings.remove(_backgroundLocationWarning);
    // The foreground map follows the newest device fix even if writing that
    // sample to the durable ride journal is briefly delayed or fails. Only
    // the journal feeds trails, summaries and GPX recording.
    _updateMapOverlays(updateDerivedState: false, updateOverlayMarkers: false);
    _checkOperationalBoundaries();
    final point = _mapPosition.value;
    final wind = _windForecastController;
    if (point != null && wind != null) {
      unawaited(
        wind.refresh(
          awareness_geo.GeoPoint(
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        ),
      );
    }
    unawaited(_refreshChaseGuidanceIfNeeded());
    if (warningChanged) setState(() {});
  }

  void _checkOperationalBoundaries() {
    final navigation = _mapNavigationPosition.value;
    if (navigation == null) return;
    final alerts = _operationalBoundaryMonitor.evaluate(
      boundaries: widget.rideController.operationalBoundaries,
      position: awareness_geo.GeoPoint(
        latitude: navigation.point.latitude,
        longitude: navigation.point.longitude,
      ),
      now: DateTime.now(),
      altitudeMeters: navigation.altitudeMeters,
      altitudeDatum: navigation.altitudeDatum,
    );
    if (alerts.isEmpty || !mounted) return;
    for (final alert in alerts) {
      _warnings.add(
        '${alert.message}. Advisory only — confirm the source and current flight information.',
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${alerts.first.message}. Advisory only; verify before acting.',
        ),
        backgroundColor: const Color(0xFF8F2638),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Leaving the foreground is the last certain moment before the process may
      // be reclaimed, so the log is written out here rather than trusted to a
      // tidy end-of-ride that may never arrive (#456).
      unawaited(_diagnosticsWriter?.flush());
      return;
    }
    unawaited(_locationController?.restartAfterForegroundResume());
  }

  void _schedulePublish() {
    final eventCount = widget.rideController.eventCount;
    if (eventCount != _observedNearbyPublishEventCount) {
      _observedNearbyPublishEventCount = eventCount;
      _nearbyPublishWorkPending = true;
    }
    if (!_nearbyPublishWorkPending || _nearbyPublishInFlight) return;
    _nearbyPublishWorkPending = false;
    _nearbyPublishInFlight = true;
    unawaited(() async {
      var retryNeeded = false;
      try {
        retryNeeded = await _publishPendingEvents();
      } finally {
        _nearbyPublishInFlight = false;
        if (retryNeeded) {
          // A later controller or transport notification retries it. Do not
          // spin immediately against an unavailable radio.
          _nearbyPublishWorkPending = true;
        } else if (_nearbyPublishWorkPending) {
          // An event arrived while the scan was running.
          _schedulePublish();
        }
      }
    }());
  }

  /// Returns true when at least one event could not be handed to Nearby.
  Future<bool> _publishPendingEvents() async {
    _internetRelayController?.wake();
    final relay = _relayController;
    final session = widget.rideController.session;
    if (!_relayConfigured || relay == null || session == null) return false;
    var retryNeeded = false;
    // RideController is updated one event at a time as the shared store is
    // written. Walking that in-memory view avoids querying and JSON-decoding
    // the complete SQLite ride on every new position (#165).
    for (final event in widget.rideController.events) {
      if (_publishedEventIds.contains(event.id)) continue;
      try {
        // Bounded, because this is an await on a transport from a chain that a
        // rejoin and a cold start both walk over the whole eligible backlog. A
        // publish that never returns would stall every later event behind it for
        // as long as the app is running, and a phone in that state is
        // indistinguishable from a hung app (#209).
        await relay
            .publish(event)
            .timeout(
              _nearbyPublishTimeout,
              onTimeout: () {
                throw TimeoutException('nearby publish', _nearbyPublishTimeout);
              },
            );
        _publishedEventIds.add(event.id);
      } on Object catch (error) {
        retryNeeded = true;
        if (kDebugMode) {
          debugPrint('Could not queue ${event.id} for nearby relay: $error');
        }
      }
    }
    return retryNeeded;
  }

  /// One nearby publish is a local hand-off to the transport, not a round trip,
  /// so seconds are already generous. The number exists to make "never" and
  /// "slow" different outcomes.
  static const _nearbyPublishTimeout = Duration(seconds: 5);

  @override
  Widget build(BuildContext context) {
    if (widget.rideController.rideEnded) {
      return EndedRideScreen(
        controller: widget.rideController,
        distanceUnits: widget.distanceUnits,
        nearbyRelayController: _relayController,
        internetRelayController: _internetRelayController,
        onRemoveRide: _removeEndedRide,
        relayCanCarryReopen: _relayCanCarryReopen,
        // The share on this screen omitted the recorded log entirely, so a rider
        // who ended the ride and pressed the obvious button lost it (#456).
        diagnostics: _endedRideDiagnostics,
      );
    }
    final selectedBody = _isSimulation
        ? switch (_selectedIndex) {
            0 => _buildMap(),
            1 => _buildSimulation(),
            2 => _buildDetails(),
            _ => _buildSettings(),
          }
        : switch (_selectedIndex) {
            0 => _buildMap(),
            1 => _buildDetails(),
            _ => _buildSettings(),
          };
    final session = widget.rideController.session!;
    final body = widget.rideController.rideStarted
        ? selectedBody
        : Column(
            children: [
              _PreStartRidePanel(
                rideCode: session.rideCode,
                // Who is here, not who has been here: the waiting-to-start
                // lobby is a live list, and a rider who has left keeps their
                // record in the ride roster instead (#144).
                participants: widget.rideController.liveParticipants,
                coordinationMode: widget.rideController.coordinationMode,
                isLeader: widget.rideController.hasFlightAuthority,
                busy: widget.rideController.busy || _loading,
                routeName: _activeRoute?.name,
                onStartRide: _confirmStartRide,
                onChooseRoute: _requestRouteChange,
                onJoinGroup: widget.onJoinGroupRequested == null
                    ? null
                    : _joinGroupBeforeStart,
              ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: selectedBody,
                ),
              ),
            ],
          );

    return ValueListenableBuilder<MapNavigationPosition?>(
      valueListenable: _mapNavigationPosition,
      builder: (context, navigationPosition, _) {
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        // The native map flashes when a bottom bar is repeatedly inserted as
        // GPS speed dips at lights. Once there is a navigation fix, preserve
        // the map viewport until the rider deliberately leaves the map tab.
        final hideWhileMoving =
            widget.rideController.rideStarted &&
            session.flightRole == FlightRole.chaseDriver &&
            _selectedIndex == 0 &&
            _activeRoute != null &&
            navigationPosition != null;
        final destinations = [
          for (final destination in _rideDestinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ];
        // Whatever hides the navigation also has to offer the way back, and it
        // has to be this shell that does: the map cannot be relied on for it.
        // It renders a spinner until its style loads, and a rider whose bar is
        // already gone would have nothing at all until that finished — which is
        // exactly the state a widget test lands in, and the state a slow phone
        // lands in on a cold start.
        final ridingBody = hideWhileMoving
            ? Stack(
                children: [
                  Positioned.fill(child: body),
                  // The one thing #133 puts in the upper leading corner, in the
                  // same place, so a rider reaches for it where the ride menu
                  // has always been.
                  Positioned(
                    left: 12,
                    top:
                        MediaQuery.paddingOf(context).top +
                        (landscape ? 12 : portraitRideMenuTopOffset),
                    child: FloatingActionButton.small(
                      key: const Key('ride-menu-button'),
                      heroTag: 'balloon-crumbs-shell-menu',
                      tooltip: 'Flight actions',
                      onPressed: _openRideMenu,
                      backgroundColor: const Color(0xE6252E39),
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.menu),
                    ),
                  ),
                ],
              )
            : body;
        if (landscape && !hideWhileMoving) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    key: const Key('landscape-navigation-rail'),
                    // Wider than the 56 it was, to carry the words. Same
                    // reasoning as the portrait bar: this rail is hidden while
                    // the rider is moving, so its cost is paid only at a
                    // standstill, and four unlabelled icons are what #306 is
                    // about.
                    minWidth: 72,
                    groupAlignment: -0.7,
                    labelType: NavigationRailLabelType.all,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) =>
                        setState(() => _selectedIndex = index),
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: destination.icon,
                          selectedIcon: destination.selectedIcon,
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          // Both orientations arrive here when the chrome is hidden: the
          // landscape rail above is only taken while it is showing.
          body: ridingBody,
          bottomNavigationBar: hideWhileMoving
              ? null
              : NavigationBar(
                  height: landscape ? 60 : 68,
                  // Named, not four bare icons.
                  //
                  // #306: "no feature reachable only through an unlabelled
                  // icon", after a shipped feature was concluded missing
                  // because its only affordance was one. This bar is the app's
                  // primary navigation and it was hiding what its four
                  // destinations are.
                  //
                  // It costs nothing where it matters: the whole bar is already
                  // hidden while the rider is moving (`hideWhileMoving`), so
                  // labels only ever appear at a standstill, which is exactly
                  // the surface that can afford words.
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  destinations: destinations,
                ),
        );
      },
    );
  }

  Widget _buildMap() {
    if (!widget.enableNativeServices && !_isSimulation) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation')),
        body: const Center(child: Text('Navigation map')),
      );
    }
    final routeStore = activeRideMapStoreWhenReady(
      initializing: _loading,
      isSimulation: _isSimulation,
      rideRouteStore: _rideRouteStore,
      simulationRouteStore: _simulationRouteStore,
    );
    if (routeStore == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = widget.rideController.session;
    final flightRole = session?.flightRole;
    final isBalloonView = session?.flightRole.isAboardBalloon == true;
    final isDriverView = flightRole == FlightRole.chaseDriver;
    final landingZoneUpdates = _isSimulation
        ? _simulationLandingZone
        : _sharedLandingZone;
    final boundaryDraft = _operationalBoundaryDraft;
    final map = RideMapFeature.fromEnvironment(
      key: ValueKey(
        'ride-map:${_appliedAuthoritativeRouteRevision ?? 'local'}:'
        '${isBalloonView ? 'air' : _activeRoute?.id ?? 'none'}:'
        '${isBalloonView ? 'balloon' : 'chase'}',
      ),
      currentPosition: _mapPosition,
      completedRideStore: widget.completedRideStore,
      navigationPosition: _mapNavigationPosition,
      overlayMarkers: _mapOverlays,
      riderTrails: _riderTrails,
      landingZone: landingZoneUpdates.value,
      landingZoneUpdates: landingZoneUpdates,
      onMapTap: _selectingLandingZone || boundaryDraft != null
          ? _handleFlightSetupMapTap
          : null,
      windForecastController: _windForecastController,
      groupRiderCount: widget.rideController.liveParticipants.length,
      onOpenRoster: _openRoster,
      // Deliberately not `onOpenRideMenu`. The control that reaches the other
      // tabs is rendered by this shell instead — see _openRideMenu and #404.
      enforcementAlert: isDriverView ? _enforcementAlert : null,
      rideCompletionSuggestion: _rideCompletionSuggestion,
      onEndRideForEveryone: _endRideFromCompletionSuggestion,
      onDismissRideCompletion: _dismissRideCompletionSuggestion,
      quickMessageAlerts: _quickMessageAlerts,
      onAcknowledgeQuickMessage: _acknowledgeQuickMessage,
      dismissedQuickMessageInterruptIds: _dismissedQuickMessageInterruptIds,
      dismissedQuickMessageReceiptIds: _dismissedQuickMessageReceiptIds,
      onDismissQuickMessageInterrupt: _dismissedQuickMessageInterruptIds.add,
      onDismissQuickMessageReceipt: _dismissedQuickMessageReceiptIds.add,
      dismissedEnforcementAlertId: _dismissedEnforcementAlertId,
      onDismissEnforcementAlert: (id) => _dismissedEnforcementAlertId = id,
      initialRouteStartConnector: _routeStartConnector,
      onRouteStartConnectorChanged: (connector) =>
          _routeStartConnector = connector,
      onReportHazard: isDriverView && _awarenessController != null
          ? _reportHazardFromMap
          : null,
      emergencyContacts: _emergencyContacts,
      onEmergencyAlert: _sendEmergencyMapAlert,
      onEmergencyIssue: _sendEmergencyMapIssue,
      onEmergencyContactUsed: _onEmergencyContactUsed,
      ridePaused: widget.rideController.ridePaused,
      rideHasNoLeader: widget.rideController.rideHasNoLeader,
      rideStarted: widget.rideController.rideStarted,
      onLeaveRide: _confirmLeaveRideFromMap,
      onRouteCommitted: _onRouteChanged,
      onNavigationGuidanceChanged: isDriverView
          ? _onNavigationGuidanceChanged
          : null,
      onNavigationViewportChanged: !isDriverView
          ? null
          : (viewport) {
              final bridge = _carPlayBridge;
              if (bridge != null) unawaited(bridge.publishViewport(viewport));
            },
      onMapStyleResolved: (styleJson) {
        if (!mounted) return;
        _carPlayMapStyleJson = styleJson;
        final bridge = _carPlayBridge;
        if (bridge == null) return;
        final basemap = BasemapConfiguration.fromEnvironment().forBrightness(
          dark: widget.mapStyleMode.resolveDark(
            MediaQuery.platformBrightnessOf(context),
          ),
          restrainedLightStyle:
              widget.mapStyleMode.dayStyle == DayMapStyle.restrained,
        );
        unawaited(
          bridge.publishMapStyle(
            styleJson: styleJson,
            fallbackStyleUrl: basemap.styleUrl,
          ),
        );
      },
      changeRouteRequestToken: _changeRouteRequestToken,
      onChangeRouteRequestHandled: _clearChangeRouteRequest,
      pendingSharedGpxFile: _pendingSharedGpxFile,
      pendingInAppRoute: _pendingInAppRoute,
      acquireCurrentPosition: _isSimulation
          ? () async => _mapPosition.value
          : _acquireCurrentPosition,
      routeStore: routeStore,
      canEditRoute:
          !isBalloonView &&
          (_isSimulation || widget.rideController.isLocalRideLeader),
      distanceUnit: widget.distanceUnits.value,
      speedLimitDisplay: isDriverView ? widget.speedLimitDisplay : null,
      chaseVehicle: widget.chaseVehicle?.vehicle ?? ChaseVehicle.unspecified,
      showRouteProgress:
          isDriverView && (widget.routeProgressDisplay?.enabled ?? true),
      darkMapStyle: widget.mapStyleMode.resolveDark(
        MediaQuery.platformBrightnessOf(context),
      ),
      restrainedLightMapStyle:
          widget.mapStyleMode.dayStyle == DayMapStyle.restrained,
      localMotorcycleStyle: isBalloonView
          ? CraftIconStyle.balloon
          : _isSimulation
          ? CraftIconStyle.fourByFour
          : session?.motorcycleStyle ?? craftIconStyleDefault,
      localRiderSymbol:
          widget.rideController.session?.riderSymbol ?? riderSymbolDefault,
      localDisplayName: widget.rideController.session?.displayName ?? 'You',
      localBadgeColor: _localBadgeColor,
      perspective: isBalloonView
          ? RideMapPerspective.balloon
          : RideMapPerspective.chase,
    );
    if (!_selectingLandingZone && boundaryDraft == null) return map;
    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 16,
          right: 16,
          child: Material(
            color: const Color(0xF2252E39),
            borderRadius: BorderRadius.circular(16),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Icon(
                    boundaryDraft == null
                        ? Icons.touch_app
                        : Icons.polyline_outlined,
                    color: const Color(0xFFFFC857),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      boundaryDraft == null
                          ? 'Tap the map to update the intended landing area · ${_landingRadiusMeters < 1000 ? '${_landingRadiusMeters.toInt()} m' : '${(_landingRadiusMeters / 1000).toStringAsFixed(1)} km'} radius'
                          : boundaryDraft.kind == OperationalBoundaryKind.line
                          ? 'Tap two points for ${boundaryDraft.label} · ${boundaryDraft.points.length}/2'
                          : 'Tap at least three corners for ${boundaryDraft.label} · ${boundaryDraft.points.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (boundaryDraft != null &&
                      boundaryDraft.kind == OperationalBoundaryKind.area &&
                      boundaryDraft.points.length >= 3)
                    TextButton(
                      onPressed: () =>
                          unawaited(_saveOperationalBoundaryDraft()),
                      child: const Text('Save'),
                    ),
                  TextButton(
                    onPressed: _cancelMapSelection,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleFlightSetupMapTap(route_domain.GeoPoint point) async {
    if (_selectingLandingZone) {
      await _updateLandingZoneFromMap(point);
      return;
    }
    final draft = _operationalBoundaryDraft;
    if (draft == null) return;
    draft.points.add(point);
    _syncOperationalBoundaries();
    if (mounted) setState(() {});
    if (draft.kind == OperationalBoundaryKind.line &&
        draft.points.length >= 2) {
      await _saveOperationalBoundaryDraft();
    }
  }

  void _cancelMapSelection() {
    setState(() {
      _selectingLandingZone = false;
      _operationalBoundaryDraft = null;
    });
    _syncOperationalBoundaries();
  }

  Future<void> _saveOperationalBoundaryDraft() async {
    final draft = _operationalBoundaryDraft;
    if (draft == null) return;
    final minimum = draft.kind == OperationalBoundaryKind.line ? 2 : 3;
    if (draft.points.length < minimum) return;
    await widget.rideController.upsertOperationalBoundary(
      OperationalBoundary(
        id: draft.id,
        label: draft.label,
        kind: draft.kind,
        points: [
          for (final point in draft.points)
            awareness_geo.GeoPoint(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
        ],
        source: draft.source,
        updatedAt: DateTime.now(),
        lowerAltitudeMeters: draft.lowerAltitudeMeters,
        upperAltitudeMeters: draft.upperAltitudeMeters,
        altitudeDatum: draft.altitudeDatum,
      ),
    );
    if (!mounted) return;
    if (widget.rideController.errorMessage case final message?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() => _operationalBoundaryDraft = null);
    _syncOperationalBoundaries();
  }

  Future<void> _updateLandingZoneFromMap(route_domain.GeoPoint point) async {
    await widget.rideController.setLandingZone(
      LandingZoneTarget(
        center: awareness_geo.GeoPoint(
          latitude: point.latitude,
          longitude: point.longitude,
        ),
        radiusMeters: _landingRadiusMeters,
        label:
            'Intended area · ${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)}',
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (widget.rideController.errorMessage case final message?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() => _selectingLandingZone = false);
  }

  LocationSample? _latestBalloonFix() {
    if (_isSimulation) {
      final balloon = _simulationController?.riders
          .where((rider) => rider.role == RideRole.lead)
          .firstOrNull;
      if (balloon == null) return null;
      return LocationSample(
        position: awareness_geo.GeoPoint(
          latitude: balloon.position.latitude,
          longitude: balloon.position.longitude,
        ),
        recordedAt: DateTime.now(),
        accuracyMeters: 5,
        speedMetersPerSecond: balloon.speedMetersPerSecond,
        headingDegrees: balloon.headingDegrees,
        altitudeMeters: balloon.altitudeMeters,
        altitudeSource: balloon.altitudeMeters == null
            ? AltitudeSource.unknown
            : AltitudeSource.gnss,
        altitudeDatum: balloon.altitudeMeters == null
            ? AltitudeDatum.unknown
            : AltitudeDatum.relativeToLaunch,
        verticalSpeedMetersPerSecond: balloon.verticalSpeedMetersPerSecond,
      );
    }

    final roster = widget.rideController.resolveCraftRoster();
    final balloonDeviceIds = roster.balloon?.deviceIds.toSet() ?? const {};
    final candidates =
        <RiderLocation>[
              ...widget.rideController.liveView.renderedPositions,
              ...?_awarenessController?.riderLocations,
            ]
            .where(
              (location) =>
                  balloonDeviceIds.contains(location.riderId) ||
                  (balloonDeviceIds.isEmpty && location.role == RideRole.lead),
            )
            .toList();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (left, right) =>
          right.sample.recordedAt.compareTo(left.sample.recordedAt),
    );
    return candidates.first.sample;
  }

  ChaseGuidanceDestination? _currentChaseGuidanceDestination({
    ChaseGuidanceTarget? target,
  }) {
    final selected = target ?? _chaseGuidanceTarget;
    if (selected == null) return null;
    return _chaseGuidanceResolver.resolve(
      target: selected,
      now: DateTime.now(),
      landingZone: widget.rideController.landingZone,
      balloonFix: _latestBalloonFix(),
    );
  }

  Future<void> _chooseChaseGuidanceTarget() async {
    final landing = _currentChaseGuidanceDestination(
      target: ChaseGuidanceTarget.landingArea,
    );
    final balloon = _currentChaseGuidanceDestination(
      target: ChaseGuidanceTarget.balloon,
    );
    final selected = await showModalBottomSheet<ChaseGuidanceTarget>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Directions for this chase vehicle'),
            subtitle: Text(
              'This changes only this device. The route ends on a road near the target; it never directs a vehicle off-road.',
            ),
          ),
          ListTile(
            key: const Key('chase-guidance-landing-area'),
            enabled: landing != null,
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Intended landing area'),
            subtitle: Text(
              landing?.label ?? 'The pilot has not set an area yet',
            ),
            trailing: _chaseGuidanceTarget == ChaseGuidanceTarget.landingArea
                ? const Icon(Icons.check)
                : null,
            onTap: landing == null
                ? null
                : () => Navigator.pop(
                    sheetContext,
                    ChaseGuidanceTarget.landingArea,
                  ),
          ),
          ListTile(
            key: const Key('chase-guidance-balloon'),
            enabled: balloon != null,
            leading: const Icon(Icons.air_outlined),
            title: const Text('Road rendezvous near balloon'),
            subtitle: Text(
              balloon?.label ?? 'No fresh balloon fix is available',
            ),
            trailing: _chaseGuidanceTarget == ChaseGuidanceTarget.balloon
                ? const Icon(Icons.check)
                : null,
            onTap: balloon == null
                ? null
                : () =>
                      Navigator.pop(sheetContext, ChaseGuidanceTarget.balloon),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _chaseGuidanceTarget = selected);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_chaseGuidancePreferenceKey, selected.name);
    await _refreshChaseGuidanceIfNeeded(force: true);
  }

  Future<void> _refreshChaseGuidanceIfNeeded({bool force = false}) async {
    if (!_isChaserPerspective ||
        _isSimulation ||
        _chaseGuidanceRouting ||
        !widget.rideController.rideStarted ||
        widget.rideController.rideEnded) {
      return;
    }
    final selected = _chaseGuidanceTarget;
    final destination = _currentChaseGuidanceDestination();
    final origin = _mapPosition.value;
    if (selected == null || destination == null || origin == null) {
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selected == ChaseGuidanceTarget.balloon
                  ? 'A fresh balloon fix and this vehicle’s position are needed.'
                  : 'An intended landing area and this vehicle’s position are needed.',
            ),
          ),
        );
      }
      return;
    }
    final now = DateTime.now();
    if (!_chaseGuidanceReroutePolicy.shouldReroute(
      now: now,
      target: destination.point,
      lastRoutedAt: _lastChaseGuidanceRouteAt,
      lastTarget: _lastChaseGuidanceTarget,
      force: force,
    )) {
      return;
    }

    _chaseGuidanceRouting = true;
    if (mounted) setState(() {});
    try {
      final result = await _simulationRoutingService.routeThrough([
        origin,
        route_domain.GeoPoint(
          latitude: destination.point.latitude,
          longitude: destination.point.longitude,
        ),
      ], originBearingDegrees: _mapNavigationPosition.value?.headingDegrees);
      if (!mounted) return;
      final roadEndpoint = awareness_geo.GeoPoint(
        latitude: result.points.last.latitude,
        longitude: result.points.last.longitude,
      );
      if (!destination.acceptsRoadEndpoint(roadEndpoint)) {
        _warnings.add(
          'No sufficiently close road rendezvous was found for ${selected.label.toLowerCase()}. The previous route is still in use.',
        );
        setState(() {});
        return;
      }
      final separation = GeoCalculations.distanceMeters(
        roadEndpoint,
        destination.point,
      );
      final route = route_domain.ImportedRoute(
        id: 'personal-chase-${_chaseGuidanceRouteSequence++}',
        name: selected.label,
        description:
            'Device-local road guidance. The road endpoint is '
            '${MeasurementFormatter(widget.distanceUnits.value).distance(separation)} '
            'from ${selected == ChaseGuidanceTarget.balloon ? 'the latest balloon fix' : 'the centre of the intended area'}. Access and stopping suitability remain unverified.',
        importedAt: now,
        sourceFileName: 'balloon-crumbs-personal-chase-route',
        paths: [
          route_domain.RoutePath(
            kind: route_domain.RoutePathKind.route,
            name: selected.label,
            points: result.points,
          ),
        ],
        waypoints: [
          route_domain.RouteWaypoint(
            point: origin,
            name: 'Chase vehicle',
            symbol: 'Flag, Blue',
          ),
          route_domain.RouteWaypoint(
            point: result.points.last,
            name: selected.label,
            description:
                'Road-accessible routing endpoint; target remains approximate.',
            symbol: 'Flag, Red',
          ),
        ],
        maneuvers: result.maneuvers,
        plannedDuration: result.duration,
      );
      _liveRoutes = _liveRoutes.withVehicleRoadRoute(route);
      _lastChaseGuidanceRouteAt = now;
      _lastChaseGuidanceTarget = destination.point;
      await _rideRouteStore?.saveActiveRoute(route);
      await _replaceAwarenessController(route);
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        _warnings.add(
          'Personal chase guidance is unavailable; the previous road route is still in use. $error',
        );
        setState(() {});
      }
    } finally {
      _chaseGuidanceRouting = false;
      if (mounted) setState(() {});
    }
  }

  void _onNavigationGuidanceChanged(NavigationGuidance? guidance) {
    _latestNavigationGuidance = guidance;
    _recordManoeuvreDiagnostics(guidance);
    _speakGuidance(guidance);
    _updateMapOverlays(updateDerivedState: false);
  }

  /// Writes the turn detail down as the rider rides towards it (#419).
  ///
  /// The report is the one `maneuverDiagnosticsReport` renders for the #302
  /// sheet, not a second derivation: a roundabout's heading change is read
  /// across two merged steps rather than from the entry manoeuvre's own
  /// `bearingAfter` (#360), and an instrument that disagrees with the app it
  /// measures is worse than none.
  /// Records an enforcement warning appearing or going away (#418).
  ///
  /// The report the ride was filed against says the warning "requires touching
  /// the screen to cancel", so what has to be distinguishable in the log is a
  /// warning the rider dismissed from one that cleared itself on passing. The
  /// clearing edge does not know which happened, so it says only that it
  /// cleared and leaves the distinction to the timing beside it.
  void _recordEnforcementTransition({
    required EnforcementAlert? previous,
    required EnforcementAlert? current,
  }) {
    final diagnostics = _diagnostics;
    if (diagnostics == null) return;
    if (previous?.hazard.id == current?.hazard.id) return;
    if (previous != null) {
      diagnostics.recordEnforcementWarning(
        hazardType: previous.hazard.type.name,
        distanceMeters: previous.distanceMeters,
        armed: false,
        clearedBy: _dismissedEnforcementAlertId == previous.hazard.id
            ? 'rider tap'
            : 'no longer detected',
      );
    }
    if (current != null) {
      diagnostics.recordEnforcementWarning(
        hazardType: current.hazard.type.name,
        distanceMeters: current.distanceMeters,
        armed: true,
        clearedBy: null,
      );
    }
  }

  /// Says a camera or police warning out loud (#430).
  ///
  /// It was never wired: `_speakGuidance` was the only path to the speech engine
  /// and it speaks turns. A rider looking at the road ahead — which is the point
  /// of the warning — got nothing.
  ///
  /// Spoken as `SpokenAudioClass.safety`, so #415's alerts-only mode keeps it when
  /// turn-by-turn goes quiet. Once, on the arming edge: the warning holds from a
  /// mile out and repeating it for a mile would be worse than silence.
  void _speakEnforcementWarning(
    EnforcementAlert? previous,
    EnforcementAlert? current,
  ) {
    final speaker = _spokenGuidance;
    if (speaker == null || current == null) return;
    if (previous?.hazard.id == current.hazard.id) return;
    final controller = widget.rideController;
    final camera = current.hazard.type == HazardType.speedCamera;
    final distance = MeasurementFormatter(
      widget.distanceUnits.value,
    ).distance(current.distanceMeters);
    // The enforced limit where the catalogue tags one, in the same words the
    // panel shows (#418) — a rider should not hear one number and read another.
    final limit = enforcementLimitLabel(current.hazard.details);
    unawaited(
      speaker.speakAlert(
        key: 'enforcement:${current.hazard.id}',
        phrase: [
          camera ? 'Speed camera' : 'Police',
          'in $distance',
          ?limit,
        ].join(', '),
        enabled: spokenAudioAllows(_spokenAudioMode, SpokenAudioClass.safety),
        rideActive:
            controller.rideStarted &&
            !controller.rideEnded &&
            !controller.ridePaused,
      ),
    );
  }

  /// The audio mode in force: what the rider chose, quietened while off route.
  ///
  /// Off route, turn-by-turn names junctions that are not coming, so it drops to
  /// alerts only — but a rider who chose silence stays silent, because an
  /// explicit choice outranks an automatic one (#415).
  SpokenAudioMode get _spokenAudioMode =>
      widget.spokenGuidance?.mode ?? SpokenAudioMode.silent;

  void _onSpokenGuidanceChanged() {
    unawaited(_warmNaturalVoiceIfNeeded());
  }

  /// Pulls the expensive model load out of the first camera or turn prompt.
  /// Silent audio and a ride that has not started remain zero-work paths.
  Future<void> _warmNaturalVoiceIfNeeded() async {
    final controller = widget.spokenGuidance;
    final speaker = _spokenGuidance;
    if (controller == null || speaker == null) return;
    final rideActive =
        widget.rideController.rideStarted && !widget.rideController.rideEnded;
    final naturalEnabled =
        controller.naturalVoicePack.enabled &&
        controller.naturalVoicePack.modelDirectory != null;
    try {
      await speaker.warmUp(
        enabled: rideActive && controller.enabled && naturalEnabled,
      );
    } on Object catch (error, stackTrace) {
      // OS speech remains configured as the fail-safe. A model-load problem is
      // useful in diagnostics but must never block or end a ride.
      _diagnostics?.recordNote('Natural voice warm-up failed: $error');
      if (kDebugMode) {
        debugPrint('Natural voice warm-up failed: $error\n$stackTrace');
      }
    }
  }

  void _recordSpeechOutput(String phrase, SpokenGuidanceOutput output) {
    _diagnostics?.recordSpeechDelivery(phrase: phrase, output: output);
  }

  void _recordManoeuvreDiagnostics(NavigationGuidance? guidance) {
    final diagnostics = _diagnostics;
    if (diagnostics == null || guidance == null) return;
    final instruction = guidance.instruction;
    diagnostics.recordManoeuvre(
      // The manoeuvre's identity, matching the key `_speakGuidance` uses, so
      // re-deriving the same turn on every fix does not write it down again.
      key: instruction.maneuver.identity,
      position: awareness_geo.GeoPoint(
        latitude: instruction.maneuver.position.latitude,
        longitude: instruction.maneuver.position.longitude,
      ),
      shownAs: instruction.direction.label,
      diagnostics: maneuverDiagnosticsReport(instruction),
    );
  }

  /// Speaks the instruction the phone banner and the car rows are already showing
  /// (#286).
  ///
  /// Deliberately driven from here rather than from its own timer or a second
  /// derivation of the route. This is the one place the current instruction
  /// changes, so audio cannot disagree with the screen - and a rider who hears
  /// one thing and sees another will trust neither.
  ///
  /// [ManeuverInstruction.standaloneText] is the wording, for the reason it
  /// already exists: it is what surfaces with no symbol beside them use, which is
  /// exactly what audio is. A roundabout says so out loud, where the banner can
  /// leave it to the drawn glyph.
  void _speakGuidance(NavigationGuidance? guidance) {
    if (guidance == null) return;
    final controller = widget.rideController;
    final identity = guidance.instruction.maneuver.identity;

    // The instruction has moved on, so the one before it is now behind the rider
    // and its position is what the clearance rule measures against (#429).
    if (identity != _guidanceManeuverIdentity) {
      if (_guidanceManeuverIdentity != null) {
        _passedManeuverPosition = _lastGuidanceManeuverPosition;
      }
      _guidanceManeuverIdentity = identity;
    }
    _lastGuidanceManeuverPosition = guidance.instruction.maneuver.position;

    final speaker = _spokenGuidance;
    if (speaker == null) return;

    final navigation = _mapNavigationPosition.value;
    final passed = _passedManeuverPosition;
    final rider = navigation?.point;
    final metersSincePrevious = passed == null || rider == null
        ? null
        : GeoCalculations.distanceMeters(
            awareness_geo.GeoPoint(
              latitude: rider.latitude,
              longitude: rider.longitude,
            ),
            awareness_geo.GeoPoint(
              latitude: passed.latitude,
              longitude: passed.longitude,
            ),
          );

    // What to say and when, decided apart from the saying so the timing can be
    // driven by a synthetic approach in a test (#409, #410, #429).
    final announcement = nextGuidanceAnnouncement(
      maneuverIdentity: identity,
      instructionText: guidance.instruction.standaloneText,
      distanceToManeuverMeters: guidance.distanceMeters,
      speedMetersPerSecond: navigation?.speedMetersPerSecond,
      alreadySpokenKeys: _spokenGuidanceKeys,
      metersSincePreviousManeuver: metersSincePrevious,
      distanceFormatter: MeasurementFormatter(
        widget.distanceUnits.value,
      ).distance,
      // The pair the banner is already showing (#163). Speech was given this and
      // ignored it, which is why a junction close behind another was only ever
      // announced at the junction itself (#460).
      followingInstructionText: guidance.followingInstruction?.standaloneText,
    );
    if (announcement == null) return;

    // Marked spoken before the await, so a slow speech engine cannot let the
    // same stage fire again on the next fix.
    _spokenGuidanceKeys.add(announcement.key);
    // #409 is about *when* this is said, so the distance to the junction at the
    // moment it left the speaker is the measurement.
    _diagnostics?.recordSpokenPrompt(
      phrase: announcement.phrase,
      distanceToManoeuvreMeters: guidance.distanceMeters,
    );
    unawaited(
      speaker.speakManoeuvre(
        // Per stage, not per manoeuvre: keyed on the manoeuvre alone, the early
        // prompt would suppress the two after it.
        key: announcement.key,
        phrase: announcement.phrase,
        // Navigation, so alerts-only silences this and keeps the warnings.
        enabled: spokenAudioAllows(
          _spokenAudioMode,
          SpokenAudioClass.navigation,
        ),
        rideActive:
            controller.rideStarted &&
            !controller.rideEnded &&
            !controller.ridePaused,
      ),
    );
  }

  String get _projectedRideState {
    if (widget.rideController.rideEnded) return 'Flight ended';
    if (widget.rideController.ridePaused) return 'Flight paused';
    if (widget.rideController.rideStarted) return 'Flight in progress';
    return 'Waiting for the pilot or coordinator to start';
  }

  /// Offers only the final pre-departure decision on CarPlay. Ride creation,
  /// joining and route selection remain phone setup; this projection exists
  /// only after that work is complete and only for the local leader.
  CarPlayRideStart? get _carPlayRideStart {
    final controller = widget.rideController;
    final locationReady =
        _isSimulation ||
        !widget.enableNativeServices ||
        (_locationController?.status.canSample ?? false);
    return CarPlayRideStart.project(
      hasSession: controller.session != null,
      isLeader: controller.isLocalRideLeader,
      rideStarted: controller.rideStarted,
      rideEnded: controller.rideEnded,
      busy: controller.busy,
      locationReady: locationReady,
      isGroup: controller.coordinationMode.isGroup,
      routeName: _activeRoute?.name,
    );
  }

  /// Handles the confirmed native action. The snapshot that drew the button
  /// may be stale, so leader, lifecycle, busy and location state are checked
  /// again before the durable start event is recorded.
  Future<void> _startPreparedRideFromCarPlay() async {
    if (!mounted) return;
    final controller = widget.rideController;
    if (controller.session == null ||
        !controller.isLocalRideLeader ||
        controller.rideStarted ||
        controller.rideEnded ||
        controller.busy ||
        _rideStartFlowInProgress) {
      _updateMapOverlays(updateDerivedState: false);
      return;
    }
    _rideStartFlowInProgress = true;
    try {
      final locationController = _locationController;
      if (!_isSimulation &&
          widget.enableNativeServices &&
          (locationController == null ||
              !locationController.status.canSample)) {
        final added = _warnings.add(
          'Open Balloon Crumbs on the iPhone and allow location access before '
          'starting the ride from CarPlay.',
        );
        _updateMapOverlays(updateDerivedState: false);
        if (added && mounted) setState(() {});
        return;
      }

      _diagnostics?.recordNote('start ride accepted from CarPlay');
      if (await _commitRideStart(source: 'CarPlay')) {
        await _resumeLocationForActiveRide();
      }
    } finally {
      _rideStartFlowInProgress = false;
      if (mounted) _updateMapOverlays(updateDerivedState: false);
    }
  }

  /// Records the one durable start transition for either surface and contains
  /// storage/authentication failures. An uncaught Future error from a button
  /// callback used to escape Flutter's UI path; CarPlay already caught its copy,
  /// so the two surfaces behaved differently under the same failure.
  Future<bool> _commitRideStart({required String source}) async {
    _localRideStartInProgress = true;
    try {
      await widget.rideController.startRide();
      return true;
    } on Object catch (error, stackTrace) {
      _diagnostics?.recordNote(
        'start ride failed from $source: ${error.runtimeType}: $error',
      );
      if (kDebugMode) {
        debugPrint(
          'Could not start the ride from $source: $error\n$stackTrace',
        );
      }
      final message = source == 'CarPlay'
          ? 'CarPlay could not start the flight. Open Balloon Crumbs on the '
                'iPhone and try again.'
          : 'The flight could not start. Please try again.';
      final added = _warnings.add(message);
      if (added && mounted) setState(() {});
      if (source != 'CarPlay' && mounted) _showRideSnackBar(message);
      return false;
    } finally {
      _localRideStartInProgress = false;
    }
  }

  /// Next instruction for the projected car surfaces.
  ///
  /// This is the same collapsed instruction the phone banner shows, so a
  /// roundabout is announced once, with its exit and direction, rather than as
  /// the engine's separate entry and exit steps. The car rows are plain text
  /// with no symbol beside them, so they name the junction.
  String? get _projectedGuidanceTitle =>
      _latestNavigationGuidance?.instruction.standaloneText;

  String? get _projectedGuidanceDetail {
    final guidance = _latestNavigationGuidance;
    if (guidance == null) return null;
    final distance = MeasurementFormatter(
      widget.distanceUnits.value,
    ).distance(guidance.distanceMeters);
    return '$distance · ${guidance.roadLabel}';
  }

  Color get _localBadgeColor {
    final session = widget.rideController.session;
    if (session == null) return riderColorDefault.color;
    return session.riderColor.color;
  }

  /// The leader and TEC, with a phone number attached only where that rider has
  /// explicitly shared their own (#188).
  ///
  /// The number comes from `receivedRiderContacts` and nowhere else. It is never
  /// taken from an ICE share — that is the rider's next of kin — and never from
  /// the roster, a location event or the device. A role with nothing attached is
  /// still listed: the emergency sheet says so plainly rather than hiding it.
  List<MapEmergencyContact> get _emergencyContacts {
    final contacts = <String, MapEmergencyContact>{};
    final sharedNumbers = widget.rideController.receivedRiderContacts;
    final session = widget.rideController.session;
    if (session != null && session.flightRole == FlightRole.pilot) {
      contacts[session.localRiderId] = MapEmergencyContact(
        riderId: session.localRiderId,
        displayName: session.displayName,
        role: session.role,
      );
    }
    for (final rider in _awarenessController?.riderLocations ?? const []) {
      if (rider.role != RideRole.lead) continue;
      final shared = sharedNumbers[rider.riderId];
      contacts[rider.riderId] = MapEmergencyContact(
        riderId: rider.riderId,
        displayName: rider.displayName,
        role: rider.role,
        phoneNumber: shared?.phoneNumber,
        contactShareEventId: shared?.eventId,
      );
    }
    return contacts.values.toList(growable: false);
  }

  /// A dialled number is a used share, so it survives the ride-end purge for the
  /// same reason a called ICE contact does: a rider who has just phoned somebody
  /// may need to phone them again.
  void _onEmergencyContactUsed(MapEmergencyContact contact) {
    final eventId = contact.contactShareEventId;
    if (eventId != null) widget.rideController.markRiderContactUsed(eventId);
  }

  Future<void> _sendEmergencyMapAlert() async {
    await _sendEmergencyQuickMessage(QuickMessage.emergencyStop);
    await _autoShareIceWithLeaderIfEnabled();
  }

  Future<void> _sendEmergencyMapIssue(QuickMessage message) =>
      _sendEmergencyQuickMessage(message);

  Future<void> _sendEmergencyQuickMessage(QuickMessage message) async {
    final session = widget.rideController.session;
    final recipients = _emergencyContacts
        .where((contact) => contact.riderId != session?.localRiderId)
        .map((contact) => contact.riderId)
        .toList(growable: false);
    await widget.rideController.sendQuickMessage(
      message,
      recipientRiderIds: recipients,
      // Where the rider is standing, relayed with the message: "Bill needs fuel"
      // is not actionable without "1.2 miles back" (#151).
      position: _localQuickMessagePosition,
    );
    await _recordLocalObserverQuickMessage(message);
  }

  Future<void> _sendLocalQuickMessage(QuickMessage message) async {
    await widget.rideController.sendQuickMessage(
      message,
      position: _localQuickMessagePosition,
    );
    await _recordLocalObserverQuickMessage(message);
  }

  /// The best fix this phone has for itself, journal-first and falling back to
  /// the foreground sample a pre-movement rider has but has not yet recorded.
  awareness_geo.GeoPoint? get _localQuickMessagePosition =>
      _awarenessController?.localLocation?.sample.position ??
      _locationController?.activeSample?.position;

  Future<void> _recordLocalObserverQuickMessage(QuickMessage message) async {
    if (message == QuickMessage.assistance ||
        message == QuickMessage.emergencyStop ||
        message == QuickMessage.resolved) {
      await _observerAccessController?.recordLocalAssistance(
        message == QuickMessage.resolved ? null : message.name,
      );
      if (mounted) setState(() {});
      _publishObserverSnapshot();
    }
  }

  /// The opt-in "share with the leader by default" setting, fired alongside
  /// the emergency-stop alert so it still happens if the rider can't take a
  /// further step. A no-op if the setting is off, there's nothing to share,
  /// or the local rider is themselves the leader.
  Future<void> _autoShareIceWithLeaderIfEnabled() async {
    if (!widget.riderProfile.shareIceWithLeaderByDefault ||
        !widget.riderProfile.hasEmergencyInfo) {
      return;
    }
    final session = widget.rideController.session;
    final leaderId = _currentLeaderRiderId;
    if (session == null ||
        leaderId == null ||
        leaderId == session.localRiderId) {
      return;
    }
    await widget.rideController.shareEmergencyInfo(
      contactName: widget.riderProfile.emergencyContactName,
      contactPhone: widget.riderProfile.emergencyContactPhone,
      medicalNotes: widget.riderProfile.medicalNotes,
      recipientRiderIds: [leaderId],
    );
  }

  /// An explicit rider action: shares ICE info with everyone in the ride,
  /// including the phone number, regardless of the default-share setting.
  Future<void> _shareIceInfoWithGroup() async {
    await widget.rideController.shareEmergencyInfo(
      contactName: widget.riderProfile.emergencyContactName,
      contactPhone: widget.riderProfile.emergencyContactPhone,
      medicalNotes: widget.riderProfile.medicalNotes,
      recipientRiderIds: const [],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency contact shared with the group.')),
    );
  }

  Future<void> _openIceShareInbox() =>
      IceShareInboxSheet.show(context, widget.rideController);

  /// Who this rider's own number would go to if they shared it now (#188).
  ///
  /// An ordinary rider addresses it to the leader and the TEC and to nobody
  /// else. A rider who holds either role is sharing so the riders they are
  /// leading can reach them, which is the case in the request, so theirs goes to
  /// the ride. Reversing that is a one-line change in
  /// [RiderContactRecipients.resolve].
  RiderContactRecipients get _ownContactRecipients {
    final session = widget.rideController.session;
    if (session == null) return const RiderContactRecipients.addressed([]);
    final leaderId = _currentLeaderRiderId;
    return RiderContactRecipients.resolve(
      localRole: session.role,
      leaderRiderId: leaderId == session.localRiderId ? null : leaderId,
      coordinationRiderIds: const [],
    );
  }

  /// Shares this rider's own number. An explicit action, never automatic: there
  /// is no path that shares a number as a side effect of anything else, and a
  /// rider who shares nothing keeps a fully working app.
  Future<void> _shareOwnPhoneNumber() async {
    if (!widget.riderProfile.hasOwnPhoneNumber) {
      await EmergencyInfoSheet.show(context, widget.riderProfile);
      return;
    }
    // A new event type is rejected outright by an older build, so an older relay
    // that will not carry it has to be named rather than allowed to look like a
    // successful share.
    final relayCanCarry =
        _internetRelayController?.supportsCapability(
          RelayProtocolCapabilities.riderContactSharing,
        ) ??
        true;
    if (!relayCanCarry) {
      _showRideSnackBar(
        PresenceLimitation.riderContactSharingUnsupportedByService.message,
      );
      return;
    }
    final recipients = _ownContactRecipients;
    if (recipients.isEmpty) {
      _showRideSnackBar(
        'Nobody is holding the leader role yet, so there '
        'is nobody to give your number to. Nothing has been shared.',
      );
      return;
    }
    final shared = await widget.rideController.shareOwnContactNumber(
      phoneNumber: widget.riderProfile.ownPhoneNumber,
      recipients: recipients,
    );
    if (!mounted) return;
    _showRideSnackBar(
      shared
          ? (recipients.toRideGroup
                ? 'Your number is now available to this flight, for this flight '
                      'only.'
                : 'Your number has gone to the coordinator, and '
                      'to nobody else.')
          : 'Your number was not shared. '
                    '${widget.rideController.errorMessage ?? ''}'
                .trim(),
    );
  }

  void _showRideSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onPushNotificationStatusChanged() {
    if (mounted) setState(() {});
  }

  void _onPushNotificationOpened(PushOpenRequest request) {
    final session = widget.rideController.session;
    if (!mounted || session == null || request.rideId != session.rideId) {
      return;
    }
    _internetRelayController?.wake();
    final safetyAlert = request.category == 'safety';
    setState(
      () => _selectedIndex = switch ((_isSimulation, safetyAlert)) {
        (true, true) => 3,
        (true, false) => 2,
        (false, true) => 2,
        (false, false) => 1,
      },
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Opened the authenticated flight alert.')),
      );
  }

  Future<void> _openNotificationPreferences() async {
    final controller = _pushNotificationController;
    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification settings are still loading.'),
        ),
      );
      return;
    }
    await NotificationPreferencesSheet.show(context, controller);
  }

  String? get _currentLeaderRiderId {
    final session = widget.rideController.session;
    if (session?.flightRole == FlightRole.pilot) {
      return session!.localRiderId;
    }
    for (final rider in _awarenessController?.riderLocations ?? const []) {
      if (rider.role == RideRole.lead) return rider.riderId;
    }
    return null;
  }

  Future<void> _toggleRidePause() async {
    if (widget.rideController.ridePaused) {
      await widget.rideController.resumeRide();
    } else {
      await widget.rideController.pauseRide();
    }
  }

  Future<void> _confirmStartRide() async {
    // Recorded before the gate, not after (#441). The report is that this
    // control "does nothing" with CarPlay connected, and no path in this file
    // treats a CarPlay session differently — so the first thing to establish is
    // whether the tap arrives at all, and if it does, which of the two early
    // returns swallows it. An entry here and no `start decision` after it means
    // the gate; no entry at all means the tap never reached Dart.
    final controller = widget.rideController;
    _diagnostics?.recordNote(
      'start ride tapped on the phone: '
      'role=${controller.session?.role.name ?? 'none'} '
      'started=${controller.rideStarted} '
      'busy=${controller.busy} '
      'route=${_activeRoute == null ? 'none' : 'selected'}',
    );
    if (_rideStartFlowInProgress) {
      _diagnostics?.recordNote(
        'start ride refused before the dialog: another start flow is active',
      );
      return;
    }
    _rideStartFlowInProgress = true;
    try {
      if (!controller.hasFlightAuthority || controller.rideStarted) {
        _diagnostics?.recordNote(
          'start ride refused before the dialog: not the leader, or already '
          'started',
        );
        return;
      }
      final route = _activeRoute;
      final decision = await showDialog<_StartRideDecision>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Start this flight?'),
          content: Text(
            route == null
                ? 'No route is selected. You can choose one now, or start '
                      'without navigation. Live location sharing and flight '
                      'recording begin only after you start.'
                : 'Route: ${route.name}\n\nLive location sharing, route '
                      'progress, off-course alerts and flight recording will '
                      'begin for the group.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _StartRideDecision.cancel),
              child: const Text('Cancel'),
            ),
            if (route == null) ...[
              TextButton(
                key: const Key('start-without-route-button'),
                onPressed: () =>
                    Navigator.pop(dialogContext, _StartRideDecision.start),
                child: const Text('Start without route'),
              ),
              FilledButton.icon(
                key: const Key('choose-route-before-start-button'),
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _StartRideDecision.chooseRoute,
                ),
                icon: const Icon(Icons.route_outlined),
                label: const Text('Choose route'),
              ),
            ] else
              FilledButton.icon(
                key: const Key('confirm-start-ride-button'),
                onPressed: () =>
                    Navigator.pop(dialogContext, _StartRideDecision.start),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start flight'),
              ),
          ],
        ),
      );
      _diagnostics?.recordNote(
        'start ride decision: ${decision?.name ?? 'dismissed'}',
      );
      if (decision == _StartRideDecision.chooseRoute) {
        _requestRouteChange();
        return;
      }
      if (decision == _StartRideDecision.start) {
        if (await _commitRideStart(source: 'phone')) {
          try {
            // The confirmation is an explicit user action and promises that
            // live sharing begins now, so it is the correct place to request
            // permission when the leader has not granted it yet.
            await _locationController?.requestAndStart();
          } on Object catch (error, stackTrace) {
            if (kDebugMode) {
              debugPrint('Could not start live GPS: $error\n$stackTrace');
            }
            final added = _warnings.add(
              'The flight started, but live GPS could not start. Use Follow me '
              'or Safety to try again.',
            );
            if (added && mounted) setState(() {});
          }
        }
      }
    } finally {
      _rideStartFlowInProgress = false;
      if (mounted) _updateMapOverlays(updateDerivedState: false);
    }
  }

  /// Warns the leader once, before the ride starts, that nobody is Tail End
  /// Charlie, and returns whether they chose to ride anyway.
  ///
  /// This is deliberately a warning and not a block: a two-rider ride or a
  /// solo scouting ride is legitimate. It only ever runs inside the start
  /// confirmation, so it cannot nag during the ride.
  Future<void> _confirmLeaveRideFromMap() async {
    final isLeader = canEndRideForEveryone(widget.rideController);
    final decision = await showRideExitDialog(
      context,
      isLeader: isLeader,
      isSolo: !widget.rideController.coordinationMode.isGroup,
    );
    switch (decision) {
      case RideExitDecision.leave:
        await _leaveRide();
        return;
      case RideExitDecision.endForEveryone:
        await _confirmEndRide();
        return;
      case RideExitDecision.cancel:
      case null:
        return;
    }
  }

  Future<void> _confirmEndRide() async {
    // One shared dialog, so the words a leader reads do not depend on whether
    // they came from the Ride page or the map's Leave control (#306).
    await confirmEndRide(
      context,
      controller: widget.rideController,
      relayCanCarryReopen: _relayCanCarryReopen,
      onShareSummary: _shareCurrentRideSummary,
    );
  }

  Widget _buildRideActions() => _RideActionsPanel(
    coordinationMode: widget.rideController.coordinationMode,
    canChangeRoute: _isSimulation || widget.rideController.isLocalRideLeader,
    onAlertsAndReports: _openAlertsAndReports,
    onShareSummary: _shareCurrentRideSummary,
    onOpenRoster: _openRoster,
    onShareRoster: _shareRoster,
    onChangeRoute: _requestRouteChange,
    canChangeLandingZone:
        !_isSimulation && widget.rideController.isLocalRideLeader,
    landingZoneLabel: widget.rideController.landingZone?.label,
    onChangeLandingZone: () => unawaited(_chooseLandingZoneOnMap()),
    boundaryCount: widget.rideController.operationalBoundaries.length,
    canEditBoundaries:
        !_isSimulation && widget.rideController.isLocalRideLeader,
    onOperationalBoundaries: () => unawaited(_openOperationalBoundaries()),
    canChooseChaseGuidance:
        !_isSimulation &&
        _isChaserPerspective &&
        widget.rideController.rideStarted &&
        !widget.rideController.rideEnded,
    chaseGuidanceLabel: _chaseGuidanceRouting
        ? 'Calculating a road rendezvous…'
        : _chaseGuidanceTarget == null
        ? null
        : '${_chaseGuidanceTarget!.label} · only on this device',
    onChooseChaseGuidance: () => unawaited(_chooseChaseGuidanceTarget()),
    maneuverCount: const NavigationGuidancePlanner()
        .instructions(_activeRoute)
        .length,
    onShowManeuvers: _openManeuverList,
    onEmergencyInfo: () =>
        EmergencyInfoSheet.show(context, widget.riderProfile),
    onNotifications: _openNotificationPreferences,
    canManageObserverAccess: _observerAccessController != null,
    onObserverAccess: _openObserverAccess,
    canShareIceInfo: widget.riderProfile.hasEmergencyInfo,
    onShareIceInfo: _shareIceInfoWithGroup,
    receivedIceShareCount: widget.rideController.receivedIceShares.length,
    onViewIceShares: _openIceShareInbox,
    hasOwnPhoneNumber: widget.riderProfile.hasOwnPhoneNumber,
    ownPhoneNumberShared: widget.rideController.hasSharedOwnContactNumber,
    ownPhoneNumberRecipientLabel: _ownContactRecipients.toRideGroup
        ? 'this flight'
        : 'the coordinator',
    onShareOwnPhoneNumber: () => unawaited(_shareOwnPhoneNumber()),
    ridePaused: widget.rideController.ridePaused,
    canToggleRidePause:
        !_isSimulation &&
        widget.rideController.rideStarted &&
        widget.rideController.hasFlightAuthority,
    onToggleRidePause: _toggleRidePause,
    onLeaveOrEndRide: _confirmLeaveRideFromMap,
  );

  Future<void> _chooseLandingZoneOnMap() async {
    var radius = _landingRadiusMeters;
    final selectedRadius = await showModalBottomSheet<double>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF171D25),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Update intended landing area',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose an approximate radius, then tap the map. This does not verify road access, permission or landing suitability.',
                style: TextStyle(color: Color(0xFFABB5C1)),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final choice in const [250.0, 500.0, 1000.0])
                    ChoiceChip(
                      label: Text(
                        choice < 1000 ? '${choice.toInt()} m' : '1 km',
                      ),
                      selected: radius == choice,
                      onSelected: (_) => setSheetState(() => radius = choice),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(radius),
                icon: const Icon(Icons.touch_app),
                label: const Text('Choose centre on map'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selectedRadius == null || !mounted) return;
    setState(() {
      _landingRadiusMeters = selectedRadius;
      _selectedIndex = 0;
      _selectingLandingZone = true;
    });
  }

  Future<void> _openOperationalBoundaries() async {
    final canEdit = !_isSimulation && widget.rideController.isLocalRideLeader;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171D25),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final boundaries = widget.rideController.operationalBoundaries;
          return FractionallySizedBox(
            heightFactor: 0.82,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Operational boundaries',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Shared pilot-entered advisories. They do not replace current airspace, weather, permissions or pilot judgement.',
                        style: TextStyle(color: Color(0xFFABB5C1)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: boundaries.isEmpty
                      ? const Center(
                          child: Text('No boundaries have been added.'),
                        )
                      : ListView.builder(
                          itemCount: boundaries.length,
                          itemBuilder: (context, index) {
                            final boundary = boundaries[index];
                            final altitude = [
                              if (boundary.lowerAltitudeMeters
                                  case final value?)
                                'min ${value.round()} m',
                              if (boundary.upperAltitudeMeters
                                  case final value?)
                                'max ${value.round()} m',
                            ].join(' · ');
                            return ListTile(
                              leading: Icon(switch (boundary.kind) {
                                OperationalBoundaryKind.line => Icons.polyline,
                                OperationalBoundaryKind.area =>
                                  Icons.pentagon_outlined,
                                OperationalBoundaryKind.altitudeBand =>
                                  Icons.height,
                              }, color: const Color(0xFFFF5D73)),
                              title: Text(boundary.label),
                              subtitle: Text(
                                '${boundary.source}${altitude.isEmpty ? '' : ' · $altitude ${boundary.altitudeDatum.name}'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: canEdit
                                  ? IconButton(
                                      tooltip: 'Remove boundary',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await widget.rideController
                                            .removeOperationalBoundary(
                                              boundary.id,
                                            );
                                        if (sheetContext.mounted) {
                                          setSheetState(() {});
                                        }
                                      },
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(
                              _configureOperationalBoundary(
                                OperationalBoundaryKind.line,
                              ),
                            );
                          },
                          icon: const Icon(Icons.polyline),
                          label: const Text('Draw line'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(
                              _configureOperationalBoundary(
                                OperationalBoundaryKind.area,
                              ),
                            );
                          },
                          icon: const Icon(Icons.pentagon_outlined),
                          label: const Text('Draw area'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(
                              _configureOperationalBoundary(
                                OperationalBoundaryKind.altitudeBand,
                              ),
                            );
                          },
                          icon: const Icon(Icons.height),
                          label: const Text('Altitude limits'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _configureOperationalBoundary(
    OperationalBoundaryKind kind,
  ) async {
    final labelController = TextEditingController(
      text: switch (kind) {
        OperationalBoundaryKind.line => 'Advisory boundary line',
        OperationalBoundaryKind.area => 'Advisory boundary area',
        OperationalBoundaryKind.altitudeBand => 'Planned altitude band',
      },
    );
    final sourceController = TextEditingController(
      text: 'Pilot-entered advisory boundary',
    );
    final lowerController = TextEditingController();
    final upperController = TextEditingController();
    var datum = AltitudeDatum.wgs84Geoid;
    String? validationMessage;
    final draft = await showDialog<_OperationalBoundaryDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            kind == OperationalBoundaryKind.altitudeBand
                ? 'Add altitude limits'
                : 'Describe the boundary',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  maxLength: 96,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: sourceController,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Source or briefing reference',
                    helperText: 'Shown to every crew member',
                  ),
                ),
                if (kind == OperationalBoundaryKind.altitudeBand) ...[
                  TextField(
                    controller: lowerController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Minimum altitude in metres (optional)',
                    ),
                  ),
                  TextField(
                    controller: upperController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Maximum altitude in metres (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AltitudeDatum>(
                    initialValue: datum,
                    decoration: const InputDecoration(
                      labelText: 'Altitude reference',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: AltitudeDatum.wgs84Geoid,
                        child: Text('Mean sea level / WGS84 geoid'),
                      ),
                      DropdownMenuItem(
                        value: AltitudeDatum.wgs84Ellipsoid,
                        child: Text('WGS84 ellipsoid'),
                      ),
                      DropdownMenuItem(
                        value: AltitudeDatum.relativeToLaunch,
                        child: Text('Relative to launch'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => datum = value);
                    },
                  ),
                ],
                if (validationMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      validationMessage!,
                      style: const TextStyle(color: Color(0xFFFF8A8A)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelController.text.trim();
                final source = sourceController.text.trim();
                final lower = lowerController.text.trim().isEmpty
                    ? null
                    : double.tryParse(lowerController.text.trim());
                final upper = upperController.text.trim().isEmpty
                    ? null
                    : double.tryParse(upperController.text.trim());
                final altitudeValid =
                    kind != OperationalBoundaryKind.altitudeBand ||
                    ((lower != null || upper != null) &&
                        (lower == null || upper == null || lower < upper));
                if (label.isEmpty || source.isEmpty || !altitudeValid) {
                  setDialogState(() {
                    validationMessage = label.isEmpty || source.isEmpty
                        ? 'Add a name and source.'
                        : 'Add at least one limit, with the minimum below the maximum.';
                  });
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _OperationalBoundaryDraft(
                    id: 'boundary-${DateTime.now().microsecondsSinceEpoch}',
                    label: label,
                    kind: kind,
                    source: source,
                    lowerAltitudeMeters: lower,
                    upperAltitudeMeters: upper,
                    altitudeDatum: datum,
                  ),
                );
              },
              child: Text(
                kind == OperationalBoundaryKind.altitudeBand
                    ? 'Save limits'
                    : 'Choose points on map',
              ),
            ),
          ],
        ),
      ),
    );
    labelController.dispose();
    sourceController.dispose();
    lowerController.dispose();
    upperController.dispose();
    if (draft == null || !mounted) return;
    if (kind == OperationalBoundaryKind.altitudeBand) {
      await widget.rideController.upsertOperationalBoundary(
        OperationalBoundary(
          id: draft.id,
          label: draft.label,
          kind: draft.kind,
          points: const [],
          source: draft.source,
          updatedAt: DateTime.now(),
          lowerAltitudeMeters: draft.lowerAltitudeMeters,
          upperAltitudeMeters: draft.upperAltitudeMeters,
          altitudeDatum: draft.altitudeDatum,
        ),
      );
      return;
    }
    setState(() {
      _selectedIndex = 0;
      _selectingLandingZone = false;
      _operationalBoundaryDraft = draft;
    });
    _syncOperationalBoundaries();
  }

  void _openAlertsAndReports() {
    unawaited(
      Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => _buildAwareness())),
    );
  }

  Future<void> _shareCurrentRideSummary() async {
    final session = widget.rideController.session;
    if (session == null) return;
    try {
      final renderObject = context.findRenderObject();
      final origin = renderObject is RenderBox && renderObject.hasSize
          ? renderObject.localToGlobal(Offset.zero) & renderObject.size
          : null;
      await const SystemRideSummarySharer().share(
        session,
        widget.rideController.events,
        distanceUnit: widget.distanceUnits.value,
        sharePositionOrigin: origin,
        // Attached only when an instrumented build was recording, and only ever
        // to a recipient the rider picks in the share sheet (#419).
        diagnostics: _renderedDiagnostics,
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share flight summary: $error')),
      );
    }
  }

  /// The same identity the relay receives, so a report can be tied to the build
  /// that produced it.
  static String get _diagnosticsBuildLabel {
    final descriptor = RelayClientDescriptor.current();
    return '${descriptor.appVersion}+${descriptor.appBuild}';
  }

  /// The recorded log as it would be shared, or null when nothing was recorded.
  ///
  /// One rendering, used by both the share sheet and the stored copy, so a log on
  /// disk cannot differ from the one that was handed over (#456).
  String? get _renderedDiagnostics {
    final recorder = _diagnostics;
    final session = widget.rideController.session;
    if (recorder == null || session == null || recorder.isEmpty) return null;
    return recorder.render(
      rideCode: session.rideCode,
      appBuild: _diagnosticsBuildLabel,
    );
  }

  void _startDiagnostics(String note) {
    _diagnostics = RideDiagnosticsRecorder(
      // Each entry keeps the stored log in step, so a force-quit costs nothing
      // (#456). Coalesced inside the writer, not written once per entry.
      onEntry: _markDiagnosticsDirty,
    );
    _diagnostics!.recordNote(note);
  }

  /// The switch moved. Recording follows it, whenever it happens (#457).
  void _onRideDiagnosticsChanged() {
    final recorder = _diagnostics;
    switch (rideDiagnosticsTransition(
      switchedOn: widget.rideDiagnostics?.isOn ?? false,
      hasRecorder: recorder != null,
      isRecording: recorder?.isRecording ?? false,
    )) {
      case RideDiagnosticsTransition.start:
        _startDiagnostics(rideDiagnosticsStartedMidRideNote);
      case RideDiagnosticsTransition.resume:
        recorder!.resumeRecording();
      case RideDiagnosticsTransition.stop:
        recorder!.stopRecording();
        // Written out now: a rider who switches off has usually just captured the
        // thing they were after, and the next thing they do may be to quit.
        unawaited(_diagnosticsWriter?.flush());
      case RideDiagnosticsTransition.nothing:
        break;
    }
  }

  /// Keeps the stored log in step, building the writer the first time there is
  /// both something to write and a ride to key it on.
  void _markDiagnosticsDirty() {
    (_diagnosticsWriter ??= _buildDiagnosticsWriter())?.markDirty();
  }

  RideDiagnosticsLogWriter? _buildDiagnosticsWriter() {
    final store = widget.rideDiagnostics?.logStore;
    final recorder = _diagnostics;
    final session = widget.rideController.session;
    // Returning null leaves the field null, so this is retried on the next entry
    // rather than deciding once — a shell can record its first note before its
    // session exists.
    if (store == null || recorder == null || session == null) return null;
    return RideDiagnosticsLogWriter(
      store: store,
      rideId: session.rideId,
      render: () => recorder.render(
        rideCode: session.rideCode,
        appBuild: _diagnosticsBuildLabel,
      ),
    );
  }

  /// The log for the ride just ended, for the share on the summary screen.
  ///
  /// Falls back to the stored copy: the recorder is still in memory here, but the
  /// same screen is reached from a restored ride whose recording happened in a
  /// previous run of the app.
  Future<String?> _endedRideDiagnostics() async {
    final inMemory = _renderedDiagnostics;
    if (inMemory != null) return inMemory;
    final store = widget.rideDiagnostics?.logStore;
    final session = widget.rideController.session;
    if (store == null || session == null) return null;
    return store.read(session.rideId);
  }

  bool get _relayCanCarryReopen =>
      _internetRelayController?.supportsCapability(
        RelayProtocolCapabilities.rideReopen,
      ) ??
      true;

  List<RideDestination> get _rideDestinations =>
      rideDestinations(simulation: _isSimulation);

  /// The way off the map while the navigation bar is hidden.
  ///
  /// #404: once a ride is under way on the map tab, with a route and a
  /// navigation fix, `hideWhileMoving` removes the whole bar — and the
  /// condition includes `_selectedIndex == 0`, so hiding the only control that
  /// can change the index kept it hidden for the rest of the ride. Ride and
  /// Settings became unreachable, and the map's own corner menu could not
  /// help because [RideMapFeature.onOpenRideMenu] was never supplied here: the
  /// button #133 added rendered in widget tests and never in the app.
  ///
  /// A sheet rather than restoring the bar, because the bar is hidden for a
  /// real reason — it flashed the native map as it was inserted and removed
  /// while GPS speed dipped at lights. This appears only when the rider asks
  /// for it.
  Future<void> _openRideMenu() async {
    final destinations = _rideDestinations;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // #415's control, and the reason it lives here rather than in the
            // action cluster: SOS, LEAVE and REPORT are a measured arrangement
            // (#133, #142) sized to a 280 px landscape rail, and a fourth target
            // in it would reflow the row a rider learns by feel. This is one
            // press of a fixed-corner control away, and it says in words what it
            // will do — which is what "I didn't spot the controls to mute" asked
            // for.
            if (widget.spokenGuidance case final guidance?)
              AnimatedBuilder(
                animation: guidance,
                builder: (context, _) => ListTile(
                  key: const Key('ride-menu-voice'),
                  leading: Icon(switch (guidance.mode) {
                    SpokenAudioMode.everything => Icons.volume_up,
                    SpokenAudioMode.alertsOnly => Icons.notifications_active,
                    SpokenAudioMode.silent => Icons.volume_off,
                  }),
                  title: Text(spokenAudioModeLabel(guidance.mode)),
                  subtitle: Text(
                    'Tap for ${spokenAudioModeLabel(guidance.nextMode).toLowerCase()}',
                  ),
                  onTap: () => unawaited(guidance.cycleMode()),
                ),
              ),
            const Divider(height: 1),
            for (final destination in destinations)
              ListTile(
                key: Key('ride-menu-destination-${destination.index}'),
                leading: Icon(
                  destination.index == _selectedIndex
                      ? destination.selectedIcon
                      : destination.icon,
                ),
                // Words, not a bare icon (#306), and the same words the bar
                // uses so a rider is not learning a second vocabulary.
                title: Text(destination.label),
                selected: destination.index == _selectedIndex,
                onTap: () => Navigator.of(context).pop(destination.index),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedIndex = selected);
    }
  }

  void _openRoster() {
    unawaited(
      RideRosterSheet.show(
        context,
        widget.rideController,
        legacyPeerRiderIds: _legacyPeerRiderIds,
      ),
    );
  }

  /// Riders the live presence channel has already identified as running an
  /// older build. Such a build predates the TEC-request event entirely, so it
  /// will skip it — which is why the leader is told by name before asking rather
  /// than watching the request sit unanswered.
  Set<String> get _legacyPeerRiderIds => {
    for (final limitation
        in _preStartPresenceController?.limitations ?? const [])
      if (limitation.kind == PresenceLimitationKind.peerAppOlder &&
          limitation.riderId != null)
        limitation.riderId!,
  };

  /// Opens the route's manoeuvre list while the map is in navigation mode and
  /// its own menu is hidden. It reads persisted route data only.
  void _openManeuverList() {
    unawaited(
      ManeuverListScreen.show(
        context,
        route: _activeRoute,
        distanceUnit: widget.distanceUnits.value,
        riderPosition: _mapPosition.value,
      ),
    );
  }

  Future<void> _openObserverAccess() async {
    final controller = _observerAccessController;
    if (controller == null) return;
    await ObserverAccessSheet.show(
      context,
      controller,
      canShareGroup:
          widget.rideController.coordinationMode.isGroup &&
          widget.rideController.isLocalRideLeader,
    );
    if (!mounted || !controller.hasActiveGrants) return;
    await _locationController?.requestAndStart();
    _publishObserverSnapshot();
  }

  void _publishObserverSnapshot() {
    final controller = _observerAccessController;
    final session = widget.rideController.session;
    if (controller == null || session == null || !controller.hasActiveGrants) {
      return;
    }
    final sample = _latestObserverLocationSample;
    final generatedAt = controller.nextSnapshotGeneratedAt();
    final rideStatus = widget.rideController.rideEnded
        ? 'ended'
        : widget.rideController.ridePaused
        ? 'paused'
        : widget.rideController.rideStarted
        ? 'active'
        : 'waiting';
    final statusUpdatedAt = _observerStatusUpdatedAt();
    final assistanceUpdatedAt = controller.localAssistanceUpdatedAt;
    final liveView = widget.rideController.liveView;
    controller.publishSnapshots(
      rider: buildLocalObserverSnapshot(
        session: session,
        snapshotGeneratedAt: generatedAt,
        rideStatus: rideStatus,
        statusUpdatedAt: statusUpdatedAt,
        assistanceUpdatedAt: assistanceUpdatedAt,
        localLocation: sample,
        assistance: controller.localAssistance,
      ),
      group:
          widget.rideController.coordinationMode.isGroup &&
              widget.rideController.isLocalRideLeader
          ? buildGroupObserverSnapshot(
              session: session,
              snapshotGeneratedAt: generatedAt,
              rideStatus: rideStatus,
              statusUpdatedAt: statusUpdatedAt,
              assistanceUpdatedAt: assistanceUpdatedAt,
              liveParticipants: liveView.liveParticipants,
              renderedPositions: liveView.renderedPositions,
              localLocation: sample,
              route: _activeRoute,
            )
          : null,
    );
  }

  DateTime _observerStatusUpdatedAt() {
    for (final event in widget.rideController.events.reversed) {
      if (event.type == RideEventType.rideStarted ||
          event.type == RideEventType.ridePaused ||
          event.type == RideEventType.rideResumed ||
          event.type == RideEventType.rideEnded) {
        return event.createdAt;
      }
    }
    return widget.rideController.session?.joinedAt ?? DateTime.now();
  }

  /// Switches to the map tab and asks it to open its route picker. The route
  /// picker itself lives entirely in [RideMapScreen] (it alone owns the
  /// on-disk route file), so this only ever hands it a fresh token to react
  /// to - never duplicates its import/demo-route/destination logic here.
  /// Explicitly clears any pending shared file: without that, a stale one
  /// from an earlier "Open in..." delivery would silently skip the picker
  /// this menu action is supposed to show.
  void _requestRouteChange() {
    setState(() {
      _selectedIndex = 0;
      _changeRouteRequestToken = Object();
      _pendingSharedGpxFile = null;
      _pendingInAppRoute = null;
    });
  }

  /// The map screen is rebuilt from scratch every time the tab switch leaves
  /// and returns to it (no keep-alive), so it cannot remember "already
  /// handled" across that round trip. Only this State survives, so it alone
  /// can safely null the token back out once the request has been actioned.
  void _clearChangeRouteRequest() {
    if (_changeRouteRequestToken != null) {
      setState(() {
        _changeRouteRequestToken = null;
        _pendingSharedGpxFile = null;
        _pendingInAppRoute = null;
      });
    }
  }

  /// The app deliberately never collects phone numbers (anonymous ride
  /// codes, no accounts), so it can't create a WhatsApp/Signal/iMessage
  /// group directly. This gives the leader a ready-to-paste roster for
  /// whichever group they create themselves.
  void _shareRoster() {
    final session = widget.rideController.session;
    if (session == null) return;
    final riders = <String>[];
    String labelFor(String name, RideRole role) => switch (role) {
      RideRole.lead => '$name (Lead)',
      _ => name,
    };
    riders.add(labelFor(session.displayName, session.role));
    if (_isSimulation) {
      for (final rider in _simulationController?.riders ?? const []) {
        if (!rider.isLocal) riders.add(labelFor(rider.displayName, rider.role));
      }
    } else {
      for (final rider in _awarenessController?.riderLocations ?? const []) {
        if (rider.riderId != session.localRiderId) {
          riders.add(labelFor(rider.displayName, rider.role));
        }
      }
    }
    final title = session.rideName ?? 'Balloon Crumbs flight';
    final text = [
      title,
      'Flight code: ${session.rideCode}',
      '',
      ...riders,
    ].join('\n');
    unawaited(
      SharePlus.instance.share(
        ShareParams(text: text, subject: 'Crew on $title'),
      ),
    );
  }

  Widget _buildSimulation() {
    final controller = _simulationController;
    if (_loading || controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return RideSimulationScreen(
      controller: controller,
      distanceUnit: widget.distanceUnits.value,
      onRestart: _restartSimulation,
      onExit: _leaveRide,
      onRoleChanged: _setSimulationRole,
      onRiderCountChanged: _restartSimulationWithRiderCount,
    );
  }

  Future<void> _setSimulationRole(RideRole role) async {
    final controller = _simulationController;
    if (controller == null) return;
    controller.setLocalRole(role);
    if (role == RideRole.lead) {
      _latestNavigationGuidance = null;
      _guidanceManeuverIdentity = null;
      _lastGuidanceManeuverPosition = null;
      _passedManeuverPosition = null;
      unawaited(_spokenGuidance?.stop());
    }
    await widget.rideController.setRole(role);
  }

  Future<void> _restartSimulation() async {
    _simulationController?.pause();
    await widget.rideController.restartSimulationRide();
  }

  Future<void> _restartSimulationWithRiderCount(int riderCount) async {
    final simulation = _simulationController;
    if (simulation == null || riderCount == simulation.riderCount) return;
    simulation.pause();
    await widget.rideController.restartSimulationRide(riderCount: riderCount);
  }

  Widget _buildDetails() => RideDashboard(
    controller: widget.rideController,
    distanceUnits: widget.distanceUnits,
    rideActions: _buildRideActions(),
    onOpenRoster: _openRoster,
    relayController: _relayController,
    internetRelayController: _internetRelayController,
    onSendQuickMessage: _sendLocalQuickMessage,
    localObserverAssistanceActive:
        _observerAccessController?.localAssistance != null,
    serviceWarning: _warnings.isEmpty ? null : _warnings.join('\n'),
    connectivity: _connectivitySummary,
  );

  Widget _buildSettings() => SafeArea(
    child: UnitSettingsSheet(
      controller: widget.distanceUnits,
      mapStyleMode: widget.mapStyleMode,
      riderProfile: widget.riderProfile,
      speedLimitDisplay: widget.speedLimitDisplay,
      chaseVehicle: widget.chaseVehicle,
      routeProgressDisplay: widget.routeProgressDisplay,
      currentRideActive: true,
      lastRelaySync: _internetRelayController?.status.lastSuccessfulSync,
      testControl: widget.testControl,
      spokenGuidance: widget.spokenGuidance,
      rideDiagnostics: widget.rideDiagnostics,
      embedded: true,
    ),
  );

  /// The one connectivity answer, built here because this is the only place that
  /// sees both channels: the event batch's own status and the presence channel's
  /// verdict on live positions (#174).
  RideConnectivitySummary? get _connectivitySummary {
    final internet = _internetRelayController;
    if (internet == null) return null;
    final status = internet.status;
    return RideConnectivitySummary.from(
      transportActive:
          status.phase != InternetRelayPhase.unconfigured &&
          status.phase != InternetRelayPhase.stopped,
      positionsPaused: widget.rideController.positionChannelUnavailable,
      queuedEventCount: status.pendingEventCount,
      lastSuccessfulSync: status.lastSuccessfulSync,
      now: DateTime.now(),
    );
  }

  Future<route_domain.GeoPoint?> _acquireCurrentPosition() async {
    final existing = _mapPosition.value;
    if (existing != null) return existing;
    final locationController = _locationController;
    if (locationController == null) return null;

    final completer = Completer<route_domain.GeoPoint?>();
    void onPosition() {
      final position = _mapPosition.value;
      if (position != null && !completer.isCompleted) {
        completer.complete(position);
      }
    }

    _mapPosition.addListener(onPosition);
    try {
      await locationController.requestAndStart();
      // requestAndStart can resume an already-active iOS stream whose latest
      // fix has not changed far enough to trigger the 10 m distance filter.
      // Rebuild the map from that retained fix instead of waiting for movement.
      _updateMapOverlays();
      onPosition();
      if (!locationController.status.canSample && !completer.isCompleted) {
        return null;
      }
      return await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => _mapPosition.value,
      );
    } finally {
      _mapPosition.removeListener(onPosition);
    }
  }

  Widget _buildAwareness() {
    final awareness = _awarenessController;
    if (_loading || awareness == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return SituationalAwarenessScreen(
      controller: awareness,
      rideStarted: widget.rideController.rideStarted,
      locationController: widget.enableNativeServices && !_isSimulation
          ? _locationController
          : null,
      onLocationStopped: _clearPreStartPresence,
      trafficRerouteHazards: _trafficRerouteHazards,
      trafficRerouting: _trafficRerouting,
      trafficRerouteError: _trafficRerouteError,
      onReviewTrafficAlternative: _trafficRerouteHazards.isEmpty
          ? null
          : _reviewTrafficAlternative,
      onDismissTrafficAlternative: _trafficRerouteHazards.isEmpty
          ? null
          : _dismissTrafficAlternative,
    );
  }

  Future<void> _clearPreStartPresence() async {
    if (!widget.rideController.rideStarted) {
      await _preStartPresenceController?.clearLocalPosition();
    }
  }

  Future<void> _removeEndedRide() async {
    final rideId = widget.rideController.session?.rideId;
    if (rideId != null) await _internetCursorStore?.clear(rideId);
    await widget.rideController.clearEndedRide();
  }

  Future<void> _leaveRide() async {
    _simulationController?.pause();
    await _preStartPresenceController?.stop();
    await _pushNotificationController?.stop();
    final rideId = widget.rideController.session?.rideId;
    if (rideId != null) await _internetCursorStore?.clear(rideId);
    await widget.rideController.leaveRide(
      publishDeparture: (departure) async {
        await _relayController?.publish(departure);
        await _internetRelayController?.synchronizeNow();
      },
    );
  }

  Future<void> _joinGroupBeforeStart() async {
    final onRequested = widget.onJoinGroupRequested;
    final controller = widget.rideController;
    if (onRequested == null ||
        controller.rideStarted ||
        controller.busy ||
        controller.coordinationMode != RideCoordinationMode.solo ||
        !controller.hasFlightAuthority) {
      return;
    }
    await _leaveRide();
    // Leaving rebuilds the app without this ride-scoped shell. The callback is
    // captured first so it remains safe to invoke after that disposal.
    onRequested();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Setting an ended ride aside tears this shell down, and with it the only
    // copy of the log that was ever in memory (#456).
    unawaited(_diagnosticsWriter?.flush());
    widget.rideDiagnostics?.removeListener(_onRideDiagnosticsChanged);
    widget.spokenGuidance?.removeListener(_onSpokenGuidanceChanged);
    unawaited(_screenAwakeCoordinator.stop());
    widget.rideController.removeListener(_onRideControllerChanged);
    widget.sharedRoutes.removeListener(_onSharedRoutesChanged);
    _simulationController?.removeListener(_onSimulationVisualChanged);
    _simulationController?.dispose();
    _windForecastController?.removeListener(_onWindForecastChanged);
    _windForecastController?.dispose();
    _simulationLandingZone.dispose();
    _sharedLandingZone.dispose();
    _preStartPresenceController?.removeListener(_onPreStartPresenceChanged);
    unawaited(_spokenGuidance?.stop());
    _awarenessController?.removeListener(_onAwarenessChanged);
    if (_awarenessController case final awareness?) {
      widget.testControlRegistry?.withdraw(awareness);
    }
    _awarenessController?.dispose();
    unawaited(_receivedEventSubscription?.cancel());
    unawaited(_internetReceivedEventSubscription?.cancel());
    unawaited(_pushOpenSubscription?.cancel());
    _stalenessTimer?.cancel();
    _externalHazardTimer?.cancel();
    _locationController?.removeListener(_onDeviceLocationChanged);
    _locationController?.dispose();
    unawaited(_relayController?.close());
    unawaited(_internetRelayController?.close());
    unawaited(_preStartPresenceController?.close());
    _pushNotificationController?.removeListener(
      _onPushNotificationStatusChanged,
    );
    unawaited(_pushNotificationController?.close());
    _observerAccessController?.dispose();
    _mapPosition.dispose();
    _mapNavigationPosition.dispose();
    _mapOverlays.dispose();
    _riderTrails.dispose();
    _quickMessageAlerts.dispose();
    _enforcementAlert.dispose();
    _rideCompletionSuggestion.dispose();
    unawaited(_carPlayBridge?.dispose());
    _carPlayRoutingClient.close();
    _windForecastClient.close();
    super.dispose();
  }
}

LocationSample? _newestLocationSample(
  LocationSample? journalSample,
  LocationSample? deviceSample,
) {
  if (journalSample == null) return deviceSample;
  if (deviceSample == null) return journalSample;
  return deviceSample.recordedAt.isAfter(journalSample.recordedAt)
      ? deviceSample
      : journalSample;
}

String _trafficDurationLabel(Duration duration) {
  final minutes = (duration.inSeconds / 60).round();
  if (minutes < 1) return '${duration.inSeconds} sec';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
}
