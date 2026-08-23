import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/land_access_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('land access note preserves privacy governance fields', () {
    final note = _note();

    final restored = LandAccessNote.fromJson(note.toJson());

    expect(restored.id, note.id);
    expect(restored.geometry.kind, LandAccessGeometryKind.polygon);
    expect(restored.geometry.points, hasLength(3));
    expect(restored.outcome, LandAccessOutcome.askFirst);
    expect(restored.firstName, 'Pat');
    expect(restored.contactRole, 'Occupier');
    expect(restored.phoneNumber, '07000 000000');
    expect(restored.provenance, LandAccessProvenance.landContact);
    expect(restored.consentStatus, LandAccessConsentStatus.verbal);
    expect(restored.reviewAfter, DateTime.utc(2027, 8, 24));
  });

  test('point and polygon geometry reject ambiguous shapes', () {
    expect(
      () => LandAccessGeometry(
        kind: LandAccessGeometryKind.point,
        points: const [
          GeoPoint(latitude: 51, longitude: -2),
          GeoPoint(latitude: 52, longitude: -2),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => LandAccessGeometry(
        kind: LandAccessGeometryKind.polygon,
        points: const [
          GeoPoint(latitude: 51, longitude: -2),
          GeoPoint(latitude: 52, longitude: -2),
        ],
      ),
      throwsFormatException,
    );
  });

  test('review date cannot predate the confirmation', () {
    expect(
      () => _note(reviewAfter: DateTime.utc(2026, 8, 23)),
      throwsFormatException,
    );
  });
}

LandAccessNote _note({DateTime? reviewAfter}) => LandAccessNote(
  id: 'field-1',
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
  contactRole: 'Occupier',
  phoneNumber: '07000 000000',
  gateNotes: 'Use the eastern gate after asking.',
  confirmedAt: DateTime.utc(2026, 8, 24),
  recordedBy: 'Synthetic tester',
  provenance: LandAccessProvenance.landContact,
  consentStatus: LandAccessConsentStatus.verbal,
  reviewAfter: reviewAfter ?? DateTime.utc(2027, 8, 24),
  createdAt: DateTime.utc(2026, 8, 24),
  updatedAt: DateTime.utc(2026, 8, 24),
);
