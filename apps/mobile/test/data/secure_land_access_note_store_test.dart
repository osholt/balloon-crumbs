import 'package:balloon_crumbs/data/secure_land_access_note_store.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/land_access_note.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('notes and export metadata remain in secure storage', () async {
    const store = SecureLandAccessNoteStore();
    final note = _note('field-a');

    await store.upsert(note);
    await store.recordExport(
      LandAccessExportMetadata(
        exportId: 'export-a',
        noteIds: [note.id],
        createdAt: DateTime.utc(2026, 8, 24),
      ),
    );

    expect(await store.loadNotes(), hasLength(1));
    expect(await store.loadExportMetadata(), hasLength(1));
  });

  test('deleting a note removes its local export metadata', () async {
    const store = SecureLandAccessNoteStore();
    final first = _note('field-a');
    final second = _note('field-b');
    await store.upsert(first);
    await store.upsert(second);
    await store.recordExport(
      LandAccessExportMetadata(
        exportId: 'export-a',
        noteIds: [first.id, second.id],
        createdAt: DateTime.utc(2026, 8, 24),
      ),
    );

    await store.delete(first.id);
    var metadata = await store.loadExportMetadata();
    expect(metadata.single.noteIds, [second.id]);

    await store.delete(second.id);
    metadata = await store.loadExportMetadata();
    expect(metadata, isEmpty);
    expect(await store.loadNotes(), isEmpty);
  });

  test('malformed storage is deleted rather than partly disclosed', () async {
    await const FlutterSecureStorage().write(
      key: 'balloon_crumbs_land_access_notes_v1',
      value: '{"schemaVersion":1,"notes":"private","exports":[]}',
    );

    expect(await const SecureLandAccessNoteStore().loadNotes(), isEmpty);
    expect(
      await const FlutterSecureStorage().read(
        key: 'balloon_crumbs_land_access_notes_v1',
      ),
      isNull,
    );
  });
}

LandAccessNote _note(String id) => LandAccessNote(
  id: id,
  geometry: LandAccessGeometry(
    kind: LandAccessGeometryKind.point,
    points: const [GeoPoint(latitude: 51.1, longitude: -2.1)],
  ),
  outcome: LandAccessOutcome.unknown,
  confirmedAt: DateTime.utc(2026, 8, 24),
  recordedBy: 'Synthetic tester',
  provenance: LandAccessProvenance.crewObservation,
  consentStatus: LandAccessConsentStatus.notRecorded,
  reviewAfter: DateTime.utc(2027, 8, 24),
  createdAt: DateTime.utc(2026, 8, 24),
  updatedAt: DateTime.utc(2026, 8, 24),
);
