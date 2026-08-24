import 'package:xml/xml.dart';

import '../domain/altitude.dart';
import '../domain/imported_route.dart';
import '../domain/ride_event.dart';
import '../domain/ride_session.dart';

enum TelemetryQuality { measured, calculated, missing, rejected }

/// Writes precise flight data without pretending every value has equal quality.
///
/// The CSV is the audit-friendly form: every value says whether it was measured,
/// calculated, missing, or rejected. GPX remains the interoperable geometry
/// format and KML is the convenient map-viewing format.
class FlightDataExporter {
  const FlightDataExporter();

  static const maximumContinuousTrailGap = Duration(minutes: 2);

  String telemetryCsv({
    required RideSession session,
    required Iterable<RideEvent> events,
    ImportedRoute? plannedRoute,
  }) {
    final rows = <_TelemetryRow>[
      ..._recordedRows(session, events),
      if (plannedRoute != null)
        ..._routeRows(
          plannedRoute,
          dataset: 'planned_route',
          quality: TelemetryQuality.calculated,
        ),
    ];
    final csv = <List<Object?>>[
      const [
        'dataset',
        'segment',
        'point',
        'recorded_at_utc',
        'latitude',
        'longitude',
        'altitude_meters',
        'position_quality',
        'altitude_quality',
        'altitude_source',
        'altitude_datum',
        'altitude_accuracy_meters',
        'note',
      ],
      ...rows.map((row) => row.cells),
    ].map(_csvRow).join('\r\n');
    return '$csv\r\n';
  }

  String archivedTelemetryCsv({
    required ImportedRoute traveledRoute,
    ImportedRoute? plannedRoute,
  }) {
    final rows = <_TelemetryRow>[
      ..._routeRows(
        traveledRoute,
        dataset: 'recorded_track',
        quality: TelemetryQuality.measured,
        markSegmentGaps: true,
      ),
      if (plannedRoute != null)
        ..._routeRows(
          plannedRoute,
          dataset: 'planned_route',
          quality: TelemetryQuality.calculated,
        ),
    ];
    final csv = <List<Object?>>[
      const [
        'dataset',
        'segment',
        'point',
        'recorded_at_utc',
        'latitude',
        'longitude',
        'altitude_meters',
        'position_quality',
        'altitude_quality',
        'altitude_source',
        'altitude_datum',
        'altitude_accuracy_meters',
        'note',
      ],
      ...rows.map((row) => row.cells),
    ].map(_csvRow).join('\r\n');
    return '$csv\r\n';
  }

  String kml({
    required String name,
    ImportedRoute? traveledRoute,
    ImportedRoute? plannedRoute,
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'kml',
      attributes: {'xmlns': 'http://www.opengis.net/kml/2.2'},
      nest: () => builder.element(
        'Document',
        nest: () {
          builder.element('name', nest: name);
          _writeKmlStyle(builder, 'recorded', 'ff00aaff');
          _writeKmlStyle(builder, 'calculated', 'ffffaa00');
          if (traveledRoute != null) {
            _writeKmlRoute(
              builder,
              traveledRoute,
              folderName: 'Recorded track',
              styleId: 'recorded',
              quality: TelemetryQuality.measured,
            );
          }
          if (plannedRoute != null) {
            _writeKmlRoute(
              builder,
              plannedRoute,
              folderName: 'Planned or forecast route',
              styleId: 'calculated',
              quality: TelemetryQuality.calculated,
            );
          }
        },
      ),
    );
    return '${builder.buildDocument().toXmlString(pretty: true)}\n';
  }

  String csvFileName(String rideCode) =>
      'balloon-crumbs-${_slug(rideCode)}-telemetry.csv';

  String kmlFileName(String rideCode) =>
      'balloon-crumbs-${_slug(rideCode)}-flight.kml';

