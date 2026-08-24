import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

import '../domain/completed_ride.dart';
import '../domain/distance_unit.dart';
import '../domain/ride_role.dart';
import 'flight_data_exporter.dart';
import 'gpx_exporter.dart';
import 'measurement_formatter.dart';

abstract interface class CompletedRideSharer {
  Future<void> shareSummary(
    CompletedRide ride, {
    DistanceUnit distanceUnit,
    Rect? sharePositionOrigin,
  });

  Future<void> exportFlightData(
    CompletedRide ride, {
    Rect? sharePositionOrigin,
  });
}

class SystemCompletedRideSharer implements CompletedRideSharer {
  const SystemCompletedRideSharer({
    this.gpxExporter = const GpxExporter(),
    this.flightDataExporter = const FlightDataExporter(),
  });

  final GpxExporter gpxExporter;
  final FlightDataExporter flightDataExporter;

  @override
  Future<void> shareSummary(
    CompletedRide ride, {
    DistanceUnit distanceUnit = DistanceUnit.kilometres,
    Rect? sharePositionOrigin,
  }) async {
    final distance = MeasurementFormatter(
      distanceUnit,
    ).distance(ride.totalDistanceMeters);
    final text = [
      'Balloon Crumbs flight · ${ride.title}',
      'Flight code: ${ride.rideCode}',
      'Crew member: ${ride.localDisplayName} (${ride.localRole.label})',
      'Started: ${ride.startedAt.toLocal().toIso8601String()}',
      'Ended: ${ride.endedAt.toLocal().toIso8601String()}',
      'Duration: ${_duration(ride.duration)}',
      'Distance: $distance',
      'Crew: ${ride.riderCount}',
    ].join('\n');
    await SharePlus.instance.share(
      ShareParams(
        subject: ride.title,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  @override
  Future<void> exportFlightData(
    CompletedRide ride, {
    Rect? sharePositionOrigin,
  }) async {
    final route = ride.traveledRoute;
    if (route == null) {
      throw StateError('This flight has no recorded local trail to export.');
    }
    final gpxFileName = gpxExporter.fileName(route);
    final csvFileName = flightDataExporter.csvFileName(ride.rideCode);
    final kmlFileName = flightDataExporter.kmlFileName(ride.rideCode);
    await SharePlus.instance.share(
      ShareParams(
        title: 'Export ${ride.title}',
        subject: 'Balloon Crumbs flight data: ${ride.title}',
        text:
            'Exact recorded positions, timestamps and altitude are attached. '
            'The CSV labels measured, calculated, missing and rejected data.',
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(gpxExporter.export(route))),
            mimeType: 'application/gpx+xml',
            name: gpxFileName,
          ),
          XFile.fromData(
            Uint8List.fromList(
              utf8.encode(
                flightDataExporter.archivedTelemetryCsv(
                  traveledRoute: route,
                  plannedRoute: ride.plannedRoute,
                ),
              ),
            ),
            mimeType: 'text/csv',
            name: csvFileName,
          ),
          XFile.fromData(
            Uint8List.fromList(
              utf8.encode(
                flightDataExporter.kml(
                  name: ride.title,
                  traveledRoute: route,
                  plannedRoute: ride.plannedRoute,
                ),
              ),
            ),
            mimeType: 'application/vnd.google-earth.kml+xml',
            name: kmlFileName,
          ),
        ],
        fileNameOverrides: [gpxFileName, csvFileName, kmlFileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
  }
}
