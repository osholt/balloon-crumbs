import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/distance_unit_controller.dart';
import '../../controllers/internet_relay_controller.dart';
import '../../controllers/ride_controller.dart';
import '../../controllers/nearby_relay_controller.dart';
import '../../domain/altitude.dart';
import '../../domain/flight_role.dart';
import '../../domain/imported_route.dart';
import '../../domain/quick_message.dart';
import '../../domain/ride_coordination_mode.dart';
import '../../domain/ride_event.dart';
import '../../services/flight_plan_summary.dart';
import '../../services/open_meteo_wind.dart';
import '../../services/ride_connectivity_summary.dart';
import '../internet/internet_relay_status_card.dart';
import '../map/ride_map_feature.dart';
import '../nearby/relay_status_card.dart';
import 'ride_invitation_qr_sheet.dart';

class RideDashboard extends StatelessWidget {
  const RideDashboard({
    super.key,
    required this.controller,
    required this.distanceUnits,
    required this.rideActions,
    required this.onOpenRoster,
    this.relayController,
    this.internetRelayController,
    this.onSendQuickMessage,
    this.localObserverAssistanceActive = false,
    this.serviceWarning,
    this.connectivity,
    this.sharedFlightPlan,
    this.vehicleRoadRoute,
    this.navigationPosition,
    this.windForecast,
    this.chaseGuidanceLabel,
    this.onUpdateFlightPlan,
    this.onUpdateLandingArea,
    this.onChooseChaseGuidance,
  });

  final RideController controller;
  final DistanceUnitController distanceUnits;
  final Widget rideActions;
  final VoidCallback onOpenRoster;
  final NearbyRelayController? relayController;
  final InternetRelayController? internetRelayController;
  final Future<void> Function(QuickMessage)? onSendQuickMessage;

  final bool localObserverAssistanceActive;
  final String? serviceWarning;

  /// The reconciled answer to "is the group seeing where I am".
  final RideConnectivitySummary? connectivity;
  final ImportedRoute? sharedFlightPlan;
  final ImportedRoute? vehicleRoadRoute;
  final ValueListenable<MapNavigationPosition?>? navigationPosition;
  final WindForecastController? windForecast;
  final String? chaseGuidanceLabel;
  final VoidCallback? onUpdateFlightPlan;
  final VoidCallback? onUpdateLandingArea;
  final VoidCallback? onChooseChaseGuidance;

