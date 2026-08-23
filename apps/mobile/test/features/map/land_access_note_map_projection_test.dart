import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/land_access_note.dart';
import 'package:balloon_crumbs/features/map/land_access_note_map_projection.dart';
import 'package:balloon_crumbs/services/rider_trail_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projection hides expired notes and private contact values', () {
    final active = _note('active', reviewAfter: DateTime.utc(2027));
    final expired = _note('expired', reviewAfter: DateTime.utc(2025));

    final projection = projectLandAccessNotes([
      active,
      expired,
    ], now: DateTime.utc(2026, 8, 24));

    expect(projection.markers, hasLength(1));
    expect(projection.traces, hasLength(1));
    expect(projection.markers.single.id, contains('active'));
    expect(projection.markers.single.label, contains('ask before'));
    expect(projection.markers.single.label, isNot(contains('Pat')));
    expect(projection.markers.single.label, isNot(contains('07000')));
    expect(projection.traces.single.kind, RiderTrailKind.operationalBoundary);
    expect(
      projection.traces.single.points.first.latitude,
      projection.traces.single.points.last.latitude,
    );
    expect(
      projection.traces.single.points.first.longitude,
      projection.traces.single.points.last.longitude,
    );
  });
}

LandAccessNote _note(String id, {required DateTime reviewAfter}) =>
    LandAccessNote(
      id: id,
      geometry: LandAccessGeometry(
        kind: LandAccessGeometryKind.polygon,
        points: const [
          GeoPoint(latitude: 51.1, longitude: -2.1),
          GeoPoint(latitude: 51.2, longitude: -2.1),
          GeoPoint(latitude: 51.2, longitude: -2.2),
        ],
      ),
      outcome: LandAccessOutcome.askFirst,
      firstName: 'Pat',
      phoneNumber: '07000 000000',
      confirmedAt: DateTime.utc(2024),
      recordedBy: 'Synthetic tester',
      provenance: LandAccessProvenance.landContact,
      consentStatus: LandAccessConsentStatus.verbal,
      reviewAfter: reviewAfter,
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );
