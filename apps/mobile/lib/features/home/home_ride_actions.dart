import 'package:flutter/material.dart';

import '../map/ride_map_feature.dart';

/// Ride setup controls that sit on the home map.
class HomeRideActions extends StatelessWidget {
  const HomeRideActions({
    super.key,
    required this.onCreate,
    required this.onJoin,
    required this.onMore,
    required this.onSelectLandingZone,
    required this.onCancelSelection,
    required this.onPreviousLandingZones,
    required this.onRadiusChanged,
    required this.radiusMeters,
    required this.recentLandingZoneCount,
    this.landingZone,
    this.selectingLandingZone = false,
    this.enabled = true,
  });

  final VoidCallback? onCreate;
  final VoidCallback? onJoin;
  final VoidCallback onMore;
  final VoidCallback onSelectLandingZone;
  final VoidCallback onCancelSelection;
  final VoidCallback? onPreviousLandingZones;
  final ValueChanged<double> onRadiusChanged;
  final double radiusMeters;
  final int recentLandingZoneCount;
  final MapLandingZone? landingZone;
  final bool selectingLandingZone;
  final bool enabled;

  static const reservedHeight = 214.0;
  static const radiusChoices = [250.0, 500.0, 1000.0];

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('home-ride-actions'),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: const BoxDecoration(
      color: Color(0xF21A2029),
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      boxShadow: [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 14,
          offset: Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: Color(0xFFFFC857)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectingLandingZone
                          ? 'Tap the map to place the area'
                          : landingZone?.label ?? 'Intended landing area',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      selectingLandingZone
                          ? 'Pan or zoom first; the next tap sets its centre.'
                          : landingZone == null
                          ? 'Optional and approximate — access is not verified.'
                          : 'Approximate rendezvous; verify road access and permission.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFABB5C1),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('select-landing-zone'),
                onPressed: selectingLandingZone
                    ? onCancelSelection
                    : onSelectLandingZone,
                child: Text(selectingLandingZone ? 'Cancel' : 'Set on map'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'Radius',
                  style: TextStyle(
                    color: Color(0xFFABB5C1),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                for (final radius in radiusChoices) ...[
                  ChoiceChip(
                    key: Key('landing-radius-${radius.toInt()}'),
                    label: Text(radius < 1000 ? '${radius.toInt()} m' : '1 km'),
                    selected: radiusMeters == radius,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onRadiusChanged(radius),
                  ),
                  const SizedBox(width: 6),
                ],
                const SizedBox(width: 4),
                TextButton(
                  key: const Key('previous-landing-zones'),
                  onPressed: recentLandingZoneCount == 0
                      ? null
                      : onPreviousLandingZones,
                  child: Text(
                    recentLandingZoneCount == 0
                        ? 'Previous'
                        : 'Previous ($recentLandingZoneCount)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  key: const Key('home-create-flight'),
                  onPressed: enabled ? onCreate : null,
                  icon: const Icon(Icons.air_outlined),
                  label: const Text('Create flight'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  key: const Key('home-join-flight'),
                  onPressed: enabled ? onJoin : null,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Join crew'),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                key: const Key('home-more-actions'),
                onPressed: onMore,
                child: const Text('More'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