  static Iterable<_TelemetryRow> _recordedRows(
    RideSession session,
    Iterable<RideEvent> events,
  ) sync* {
    final ordered =
        events
            .where(
              (event) =>
                  event.type == RideEventType.riderLocationUpdated &&
                  event.deviceId == session.localRiderId,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final time = left.createdAt.compareTo(right.createdAt);
            return time != 0 ? time : left.id.compareTo(right.id);
          });
    DateTime? previousRecordedAt;
    var segment = 1;
    var point = 0;
    for (final event in ordered) {
      final location = event.payload['location'];
      final sample = location is Map ? location['sample'] : null;
      if (sample is! Map) {
        yield _TelemetryRow.rejected(
          event.createdAt,
          'Malformed location sample',
        );
        continue;
      }
      final position = sample['position'];
      final latitude = position is Map ? position['latitude'] : null;
      final longitude = position is Map ? position['longitude'] : null;
      final positionIsValid =
          latitude is num &&
          latitude.isFinite &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude is num &&
          longitude.isFinite &&
          longitude >= -180 &&
          longitude <= 180;
      final rawRecordedAt = sample['recordedAt'];
      final parsedRecordedAt = rawRecordedAt is String
          ? DateTime.tryParse(rawRecordedAt)?.toUtc()
          : null;
      final recordedAt = parsedRecordedAt ?? event.createdAt.toUtc();
      final notes = <String>[
        if (rawRecordedAt != null && parsedRecordedAt == null)
          'Rejected recordedAt; event time used',
      ];
      final rawAltitude = sample['altitudeMeters'];
      final altitudeIsValid =
          rawAltitude is num &&
          rawAltitude.isFinite &&
          rawAltitude >= -1000 &&
          rawAltitude <= 30000;
      final altitudeQuality = rawAltitude == null
          ? TelemetryQuality.missing
          : altitudeIsValid
          ? TelemetryQuality.measured
          : TelemetryQuality.rejected;
      if (rawAltitude != null && !altitudeIsValid) {
        notes.add('Rejected altitude outside the supported numeric range');
      }
      if (!positionIsValid) {
        yield _TelemetryRow(
          dataset: 'recorded_track',
          segment: segment,
          point: point,
          recordedAt: recordedAt,
          positionQuality: TelemetryQuality.rejected,
          altitudeQuality: altitudeQuality,
          note: [...notes, 'Rejected invalid or missing position'].join('; '),
        );
        continue;
      }
      if (previousRecordedAt case final previous?
          when recordedAt.difference(previous) > maximumContinuousTrailGap ||
              recordedAt.isBefore(previous)) {
        segment += 1;
        point = 0;
        final movedBackwards = recordedAt.isBefore(previous);
        yield _TelemetryRow(
          dataset: 'recording_gap',
          segment: segment,
          point: point,
          recordedAt: recordedAt,
          positionQuality: TelemetryQuality.missing,
          altitudeQuality: TelemetryQuality.missing,
          note: movedBackwards
              ? 'Recorded time moved backwards; continuity was rejected'
              : 'No continuous position record for more than 120 seconds',
        );
      }
      previousRecordedAt = recordedAt;
      point += 1;
      final rawAltitudeAccuracy = sample['altitudeAccuracyMeters'];
      yield _TelemetryRow(
        dataset: 'recorded_track',
        segment: segment,
        point: point,
        recordedAt: recordedAt,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        altitudeMeters: altitudeIsValid ? rawAltitude.toDouble() : null,
        positionQuality: TelemetryQuality.measured,
        altitudeQuality: altitudeQuality,
        altitudeSource: altitudeIsValid
            ? _enumValue(
                AltitudeSource.values,
                sample['altitudeSource'],
                AltitudeSource.unknown,
              )
            : AltitudeSource.unknown,
        altitudeDatum: altitudeIsValid
            ? _enumValue(
                AltitudeDatum.values,
                sample['altitudeDatum'],
                AltitudeDatum.unknown,
              )
            : AltitudeDatum.unknown,
        altitudeAccuracyMeters:
            altitudeIsValid &&
                rawAltitudeAccuracy is num &&
                rawAltitudeAccuracy.isFinite &&
                rawAltitudeAccuracy >= 0 &&
                rawAltitudeAccuracy <= 10000
            ? rawAltitudeAccuracy.toDouble()
            : null,
        note: notes.join('; '),
      );
    }
  }

  static Iterable<_TelemetryRow> _routeRows(
    ImportedRoute route, {
    required String dataset,
    required TelemetryQuality quality,
    bool markSegmentGaps = false,
  }) sync* {
    var segment = 0;
    for (final path in route.paths) {
      segment += 1;
      if (markSegmentGaps && segment > 1) {
        yield _TelemetryRow(
          dataset: 'recording_gap',
          segment: segment,
          point: 0,
          positionQuality: TelemetryQuality.missing,
          altitudeQuality: TelemetryQuality.missing,
          note: 'Recorded track resumes in a new segment',
        );
      }
      for (final (index, point) in path.points.indexed) {
        yield _TelemetryRow(
          dataset: dataset,
          segment: segment,
          point: index + 1,
          recordedAt: point.recordedAt,
          latitude: point.latitude,
          longitude: point.longitude,
          altitudeMeters: point.elevationMeters,
          positionQuality: quality,
          altitudeQuality: point.elevationMeters == null
              ? TelemetryQuality.missing
              : quality,
          altitudeSource: point.altitudeSource,
          altitudeDatum: point.altitudeDatum,
          altitudeAccuracyMeters: point.altitudeAccuracyMeters,
        );
      }
    }
  }

  static void _writeKmlStyle(XmlBuilder builder, String id, String color) {
    builder.element(
      'Style',
      attributes: {'id': id},
      nest: () => builder.element(
        'LineStyle',
        nest: () {
          builder.element('color', nest: color);
          builder.element('width', nest: '5');
        },
      ),
    );
  }

  static void _writeKmlRoute(
    XmlBuilder builder,
    ImportedRoute route, {
    required String folderName,
    required String styleId,
    required TelemetryQuality quality,
  }) {
    builder.element(
      'Folder',
      nest: () {
        builder.element('name', nest: folderName);
        for (final (index, path) in route.paths.indexed) {
          if (path.points.length < 2) continue;
          final hasKmlAbsoluteAltitude = path.points.every(
            (point) =>
                point.elevationMeters != null &&
                point.altitudeDatum == AltitudeDatum.wgs84Geoid,
          );
          builder.element(
            'Placemark',
            nest: () {
              builder.element(
                'name',
                nest: path.name ?? '$folderName ${index + 1}',
              );
              builder.element('styleUrl', nest: '#$styleId');
              builder.element(
                'ExtendedData',
                nest: () {
                  _writeKmlData(builder, 'position_quality', quality.name);
                  _writeKmlData(
                    builder,
                    'altitude_quality',
                    hasKmlAbsoluteAltitude ? quality.name : 'missing_or_mixed',
                  );
                  _writeKmlData(builder, 'altitude_unit', 'metres');
                  _writeKmlData(
                    builder,
                    'altitude_datum',
                    hasKmlAbsoluteAltitude
                        ? AltitudeDatum.wgs84Geoid.name
                        : 'omitted_from_kml_use_csv',
                  );
                },
              );
              builder.element(
                'LineString',
                nest: () {
                  builder.element('tessellate', nest: '1');
                  if (hasKmlAbsoluteAltitude) {
                    builder.element('altitudeMode', nest: 'absolute');
                  }
                  builder.element(
                    'coordinates',
                    nest: path.points
                        .map(
                          (point) => hasKmlAbsoluteAltitude
                              ? '${point.longitude},${point.latitude},${point.elevationMeters}'
                              : '${point.longitude},${point.latitude}',
                        )
                        .join(' '),
                  );
                },
              );
            },
          );
        }
      },
    );
  }

  static void _writeKmlData(XmlBuilder builder, String name, String value) {
    builder.element(
      'Data',
      attributes: {'name': name},
      nest: () => builder.element('value', nest: value),
    );
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? name,
    T fallback,
  ) => values.where((value) => value.name == name).firstOrNull ?? fallback;

  static String _csvRow(List<Object?> values) =>
      values.map((value) => _csvCell(value?.toString() ?? '')).join(',');

  static String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  static String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'flight' : slug;
  }
}