  @override
  Widget build(BuildContext context) {
    final session = controller.session!;
    final mode = controller.coordinationMode;
    final isSolo = mode == RideCoordinationMode.solo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balloon Crumbs'),
        backgroundColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RideHeader(
                    rideCode: session.rideCode,
                    displayName: session.displayName,
                    role: session.flightRole,
                    craftLabel:
                        controller.localCraft?.craft.label ??
                        (session.flightRole.isAboardBalloon
                            ? 'Balloon'
                            : 'Unassigned craft'),
                    coordinationMode: mode,
                    onRoleChanged: controller.setFlightRole,
                  ),
                  const SizedBox(height: 14),
                  _RoleLivePanel(
                    role: session.flightRole,
                    sharedFlightPlan: sharedFlightPlan,
                    vehicleRoadRoute: vehicleRoadRoute,
                    navigationPosition: navigationPosition,
                    windForecast: windForecast,
                    landingAreaLabel: controller.landingZone?.label,
                    landingAreaUpdatedAt: controller.landingZone?.updatedAt,
                    chaseGuidanceLabel: chaseGuidanceLabel,
                    onUpdateFlightPlan: onUpdateFlightPlan,
                    onUpdateLandingArea: onUpdateLandingArea,
                    onChooseChaseGuidance: onChooseChaseGuidance,
                  ),
                  rideActions,
                  // One answer above the per-channel cards (#174). Three accurate
                  // cards that disagreed left a rider unable to tell whether the
                  // app was working; the channels keep their own detail below.
                  if (!isSolo) ...[
                    if (connectivity case final connectivity?) ...[
                      const SizedBox(height: 14),
                      _ConnectivitySummaryCard(summary: connectivity),
                    ],
                    const SizedBox(height: 6),
                    ExpansionTile(
                      key: const Key('flight-technical-details'),
                      leading: const Icon(Icons.hub_outlined),
                      title: const Text('Connection and technical details'),
                      subtitle: const Text(
                        'Crew presence, offline queue and relay channels',
                      ),
                      children: [
                        _ConnectionCard(
                          controller: controller,
                          onOpenRoster: onOpenRoster,
                        ),
                        if (relayController case final relayController?) ...[
                          const SizedBox(height: 8),
                          RelayStatusCard(controller: relayController),
                        ],
                        if (internetRelayController
                            case final internetRelayController?) ...[
                          const SizedBox(height: 8),
                          InternetRelayStatusCard(
                            controller: internetRelayController,
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (serviceWarning case final warning?) ...[
                    const SizedBox(height: 14),
                    _ServiceWarning(message: warning),
                  ],
                  if (!isSolo) ...[
                    const SizedBox(height: 22),
                    Text(
                      'QUICK MESSAGES',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF8D98A7),
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    QuickMessageGrid(
                      busy: controller.busy,
                      onSend: onSendQuickMessage ?? controller.sendQuickMessage,
                      showResolved: localObserverAssistanceActive,
                    ),
                    const SizedBox(height: 22),
                    _RideCodeCard(controller: controller),
                  ],
                  const SizedBox(height: 12),
                  ExpansionTile(
                    key: const Key('flight-event-history'),
                    leading: const Icon(Icons.history),
                    title: const Text('Flight event history'),
                    subtitle: const Text('Local offline-safe journal'),
                    children: [_EventTimeline(controller: controller)],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RideHeader extends StatelessWidget {
  const _RideHeader({
    required this.rideCode,
    required this.displayName,
    required this.role,
    required this.craftLabel,
    required this.coordinationMode,
    required this.onRoleChanged,
  });

  final String rideCode;
  final String displayName;
  final FlightRole role;
  final String craftLabel;
  final RideCoordinationMode coordinationMode;
  final ValueChanged<FlightRole> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF252E39), Color(0xFF171D25)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF343F4C)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coordinationMode == RideCoordinationMode.solo
                      ? 'SOLO FLIGHT'
                      : 'FLIGHT $rideCode',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${role.label} · $craftLabel',
                  style: const TextStyle(color: Color(0xFFABB5C1)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (coordinationMode != RideCoordinationMode.solo && role.isChasing)
            DropdownButtonHideUnderline(
              child: DropdownButton<FlightRole>(
                value: role,
                borderRadius: BorderRadius.circular(14),
                items: const [FlightRole.chaseDriver, FlightRole.chaseCrew]
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onRoleChanged(value);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleLivePanel extends StatelessWidget {
  const _RoleLivePanel({
    required this.role,
    required this.sharedFlightPlan,
    required this.vehicleRoadRoute,
    required this.navigationPosition,
    required this.windForecast,
    required this.landingAreaLabel,
    required this.landingAreaUpdatedAt,
    required this.chaseGuidanceLabel,
    required this.onUpdateFlightPlan,
    required this.onUpdateLandingArea,
    required this.onChooseChaseGuidance,
  });

  final FlightRole role;
  final ImportedRoute? sharedFlightPlan;
  final ImportedRoute? vehicleRoadRoute;
  final ValueListenable<MapNavigationPosition?>? navigationPosition;
  final WindForecastController? windForecast;
  final String? landingAreaLabel;
  final DateTime? landingAreaUpdatedAt;
  final String? chaseGuidanceLabel;
  final VoidCallback? onUpdateFlightPlan;
  final VoidCallback? onUpdateLandingArea;
  final VoidCallback? onChooseChaseGuidance;

  @override
  Widget build(BuildContext context) {
    final position = navigationPosition;
    if (position == null) return _buildForPosition(context, null);
    return ValueListenableBuilder<MapNavigationPosition?>(
      valueListenable: position,
      builder: (context, value, _) => _buildForPosition(context, value),
    );
  }

  Widget _buildForPosition(
    BuildContext context,
    MapNavigationPosition? position,
  ) {
    final wind = windForecast;
    if (wind == null) return _buildCard(context, position, null);
    return AnimatedBuilder(
      animation: wind,
      builder: (context, _) => _buildCard(context, position, wind),
    );
  }

  Widget _buildCard(
    BuildContext context,
    MapNavigationPosition? position,
    WindForecastController? wind,
  ) {
    final summary = FlightPlanSummary.fromRoute(sharedFlightPlan);
    final (icon, title, detail) = switch (role) {
      FlightRole.pilot => (
        Icons.air_outlined,
        'Pilot flight deck',
        'Airborne telemetry, wind and the shared forecast. Road directions and speed limits stay hidden.',
      ),
      FlightRole.balloonCrew => (
        Icons.air,
        'Airborne crew',
        'Read-only flight profile, wind and pilot landing intent.',
      ),
      FlightRole.chaseDriver => (
        Icons.directions_car,
        'Driver navigation',
        'Road guidance stays focused on the selected safe rendezvous.',
      ),
      FlightRole.chaseCrew => (
        Icons.groups_2_outlined,
        'Chase coordination',
        'Shared balloon forecast, landing intent and this vehicle’s road route.',
      ),
      FlightRole.observer => (
        Icons.visibility_outlined,
        'Observer',
        'Read-only shared flight status with reduced detail.',
      ),
    };
    return Card(
      key: Key('flight-role-briefing-${role.name}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: const TextStyle(color: Color(0xFFABB5C1)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (role.isAboardBalloon) ...[
              _AirborneTelemetry(position: position),
              const SizedBox(height: 12),
              _WindSummary(wind: wind),
              const SizedBox(height: 12),
              _FlightPlanOverview(summary: summary),
              const SizedBox(height: 12),
              _LandingIntentRow(
                label: landingAreaLabel,
                updatedAt: landingAreaUpdatedAt,
                onPressed: role == FlightRole.pilot
                    ? onUpdateLandingArea
                    : null,
              ),
              if (role == FlightRole.pilot && onUpdateFlightPlan != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('pilot-update-flight-plan'),
                    onPressed: onUpdateFlightPlan,
                    icon: const Icon(Icons.route_outlined),
                    label: Text(
                      summary == null
                          ? 'Add forecast flight plan'
                          : 'Replace forecast flight plan',
                    ),
                  ),
                ),
            ] else if (role.isChasing) ...[
              _ChaseTargetRow(
                label: chaseGuidanceLabel,
                onPressed: onChooseChaseGuidance,
              ),
              const SizedBox(height: 12),
              _RoadRouteOverview(route: vehicleRoadRoute),
              if (role == FlightRole.chaseCrew) ...[
                const SizedBox(height: 12),
                _FlightPlanOverview(summary: summary),
                const SizedBox(height: 12),
                _LandingIntentRow(
                  label: landingAreaLabel,
                  updatedAt: landingAreaUpdatedAt,
                ),
                const SizedBox(height: 12),
                _WindSummary(wind: wind),
              ],
            ] else ...[
              _FlightPlanOverview(summary: summary, reduced: true),
              const SizedBox(height: 12),
              _LandingIntentRow(
                label: landingAreaLabel,
                updatedAt: landingAreaUpdatedAt,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AirborneTelemetry extends StatelessWidget {
  const _AirborneTelemetry({required this.position});

  final MapNavigationPosition? position;

  @override
  Widget build(BuildContext context) {
    final fix = position;
    final altitude = fix?.altitudeMeters;
    final verticalRate = fix?.verticalSpeedMetersPerSecond;
    final fixAge = fix == null
        ? null
        : DateTime.now().difference(fix.recordedAt);
    return Container(
      key: const Key('airborne-live-telemetry'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: 'ALTITUDE',
              value: altitude == null ? 'Unavailable' : '${altitude.round()} m',
              detail: altitude == null
                  ? 'No altitude fix'
                  : '${_altitudeSourceLabel(fix!.altitudeSource)} · ${_altitudeDatumLabel(fix.altitudeDatum)}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Metric(
              label: 'VERTICAL RATE',
              value: verticalRate == null
                  ? 'Unavailable'
                  : '${verticalRate >= 0 ? '+' : ''}${verticalRate.toStringAsFixed(1)} m/s',
              detail: fixAge == null
                  ? 'No fix'
                  : 'Fix ${_compactAge(fixAge)} ago',
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF8D98A7),
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(
        detail,
        style: const TextStyle(color: Color(0xFF98A3B1), fontSize: 12),
      ),
    ],
  );
}

class _WindSummary extends StatelessWidget {
  const _WindSummary({required this.wind});

  final WindForecastController? wind;

  @override
  Widget build(BuildContext context) {
    final controller = wind;
    final field = controller?.field;
    final enabled = controller?.enabled ?? false;
    final level = controller?.selectedAltitudeMetersMsl;
    return _InformationRow(
      key: const Key('role-wind-summary'),
      icon: Icons.air,
      title: enabled && level != null
          ? 'Forecast wind · $level m MSL'
          : 'Forecast wind off',
      detail: field == null
          ? controller?.loading == true
                ? 'Loading Open-Meteo forecast…'
                : 'No wind forecast loaded'
          : '${field.sourceLabel} · valid ${_formatTime(context, field.validAt)} · fetched ${_compactAge(DateTime.now().difference(field.fetchedAt))} ago. Forecast model only; not an aviation briefing.',
    );
  }
}

class _FlightPlanOverview extends StatelessWidget {
  const _FlightPlanOverview({required this.summary, this.reduced = false});

  final FlightPlanSummary? summary;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final plan = summary;
    if (plan == null) {
      return const _InformationRow(
        key: Key('role-flight-plan-summary'),
        icon: Icons.route_outlined,
        title: 'No shared flight forecast',
        detail: 'The pilot has not shared a timed altitude plan.',
      );
    }
    final times = plan.startTime == null
        ? 'Start time unavailable'
        : plan.landingTime == null
        ? 'Start ${_formatTime(context, plan.startTime!)}'
        : '${_formatTime(context, plan.startTime!)}–${_formatTime(context, plan.landingTime!)}';
    final duration = plan.duration == null
        ? null
        : _formatDuration(plan.duration!);
    final altitude = plan.maximumAltitudeMetersMsl == null
        ? null
        : 'max ${plan.maximumAltitudeMetersMsl!.round()} m MSL';
    final climb = plan.maximumAscentRateMetersPerSecond == null
        ? null
        : 'climb ${plan.maximumAscentRateMetersPerSecond!.toStringAsFixed(1)} m/s';
    final descent = plan.maximumDescentRateMetersPerSecond == null
        ? null
        : 'descent ${plan.maximumDescentRateMetersPerSecond!.toStringAsFixed(1)} m/s';
    final detail = [
      times,
      duration,
      altitude,
      climb,
      descent,
    ].whereType<String>().join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InformationRow(
          key: const Key('role-flight-plan-summary'),
          icon: Icons.route_outlined,
          title: plan.routeName,
          detail: '$detail. Forecast path only; actual drift may differ.',
        ),
        if (!reduced && plan.stages.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('flight-plan-altitude-stages'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('${plan.stages.length} altitude and time stages'),
            subtitle: const Text('Launch, climb, descent and landing forecast'),
            children: [
              for (final stage in plan.stages)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 8, right: 4),
                  leading: Icon(_stageIcon(stage.phase), size: 19),
                  title: Text(stage.label),
                  subtitle: Text(
                    stage.time == null
                        ? 'Time unavailable'
                        : _formatTime(context, stage.time!),
                  ),
                  trailing: Text(
                    stage.altitudeMetersMsl == null
                        ? '—'
                        : '${stage.altitudeMetersMsl!.round()} m MSL',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LandingIntentRow extends StatelessWidget {
  const _LandingIntentRow({
    required this.label,
    required this.updatedAt,
    this.onPressed,
  });

  final String? label;
  final DateTime? updatedAt;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _InformationRow(
    key: const Key('role-landing-intent'),
    icon: Icons.flag_outlined,
    title: label ?? 'No intended landing area',
    detail: label == null
        ? 'The pilot can set and update an approximate rendezvous area during the flight.'
        : 'Pilot intent · updated ${updatedAt == null ? 'time unavailable' : '${_compactAge(DateTime.now().difference(updatedAt!))} ago'} · access and landing suitability are unverified.',
    actionLabel: onPressed == null
        ? null
        : label == null
        ? 'Set'
        : 'Update',
    onPressed: onPressed,
  );
}

class _ChaseTargetRow extends StatelessWidget {
  const _ChaseTargetRow({required this.label, required this.onPressed});

  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _InformationRow(
    key: const Key('role-chase-target'),
    icon: Icons.assistant_direction_outlined,
    title: label ?? 'No chase target selected',
    detail:
        'Routes dynamically to a road-accessible endpoint near the selected target and never directs off-road.',
    actionLabel: onPressed == null ? null : 'Change',
    onPressed: onPressed,
  );
}

class _RoadRouteOverview extends StatelessWidget {
  const _RoadRouteOverview({required this.route});

  final ImportedRoute? route;

  @override
  Widget build(BuildContext context) {
    final roadRoute = route;
    return _InformationRow(
      key: const Key('role-road-route-summary'),
      icon: Icons.directions_car_outlined,
      title: roadRoute?.name ?? 'Road route not ready',
      detail: roadRoute == null
          ? 'Choose a target when balloon and vehicle positions are available.'
          : '${roadRoute.plannedDuration == null ? 'ETA updates while driving' : 'Planned ${_formatDuration(roadRoute.plannedDuration!)}'} · recalculates after meaningful target movement.',
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 21, color: const Color(0xFF8D98A7)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(color: Color(0xFF98A3B1), fontSize: 12),
            ),
          ],
        ),
      ),
      if (actionLabel != null && onPressed != null)
        TextButton(onPressed: onPressed, child: Text(actionLabel!)),
    ],
  );
}

IconData _stageIcon(FlightPlanStagePhase phase) => switch (phase) {
  FlightPlanStagePhase.launch => Icons.flight_takeoff,
  FlightPlanStagePhase.climb => Icons.trending_up,
  FlightPlanStagePhase.level => Icons.trending_flat,
  FlightPlanStagePhase.descend => Icons.trending_down,
  FlightPlanStagePhase.peak => Icons.vertical_align_top,
  FlightPlanStagePhase.landing => Icons.flight_land,
};

String _formatTime(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
}

String _compactAge(Duration age) {
  if (age.isNegative) return '0s';
  if (age.inSeconds < 60) return '${age.inSeconds}s';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  return '${age.inHours}h';
}

String _altitudeSourceLabel(AltitudeSource source) => switch (source) {
  AltitudeSource.gnss => 'GNSS',
  AltitudeSource.barometric => 'Barometric',
  AltitudeSource.unknown => 'Source unknown',
};

String _altitudeDatumLabel(AltitudeDatum datum) => switch (datum) {
  AltitudeDatum.wgs84Geoid => 'MSL',
  AltitudeDatum.wgs84Ellipsoid => 'WGS84 ellipsoid',
  AltitudeDatum.relativeToLaunch => 'relative to launch',
  AltitudeDatum.unknown => 'datum unknown',
};

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller, required this.onOpenRoster});

  final RideController controller;
  final VoidCallback onOpenRoster;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _StatusRow(
              icon: Icons.cloud_queue,
              title: 'Durable event queue',
              detail: '${controller.pendingEventCount} events stored locally',
              state: 'OFFLINE SAFE',
              stateColor: const Color(0xFFFFC857),
            ),
            const Divider(height: 24),
            ListTile(
              key: const Key('dashboard-open-roster'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_2_outlined),
              title: const Text('Flight crew'),
              subtitle: Text(
                '${controller.liveParticipants.length} current crew · '
                'presence and transport status',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenRoster,
            ),
          ],
        ),
      ),
    );
  }
}

/// The one connectivity answer, above the channels that produced it (#174).
class _ConnectivitySummaryCard extends StatelessWidget {
  const _ConnectivitySummaryCard({required this.summary});

  final RideConnectivitySummary summary;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (summary.state) {
      RideConnectivityState.reaching => (
        Icons.check_circle_outline,
        const Color(0xFF6ED89A),
      ),
      RideConnectivityState.degraded => (
        Icons.access_time,
        const Color(0xFFFFC857),
      ),
      RideConnectivityState.notReaching => (
        Icons.error_outline,
        const Color(0xFFFF5D73),
      ),
      RideConnectivityState.inactive => (
        Icons.cloud_off_outlined,
        const Color(0xFF8D98A7),
      ),
    };
    return Card(
      key: const Key('ride-connectivity-summary'),
      child: ListTile(
        leading: Icon(icon, color: colour),
        title: Text(
          summary.headline,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(summary.detail),
      ),
    );
  }
}

class _ServiceWarning extends StatelessWidget {
  const _ServiceWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF2B2115),
    child: ListTile(
      leading: const Icon(Icons.info_outline, color: Color(0xFFFFC857)),
      title: const Text('Service limitation'),
      subtitle: Text(message),
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.state,
    required this.stateColor,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String state;
  final Color stateColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: stateColor),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(color: Color(0xFF98A3B1), fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            state,
            style: TextStyle(
              color: stateColor,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class QuickMessageGrid extends StatelessWidget {
  const QuickMessageGrid({
    super.key,
    required this.busy,
    required this.onSend,
    this.showResolved = false,
  });

  final bool busy;
  final Future<void> Function(QuickMessage) onSend;
  final bool showResolved;

  static const _messages = [
    (QuickMessage.stopped, Icons.pause_circle_outline),
    (QuickMessage.mechanical, Icons.build_outlined),
    (QuickMessage.fuel, Icons.local_gas_station_outlined),
    (QuickMessage.assistance, Icons.sos_outlined),
    (QuickMessage.routeBlocked, Icons.block_outlined),
    (QuickMessage.emergencyStop, Icons.warning_amber_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 540 ? 3 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.35,
          children: [
            for (final (message, icon) in _messages)
              OutlinedButton.icon(
                onPressed: busy ? null : () => onSend(message),
                icon: Icon(
                  icon,
                  color: message.priority == EventPriority.critical
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                label: Text(
                  message.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (showResolved)
              OutlinedButton.icon(
                key: const Key('observer-assistance-resolved'),
                onPressed: busy ? null : () => onSend(QuickMessage.resolved),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Resolved / I’m OK'),
              ),
          ],
        );
      },
    );
  }
}

class _RideCodeCard extends StatelessWidget {
  const _RideCodeCard({required this.controller});

  final RideController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session!;
    if (!controller.hasFlightAuthority) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share this flight code',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    session.rideCode,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: session.rideCode),
                        ),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy code'),
                      ),
                      TextButton.icon(
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text: controller.rideCodeShareText,
                            subject: 'Join my Balloon Crumbs group',
                          ),
                        ),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share code'),
                      ),
                      // The only way in that needs no signal. Sharing a code or
                      // an invite both end in a relay lookup, so in a car park
                      // with no bars they do nothing at all (#279).
                      TextButton.icon(
                        key: const Key('show-invitation-qr'),
                        onPressed: () =>
                            RideInvitationQrSheet.show(context, session),
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Show QR'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTimeline extends StatelessWidget {
  const _EventTimeline({required this.controller});

  final RideController controller;

  @override
  Widget build(BuildContext context) {
    final events = controller.events.reversed.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'LOCAL EVENT JOURNAL',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF8D98A7),
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Text(
              '${events.length} shown',
              style: const TextStyle(color: Color(0xFF75808D), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No flight events yet.'),
                )
              : Column(
                  children: [
                    for (var index = 0; index < events.length; index++) ...[
                      _EventRow(event: events[index]),
                      if (index != events.length - 1)
                        const Divider(height: 1, indent: 50),
                    ],
                  ],
                ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 10),
          const Text(
            'Debug build: transport acknowledgements are not yet connected, so '
            'events correctly remain queued.',
            style: TextStyle(color: Color(0xFF6F7A87), fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final RideEvent event;

  @override
  Widget build(BuildContext context) {
    final title = switch (event.type) {
      RideEventType.rideCreated => 'Flight created',
      RideEventType.riderJoined => 'Joined flight',
      RideEventType.riderLeft => 'Left flight',
      RideEventType.roleChanged => 'Role changed',
      RideEventType.rideStarted => 'Flight started',
      // Also the acknowledgement of another rider's message, which is a
      // `statusMessage` carrying `acknowledgesQuickMessageEventId` and the label
      // "Seen: <what they raised>" (#151). One row either way: the log records
      // what went into the journal, and the ride surface is where a rider is
      // actually told (`_QuickMessageAlertCard` in the map).
      RideEventType.statusMessage =>
        event.payload['label'] as String? ?? 'Status message',
      RideEventType.riderLocationUpdated => 'Location updated',
      RideEventType.hazardReported => 'Hazard reported',
      RideEventType.hazardCleared => 'Hazard cleared',
      RideEventType.routeRevisionChunk => 'Route revision received',
      RideEventType.routeRevisionPublished => 'Group route updated',
      RideEventType.routeCleared => 'Group route cleared',
      RideEventType.ridePaused => 'Flight paused',
      RideEventType.rideResumed => 'Flight resumed',
      RideEventType.rideEnded => 'Flight ended',
      // Says what happened rather than what it undid: the journal keeps both
      // events, and a rider reading the log should see the sequence.
      RideEventType.rideReopened => 'Flight reopened by the coordinator',
      RideEventType.iceInfoShared => 'Emergency contact shared',
      RideEventType.iceInfoViewed => 'Emergency contact viewed',
      // WP3. Named by craft label rather than id: a log a crew reads at the end
      // of a ride should say "Vehicle 2 joined", not a device identifier.
      RideEventType.craftRegistered =>
        '${event.payload['label'] ?? 'A craft'} joined the flight',
      RideEventType.deviceAttachedToCraft =>
        'A device moved to ${event.payload['craftLabel'] ?? 'another craft'}',
      RideEventType.craftPrimaryDeviceNominated =>
        'Primary reporting device set for '
            '${event.payload['craftLabel'] ?? 'a craft'}',
      RideEventType.craftChaseAssigned =>
        '${event.payload['vehicleLabel'] ?? 'A vehicle'} is now chasing '
            '${event.payload['targetLabel'] ?? 'the balloon'}',
      RideEventType.landingAreaNoted => 'Intended landing area updated',
      RideEventType.windContextNoted => 'Wind context recorded for replay',
      RideEventType.operationalBoundaryUpserted =>
        'Operational boundary updated',
      RideEventType.operationalBoundaryRemoved =>
        'Operational boundary removed',
      // #188. The activity list says a number was shared and with whom, never
      // what the number is: this is a log, not a place to read a number off a
      // screen.
      RideEventType.riderContactShared =>
        event.payload['recipientRiderIds'] == null
            ? 'Phone number shared with the flight crew'
            : 'Phone number shared with the pilot and coordinator',
    };
    final time = TimeOfDay.fromDateTime(event.createdAt).format(context);
    return ListTile(
      dense: true,
      leading: Icon(
        event.acknowledged ? Icons.cloud_done_outlined : Icons.schedule_send,
        size: 20,
        color: event.acknowledged
            ? const Color(0xFF6ED89A)
            : const Color(0xFFFFC857),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(event.acknowledged ? 'Delivered' : 'Stored locally'),
      trailing: Text(time, style: const TextStyle(color: Color(0xFF7F8995))),
    );
  }
}
