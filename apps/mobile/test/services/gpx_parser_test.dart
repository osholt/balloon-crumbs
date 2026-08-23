import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/altitude.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/services/gpx_parser.dart';

void main() {
  const parser = GpxParser();

  test('parses GPX 1.1 tracks, route points, waypoints, and metadata', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>Mixed route</name><desc>Saturday</desc></metadata>
          <wpt lat="53.3" lon="-1.6"><name>Fuel</name><sym>Fuel</sym></wpt>
          <trk><name>Main track</name>
            <trkseg>
              <trkpt lat="53.1" lon="-1.4"><ele>200</ele><time>2026-07-16T09:00:00Z</time></trkpt>
              <trkpt lat="53.2" lon="-1.5" />
            </trkseg>
          </trk>
          <rte><name>Diversion</name><rtept lat="53.4" lon="-1.7" /></rte>
        </gpx>
      '''),
      routeId: 'route-1',
      sourceFileName: 'mixed.gpx',
      importedAt: DateTime.utc(2026, 7, 16),
    );

    expect(route.name, 'Mixed route');
    expect(route.description, 'Saturday');
    expect(route.paths, hasLength(2));
    expect(route.pathPointCount, 3);
    expect(route.paths.first.points.first.elevationMeters, 200);
    expect(
      route.paths.first.points.first.altitudeSource,
      AltitudeSource.unknown,
      reason: 'a third-party <ele> does not state how it was measured',
    );
    expect(
      route.paths.first.points.first.altitudeDatum,
      AltitudeDatum.unknown,
      reason: 'the parser must not fabricate a geoid/ellipsoid datum',
    );
    expect(route.paths.first.points.first.altitudeAccuracyMeters, isNull);
    expect(route.paths.first.points.first.recordedAt, isNotNull);
    expect(route.waypoints.single.name, 'Fuel');
  });

  test('round-trips Balloon Crumbs altitude evidence per point', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:bc="https://balloon-crumbs.tailendcharlie.app/gpx/1">
          <trk><trkseg>
            <trkpt lat="51.45" lon="-2.59">
              <ele>123.4</ele>
              <extensions>
                <bc:altitude source="gnss" datum="wgs84Ellipsoid"
                             accuracy-meters="7.25"/>
              </extensions>
            </trkpt>
          </trkseg></trk>
        </gpx>
      '''),
      routeId: 'altitude',
      sourceFileName: 'altitude.gpx',
      importedAt: DateTime.utc(2026, 8, 20),
    );

    final point = route.paths.single.points.single;
    expect(point.elevationMeters, 123.4);
    expect(point.altitudeSource, AltitudeSource.gnss);
    expect(point.altitudeDatum, AltitudeDatum.wgs84Ellipsoid);
    expect(point.altitudeAccuracyMeters, 7.25);
  });

  test('recognises a web-planner balloon forecast', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>Bath forecast</name>
            <desc>Forecast-only wind drift. Not a controllable route.</desc>
          </metadata>
          <trk>
            <name>Bath forecast</name>
            <type>balloon-flight-forecast</type>
            <trkseg>
              <trkpt lat="51.38" lon="-2.36">
                <ele>120</ele><time>2026-08-23T06:00:00Z</time>
              </trkpt>
              <trkpt lat="51.42" lon="-2.20">
                <ele>900</ele><time>2026-08-23T07:15:00Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
      '''),
      routeId: 'forecast',
      sourceFileName: 'forecast.gpx',
      importedAt: DateTime.utc(2026, 8, 22),
    );

    expect(route.purpose, ImportedRoutePurpose.balloonForecast);
    expect(route.isBalloonForecast, isTrue);
  });

  test('malformed altitude evidence degrades without losing <ele>', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:bc="https://balloon-crumbs.tailendcharlie.app/gpx/1">
          <trk><trkseg><trkpt lat="51.45" lon="-2.59">
            <ele>123.4</ele>
            <extensions><bc:altitude source="future-sensor"
              datum="future-datum" accuracy-meters="-4"/></extensions>
          </trkpt></trkseg></trk>
        </gpx>
      '''),
      routeId: 'future',
      sourceFileName: 'future.gpx',
      importedAt: DateTime.utc(2026, 8, 20),
    );

    final point = route.paths.single.points.single;
    expect(point.elevationMeters, 123.4);
    expect(point.altitudeSource, AltitudeSource.unknown);
    expect(point.altitudeDatum, AltitudeDatum.unknown);
    expect(point.altitudeAccuracyMeters, isNull);
  });

  test('does not mistake another vendor altitude extension for ours', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:other="https://example.com/gpx">
          <trk><trkseg><trkpt lat="51.45" lon="-2.59">
            <ele>123.4</ele>
            <extensions><other:altitude source="gnss"
              datum="wgs84Geoid" accuracy-meters="1"/></extensions>
          </trkpt></trkseg></trk>
        </gpx>
      '''),
      routeId: 'other-vendor',
      sourceFileName: 'other.gpx',
      importedAt: DateTime.utc(2026, 8, 20),
    );

    final point = route.paths.single.points.single;
    expect(point.elevationMeters, 123.4);
    expect(point.altitudeSource, AltitudeSource.unknown);
    expect(point.altitudeDatum, AltitudeDatum.unknown);
    expect(point.altitudeAccuracyMeters, isNull);
  });

  test('rejects invalid coordinates and excessive point counts', () {
    expect(
      () => parser.parse(
        _bytes('<gpx><wpt lat="91" lon="0" /></gpx>'),
        routeId: 'bad',
        sourceFileName: 'bad.gpx',
        importedAt: DateTime.utc(2026),
      ),
      throwsA(isA<GpxFormatException>()),
    );

    const limitedParser = GpxParser(maximumPoints: 1);
    expect(
      () => limitedParser.parse(
        _bytes(
          '<gpx><rte><rtept lat="1" lon="1"/><rtept lat="2" lon="2"/></rte></gpx>',
        ),
        routeId: 'large',
        sourceFileName: 'large.gpx',
        importedAt: DateTime.utc(2026),
      ),
      throwsA(isA<GpxFormatException>()),
    );
  });

  test('recognises a planner-calculated track as a road route', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:tec="https://balloon-crumbs.invalid/gpx/1">
          <trk>
            <extensions><tec:road-route>true</tec:road-route></extensions>
            <trkseg>
              <trkpt lat="53.1" lon="-1.4" />
              <trkpt lat="53.2" lon="-1.5" />
            </trkseg>
          </trk>
        </gpx>
      '''),
      routeId: 'planned',
      sourceFileName: 'planned.gpx',
      importedAt: DateTime.utc(2026, 7, 23),
    );

    expect(route.paths.single.kind.name, 'route');
  });

  test('preserves Scenic soft points without importing duplicate routes', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1"
             creator="Scenic Motorcycle Navigation App"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:trp="http://www.garmin.com/xmlschemas/TripExtensions/v1"
             xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3">
          <wpt lat="51.0" lon="-2.0"><name>Start</name></wpt>
          <rte><name>Plain</name>
            <rtept lat="51.0" lon="-2.0"/>
            <rtept lat="51.1" lon="-2.1"/>
            <rtept lat="51.2" lon="-2.2"/>
          </rte>
          <rte><name>Garmin Trip</name>
            <rtept lat="51.0" lon="-2.0">
              <extensions><trp:ViaPoint/></extensions>
            </rtept>
            <rtept lat="51.1" lon="-2.1">
              <name>Via 1</name>
              <extensions><trp:ShapingPoint/></extensions>
            </rtept>
            <rtept lat="51.2" lon="-2.2">
              <extensions><trp:ViaPoint/></extensions>
            </rtept>
          </rte>
          <rte><name>Garmin RoutePoint</name>
            <rtept lat="51.0" lon="-2.0">
              <extensions><gpxx:RoutePointExtension>
                <gpxx:rpt lat="51.1" lon="-2.1"/>
              </gpxx:RoutePointExtension></extensions>
            </rtept>
            <rtept lat="51.2" lon="-2.2"/>
          </rte>
          <trk><name>Calculated track</name><trkseg>
            <trkpt lat="51.0" lon="-2.0"/>
            <trkpt lat="51.2" lon="-2.2"/>
          </trkseg></trk>
        </gpx>
      '''),
      routeId: 'scenic',
      sourceFileName: 'scenic.gpx',
      importedAt: DateTime.utc(2026, 7, 24),
    );

    expect(route.paths, hasLength(2));
    expect(
      route.paths.where((path) => path.kind.name == 'route').single.name,
      'Garmin Trip',
    );
    expect(
      route.waypoints.where((waypoint) => waypoint.symbol == 'Shaping point'),
      hasLength(1),
    );
    expect(
      route.waypoints
          .where((waypoint) => waypoint.symbol == 'Shaping point')
          .single
          .name,
      'Via 1',
    );
  });

  test('Garmin RoutePoint extension points shape the line without becoming '
      'waypoints', () {
    final route = parser.parse(
      _bytes('''
        <gpx version="1.1"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3">
          <rte><name>Garmin route</name>
            <rtept lat="51.0" lon="-2.0">
              <extensions><gpxx:RoutePointExtension>
                <gpxx:rpt lat="51.1" lon="-2.1"/>
                <gpxx:rpt lat="51.2" lon="-2.2"/>
              </gpxx:RoutePointExtension></extensions>
            </rtept>
            <rtept lat="51.3" lon="-2.3"/>
          </rte>
        </gpx>
      '''),
      routeId: 'garmin',
      sourceFileName: 'garmin.gpx',
      importedAt: DateTime.utc(2026, 7, 24),
    );

    expect(route.paths.single.points.map((point) => point.latitude), [
      51.0,
      51.1,
      51.2,
      51.3,
    ]);
    expect(route.waypoints, isEmpty);
  });

  test('bundled demo is valid GPX geometry', () {
    final bytes = File('assets/demo_route.gpx').readAsBytesSync();
    final route = parser.parse(
      bytes,
      routeId: 'demo',
      sourceFileName: 'demo_route.gpx',
      importedAt: DateTime.utc(2026),
    );

    expect(route.name, "King's Oak Academy to Cross Hands Hotel");
    expect(route.pathPointCount, greaterThan(450));
    expect(route.waypoints, hasLength(3));
    expect(route.paths.single.kind.name, 'track');
    expect(
      route.paths.single.points.first.latitude,
      closeTo(51.462674, 0.00001),
    );
    expect(
      route.paths.single.points.last.latitude,
      closeTo(51.528729, 0.00001),
    );
  });
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));
