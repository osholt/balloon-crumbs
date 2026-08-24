import 'package:flutter/material.dart';

import '../../domain/altitude_unit.dart';
import '../../domain/distance_unit.dart';
import '../../domain/imported_route.dart';
import '../../services/measurement_formatter.dart';
import '../../services/navigation_guidance.dart';
import '../../services/route_length.dart';

enum RouteConfirmationAction { cancel, confirm }

/// The one gate between a candidate route and the authoritative group route.
///
/// This replaces the inherited route-review screen, which was built for a job
/// the chase crew does not have: it existed to check a planned line and place
/// junction markers along it before a group ride, and a balloon has no planned
/// line to check. What that screen also did, incidentally, was tell whoever was
/// about to publish a route how long it was and what was wrong with it.
///
/// That part has to survive the deletion, because the flows it guarded do:
/// importing a GPX file, planning a route to a destination, loading the demo
/// route, and accepting a traffic alternative. A GPX file that matched badly, or
/// carries a 200 km line when the crew expected 20, must not become the group's
/// route without somebody seeing the number first.
///
/// So this is deliberately a sheet and not a screen: route name, distance,
/// duration, turn count, warnings, cancel or confirm. No map preview, no stop
/// editing, no reshaping — WP7 builds whatever chase-plan sketching turns out to
/// be worth having rather than inheriting an editor built for motorcycles.
class RouteConfirmationSheet extends StatelessWidget {
  const RouteConfirmationSheet({
    super.key,
    required this.route,
    required this.distanceUnit,
    this.altitudeUnit = AltitudeUnit.metres,
    this.distanceMeters,
    this.duration,
    this.warnings = const [],
    this.previousRoute,
  });

  final ImportedRoute route;
  final DistanceUnit distanceUnit;
  final AltitudeUnit altitudeUnit;
  final double? distanceMeters;
  final Duration? duration;
  final List<String> warnings;

  /// The route this one would replace, used only for the material-change
  /// warning. Null on a first route, when there is nothing to compare against.
  final ImportedRoute? previousRoute;

  static Future<RouteConfirmationAction> show(
    BuildContext context, {
    required ImportedRoute route,
    required DistanceUnit distanceUnit,
    AltitudeUnit altitudeUnit = AltitudeUnit.metres,
    double? distanceMeters,
    Duration? duration,
    List<String> warnings = const [],
    ImportedRoute? previousRoute,
  }) async {
    final action = await showModalBottomSheet<RouteConfirmationAction>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => RouteConfirmationSheet(
        route: route,
        distanceUnit: distanceUnit,
        altitudeUnit: altitudeUnit,
        distanceMeters: distanceMeters,
        duration: duration,
        warnings: warnings,
        previousRoute: previousRoute,
      ),
    );
    // A dismissed sheet is a cancelled route, never a confirmed one.
    return action ?? RouteConfirmationAction.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final isForecast = route.isBalloonForecast;
    final formatter = MeasurementFormatter(distanceUnit);
    final effectiveDistance = distanceMeters ?? routeLengthMeters(route);
    final forecastDuration = isForecast ? _forecastDuration(route) : null;
    final effectiveDuration = duration ?? forecastDuration;
    final maneuverCount = const NavigationGuidancePlanner()
        .instructions(route)
        .length;
    final visibleWarnings = [
      ...warnings.where((warning) => warning.trim().isNotEmpty),
      if (isForecast)
        'Forecast only: the balloon cannot follow this line. Wind, airspace '
            'and landing conditions can change; check current aviation '
            'information and landing suitability before launch.',
      if (!isForecast)
        ?materialRouteChangeWarning(previousRoute, route, distanceUnit),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isForecast ? 'Use this forecast plan?' : 'Use this route?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              route.name,
              key: const Key('confirm-route-name'),
              style: const TextStyle(color: Color(0xFF9CA7B5)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _Fact(
                  icon: Icons.straighten,
                  label: formatter.distance(effectiveDistance),
                ),
                if (effectiveDuration case final duration?)
                  _Fact(icon: Icons.schedule, label: _durationLabel(duration)),
                if (isForecast)
                  if (_maximumAltitude(route) case final altitude?)
                    _Fact(
                      icon: Icons.height,
                      label: 'Max ${altitudeUnit.altitude(altitude)} MSL',
                    )
                  else
                    const _Fact(
                      icon: Icons.height,
                      label: 'Altitude unavailable',
                    )
                else
                  _Fact(
                    icon: Icons.turn_right,
                    label: maneuverCount == 1
                        ? '1 turn'
                        : '$maneuverCount turns',
                  ),
              ],
            ),
            if (isForecast) ...[
              const SizedBox(height: 12),
              Text(
                _forecastWindow(context, route) ??
                    'The forecast time is not included in this file.',
                key: const Key('forecast-plan-time'),
                style: const TextStyle(color: Color(0xFFB9C4D1)),
              ),
              if (route.description case final description?) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF9CA7B5),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
            if (visibleWarnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Scrolls rather than truncates: a matched import can produce
              // several warnings and the last one is not the least important.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final warning in visibleWarnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: Color(0xFFFFC857),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  warning,
                                  style: const TextStyle(
                                    color: Color(0xFFD3DBE4),
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('cancel-route-confirmation'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(RouteConfirmationAction.cancel),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('confirm-route-confirmation'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(RouteConfirmationAction.confirm),
                    child: Text(
                      isForecast ? 'Use forecast plan' : 'Use this route',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  static List<GeoPoint> _forecastPoints(ImportedRoute route) => route.paths
      .expand((path) => path.points)
      .where((point) => point.recordedAt != null)
      .toList(growable: false);

  static Duration? _forecastDuration(ImportedRoute route) {
    final points = _forecastPoints(route);
    if (points.length < 2) return null;
    final duration = points.last.recordedAt!.difference(
      points.first.recordedAt!,
    );
    return duration.isNegative ? null : duration;
  }

  static double? _maximumAltitude(ImportedRoute route) => route.paths
      .expand((path) => path.points)
      .map((point) => point.elevationMeters)
      .nonNulls
      .fold<double?>(null, (highest, value) {
        if (highest == null || value > highest) return value;
        return highest;
      });

  static String? _forecastWindow(BuildContext context, ImportedRoute route) {
    final points = _forecastPoints(route);
    if (points.isEmpty) return null;
    final localizations = MaterialLocalizations.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    String time(DateTime value) => localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: use24Hour,
    );
    final start = points.first.recordedAt!.toLocal();
    final end = points.last.recordedAt!.toLocal();
    return 'Forecast ${localizations.formatMediumDate(start)} · '
        '${time(start)}–${time(end)} local';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: const Color(0xFF8F9BAA)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}
