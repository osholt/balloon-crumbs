import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/ride_simulation_controller.dart';
import '../../domain/distance_unit.dart';
import '../../domain/ride_role.dart';
import '../../domain/ride_session.dart';
import '../../services/measurement_formatter.dart';
import '../map/craft_icon.dart';

class RideSimulationScreen extends StatelessWidget {
  const RideSimulationScreen({
    super.key,
    required this.controller,
    this.distanceUnit = DistanceUnit.miles,
    required this.onRestart,
    required this.onExit,
    required this.onRoleChanged,
    required this.onRiderCountChanged,
  });

  final RideSimulationController controller;
  final DistanceUnit distanceUnit;
  final Future<void> Function() onRestart;
  final Future<void> Function() onExit;
  final Future<void> Function(RideRole role) onRoleChanged;
  final Future<void> Function(int riderCount) onRiderCountChanged;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: landscape ? 42 : 52,
        title: const Text('Ride Lab'),
        actions: [
          IconButton(
            tooltip: 'Restart simulation',
            onPressed: () => unawaited(onRestart()),
            icon: const Icon(Icons.replay),
          ),
          IconButton(
            tooltip: 'Exit simulation',
            onPressed: () => unawaited(onExit()),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final controls = _SimulationControls(
              controller: controller,
              onRoleChanged: onRoleChanged,
              onRiderCountChanged: onRiderCountChanged,
            );
            final fleet = _FleetCard(
              controller: controller,
              distanceUnit: distanceUnit,
            );
            if (landscape) {
              return Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: SingleChildScrollView(child: controls)),
                    const SizedBox(width: 10),
                    Expanded(child: SingleChildScrollView(child: fleet)),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              children: [controls, const SizedBox(height: 12), fleet],
            );
          },
        ),
      ),
    );
  }
}

class _SimulationControls extends StatelessWidget {
  const _SimulationControls({
    required this.controller,
    required this.onRoleChanged,
    required this.onRiderCountChanged,
  });

  final RideSimulationController controller;
  final Future<void> Function(RideRole role) onRoleChanged;
  final Future<void> Function(int riderCount) onRiderCountChanged;

  @override
  Widget build(BuildContext context) {
    final status = switch (controller.state) {
      RideSimulationState.ready => 'READY',
      RideSimulationState.running => 'RUNNING',
      RideSimulationState.paused => 'PAUSED',
      RideSimulationState.completed => 'FINISHED',
    };
    final statusColor = switch (controller.state) {
      RideSimulationState.running => const Color(0xFF6ED89A),
      RideSimulationState.completed => Theme.of(context).colorScheme.primary,
      _ => const Color(0xFFFFC857),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SYNTHETIC FLIGHT',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _Pill(label: status, color: statusColor),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${controller.riderCount} virtual craft use the real navigation '
              'and off-course logic. Device GPS, internet relay and nearby '
              'radios are off.',
              style: const TextStyle(color: Color(0xFFADB7C4), height: 1.35),
            ),
            const SizedBox(height: 14),
            Text(
              'YOUR VIEW',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF8F9BAA),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<RideRole>(
              key: const Key('simulation-role'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: RideRole.lead,
                  icon: CraftIcon(
                    style: CraftIconStyle.balloon,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: Text('Balloon'),
                ),
                ButtonSegment(
                  value: RideRole.rider,
                  icon: CraftIcon(
                    style: CraftIconStyle.fourByFour,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: Text('Chase'),
                ),
              ],
              selected: {controller.localRole},
              onSelectionChanged: (selection) =>
                  unawaited(onRoleChanged(selection.single)),
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: controller.progress),
            const SizedBox(height: 8),
            Text(
              '${(controller.progress * 100).round()}% route · '
              '${_duration(controller.simulatedElapsed)} simulated',
              style: const TextStyle(color: Color(0xFF8F9BAA)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Virtual riders',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DropdownButton<int>(
                  key: const Key('simulation-rider-count'),
                  value: controller.riderCount,
                  items: [
                    for (
                      var count = RideSession.minimumSimulationRiderCount;
                      count <= RideSession.maximumSimulationRiderCount;
                      count += 1
                    )
                      DropdownMenuItem(
                        value: count,
                        child: Text('$count riders'),
                      ),
                  ],
                  onChanged: (count) {
                    if (count != null && count != controller.riderCount) {
                      unawaited(onRiderCountChanged(count));
                    }
                  },
                ),
              ],
            ),
            const Text(
              'Changing the fleet starts a clean simulation.',
              style: TextStyle(color: Color(0xFF8F9BAA), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('simulation-play-pause'),
                    onPressed:
                        !controller.rideStarted ||
                            controller.state == RideSimulationState.completed
                        ? null
                        : controller.isRunning
                        ? controller.pause
                        : controller.start,
                    icon: Icon(
                      controller.isRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(
                      !controller.rideStarted
                          ? 'Waiting for start'
                          : controller.isRunning
                          ? 'Pause'
                          : 'Run',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Simulation time scale',
                  child: DropdownButton<double>(
                    key: const Key('simulation-speed'),
                    value: controller.timeScale,
                    items: const [1.0, 4.0, 8.0, 16.0]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('${value.toInt()}×'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) controller.setTimeScale(value);
                    },
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            SwitchListTile.adaptive(
              key: const Key('simulation-off-route'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Send Alex off route'),
              subtitle: const Text('Builds the magenta trail and leader alert'),
              value: controller.alexOffRoute,
              onChanged: controller.setAlexOffRoute,
            ),
            SwitchListTile.adaptive(
              key: const Key('simulation-tec-delay'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Delay the back rider'),
              subtitle: const Text('Increases the lead-to-TEC gap'),
              value: controller.backRiderDelayed,
              onChanged: controller.setBackRiderDelayed,
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const Key('simulation-hazard'),
              onPressed: () => unawaited(controller.reportRoadworks()),
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Drop roadworks 450 m ahead'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Open the Map tab to watch the production UI respond.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF7F8A98), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _FleetCard extends StatelessWidget {
  const _FleetCard({required this.controller, required this.distanceUnit});

  final RideSimulationController controller;
  final DistanceUnit distanceUnit;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('VIRTUAL FLEET', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final rider in controller.riders) ...[
            Row(
              children: [
                CraftIcon(
                  style: rider.role == RideRole.lead
                      ? CraftIconStyle.balloon
                      : rider.motorcycleStyle,
                  color: rider.isOffRoute
                      ? const Color(0xFFFF4FA3)
                      : const Color(0xFF6ED89A),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rider.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${rider.role.label} · '
                        '${MeasurementFormatter(distanceUnit).speed(rider.speedMetersPerSecond)}'
                        '${rider.altitudeMeters == null ? '' : ' · ${rider.altitudeMeters!.round()} m'}',
                        style: const TextStyle(
                          color: Color(0xFF8F9BAA),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (rider.isOffRoute)
                  const _Pill(label: 'OFF ROUTE', color: Color(0xFFFF4FA3))
                else
                  Text('${(rider.progress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(value: rider.progress, minHeight: 3),
            const SizedBox(height: 13),
          ],
        ],
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
    ),
  );
}