class _TelemetryRow {
  const _TelemetryRow({
    required this.dataset,
    required this.segment,
    required this.point,
    required this.positionQuality,
    required this.altitudeQuality,
    this.recordedAt,
    this.latitude,
    this.longitude,
    this.altitudeMeters,
    this.altitudeSource = AltitudeSource.unknown,
    this.altitudeDatum = AltitudeDatum.unknown,
    this.altitudeAccuracyMeters,
    this.note = '',
  });

  factory _TelemetryRow.rejected(DateTime recordedAt, String note) =>
      _TelemetryRow(
        dataset: 'recorded_track',
        segment: 0,
        point: 0,
        recordedAt: recordedAt,
        positionQuality: TelemetryQuality.rejected,
        altitudeQuality: TelemetryQuality.rejected,
        note: note,
      );

  final String dataset;
  final int segment;
  final int point;
  final DateTime? recordedAt;
  final double? latitude;
  final double? longitude;
  final double? altitudeMeters;
  final TelemetryQuality positionQuality;
  final TelemetryQuality altitudeQuality;
  final AltitudeSource altitudeSource;
  final AltitudeDatum altitudeDatum;
  final double? altitudeAccuracyMeters;
  final String note;

  List<Object?> get cells => [
    dataset,
    segment,
    point,
    recordedAt?.toUtc().toIso8601String(),
    latitude,
    longitude,
    altitudeMeters,
    positionQuality.name,
    altitudeQuality.name,
    altitudeSource.name,
    altitudeDatum.name,
    altitudeAccuracyMeters,
    note,
  ];
}
