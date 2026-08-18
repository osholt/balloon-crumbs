import 'package:latlong2/latlong.dart';

import '../domain/distance_unit.dart';
import '../domain/imported_route.dart';
import 'measurement_formatter.dart';

/// How far the vehicle will actually travel: the length of the path that will be
/// driven and tracked, not the sum of every path in the file.
///
/// Summing them reported a 23.4 mi MyRoute-app route as 47.4 mi, because that
/// export carries the journey twice - a dense calculated track and the sparse
/// waypoint route it came from (#180). The importer now drops a duplicate
/// representation, so in practice there is one path; this measures the primary
/// one regardless, because a file with two genuinely different paths must not
/// add them together either. A driver reads one number and drives one route.
///
/// "Primary" is the longest path, the same choice `RouteProgressTracker` makes,
/// so the distance shown and the distance progress is measured against cannot
/// disagree.
double routeLengthMeters(ImportedRoute route) {
  var longest = 0.0;
  for (final path in route.paths) {
    final length = _pathLengthMeters(path.points);
    if (length > longest) longest = length;
  }
  return longest;
}

double _pathLengthMeters(List<GeoPoint> points) {
  const distance = Distance();
  var total = 0.0;
  for (var index = 1; index < points.length; index += 1) {
    total += distance.as(
      LengthUnit.Meter,
      LatLng(points[index - 1].latitude, points[index - 1].longitude),
      LatLng(points[index].latitude, points[index].longitude),
    );
  }
  return total;
}

/// A warning when a candidate route is materially longer or shorter than the one
/// it would replace, or null when the change is unremarkable.
///
/// The threshold is 20%, and both routes must be over a kilometre: a short route
/// changing by a third is a rounding difference, while a long one changing by a
/// fifth means the file is not the journey the crew expected. This is the one
/// number worth interrupting a route confirmation for.
String? materialRouteChangeWarning(
  ImportedRoute? previous,
  ImportedRoute candidate,
  DistanceUnit distanceUnit,
) {
  if (previous == null) return null;
  final previousDistance = routeLengthMeters(previous);
  final candidateDistance = routeLengthMeters(candidate);
  if (previousDistance < 1000 || candidateDistance < 1000) return null;
  final change =
      (candidateDistance - previousDistance).abs() / previousDistance;
  if (change < 0.2) return null;
  final formatter = MeasurementFormatter(distanceUnit);
  return 'This route is ${(change * 100).round()}% '
      '${candidateDistance > previousDistance ? 'longer' : 'shorter'} than the '
      'current route (${formatter.distance(previousDistance)} \u2192 '
      '${formatter.distance(candidateDistance)}).';
}
