import 'package:xml/xml.dart';

import '../domain/app_links.dart';
import '../domain/altitude.dart';
import '../domain/imported_route.dart';

class GpxExporter {
  const GpxExporter();

  String export(ImportedRoute route) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'gpx',
      attributes: {
        'version': '1.1',
        'creator': 'Balloon Crumbs',
        'xmlns': 'http://www.topografix.com/GPX/1/1',
        if (route.preferences != null || _hasAltitudeMetadata(route))
          'xmlns:bc': 'https://$appLinkHost/gpx/1',
      },
      nest: () {
        builder.element(
          'metadata',
          nest: () {
            builder.element('name', nest: route.name);
            if (route.description case final description?) {
              builder.element('desc', nest: description);
            }
            builder.element(
              'time',
              nest: route.importedAt.toUtc().toIso8601String(),
            );
            // Preferences belong to the route, so they travel with the file a
            // rider shares rather than staying on the device that planned it.
            // Any other GPX reader ignores an unknown extension element.
            if (route.preferences != null) {
              builder.element(
                'extensions',
                nest: () {
                  if (route.preferences case final preferences?) {
                    builder.element(
                      'bc:route-preferences',
                      attributes: {
                        'style': preferences.style.apiValue,
                        'avoid-motorways': '${preferences.avoidMotorways}',
                        'avoid-major-roads': '${preferences.avoidMajorRoads}',
                        'avoid-tolls': '${preferences.avoidTolls}',
                        'avoid-ferries': '${preferences.avoidFerries}',
                        'byway-surface': preferences.bywaySurface.apiValue,
                      },
                    );
                  }
                },
              );
            }
          },
        );
        for (final waypoint in route.waypoints) {
          builder.element(
            'wpt',
            attributes: _coordinates(waypoint.point),
            nest: () {
              _writePointDetails(builder, waypoint.point);
              if (waypoint.name case final name?) {
                builder.element('name', nest: name);
              }
              if (waypoint.description case final description?) {
                builder.element('desc', nest: description);
              }
              if (waypoint.symbol case final symbol?) {
                builder.element('sym', nest: symbol);
              }
            },
          );
        }
        for (final path in route.paths) {
          switch (path.kind) {
            case RoutePathKind.track:
              builder.element(
                'trk',
                nest: () {
                  if (path.name case final name?) {
                    builder.element('name', nest: name);
                  }
                  builder.element(
                    'trkseg',
                    nest: () {
                      for (final point in path.points) {
                        builder.element(
                          'trkpt',
                          attributes: _coordinates(point),
                          nest: () => _writePointDetails(builder, point),
                        );
                      }
                    },
                  );
                },
              );
            case RoutePathKind.route:
              builder.element(
                'rte',
                nest: () {
                  if (path.name case final name?) {
                    builder.element('name', nest: name);
                  }
                  for (final point in path.points) {
                    builder.element(
                      'rtept',
                      attributes: _coordinates(point),
                      nest: () => _writePointDetails(builder, point),
                    );
                  }
                },
              );
          }
        }
      },
    );
    return '${builder.buildDocument().toXmlString(pretty: true)}\n';
  }

  String fileName(ImportedRoute route) {
    final slug = route.name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'balloon-crumbs-route' : slug}.gpx';
  }

  static Map<String, String> _coordinates(GeoPoint point) => {
    'lat': point.latitude.toStringAsFixed(7),
    'lon': point.longitude.toStringAsFixed(7),
  };

  static void _writePointDetails(XmlBuilder builder, GeoPoint point) {
    if (point.elevationMeters case final elevation?) {
      builder.element('ele', nest: elevation.toStringAsFixed(3));
    }
    if (point.recordedAt case final recordedAt?) {
      builder.element('time', nest: recordedAt.toUtc().toIso8601String());
    }
    if (_pointHasAltitudeMetadata(point)) {
      builder.element(
        'extensions',
        nest: () => builder.element(
          'bc:altitude',
          attributes: {
            'source': point.altitudeSource.name,
            'datum': point.altitudeDatum.name,
            if (point.altitudeAccuracyMeters case final accuracy?)
              'accuracy-meters': accuracy.toStringAsFixed(3),
          },
        ),
      );
    }
  }

  static bool _pointHasAltitudeMetadata(GeoPoint point) =>
      point.elevationMeters != null &&
      (point.altitudeSource != AltitudeSource.unknown ||
          point.altitudeDatum != AltitudeDatum.unknown ||
          point.altitudeAccuracyMeters != null);

  static bool _hasAltitudeMetadata(ImportedRoute route) => [
    ...route.paths.expand((path) => path.points),
    ...route.waypoints.map((waypoint) => waypoint.point),
  ].any(_pointHasAltitudeMetadata);
}
