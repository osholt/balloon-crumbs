import 'dart:math';

import 'package:balloon_crumbs/controllers/land_access_note_controller.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/land_access_note.dart';
import 'package:balloon_crumbs/domain/land_access_note_store.dart';
import 'package:balloon_crumbs/features/settings/land_access_notes_screen.dart';
import 'package:balloon_crumbs/services/land_access_note_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('manager explains the local privacy boundary and map toggle', (
    tester,
  ) async {
    final controller = LandAccessNoteController(
      _MemoryStore([_note()]),
      exportCodec: LandAccessNoteExportCodec(
        iterations: 10000,
        random: Random(1),
      ),
    );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: LandAccessNotesScreen(
          controller: controller,
          recordedBy: 'Synthetic tester',
          enableNativeMap: false,
        ),
      ),
    );

    expect(find.text('Private recovery memory'), findsOneWidget);
    expect(find.textContaining('never uploaded'), findsOneWidget);
    expect(
      find.textContaining('never a public permission score'),
      findsNothing,
    );
    expect(
      find.byKey(const Key('show-land-access-notes-on-map')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('show-land-access-notes-on-map')));
    await tester.pump();
    expect(controller.showOnMap, isTrue);
  });

  testWidgets(
    'editor requires purpose audience and retention acknowledgement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(945, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = _MemoryStore([_note()]);
      final controller = LandAccessNoteController(store);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: LandAccessNoteEditor(
            controller: controller,
            recordedBy: 'Synthetic tester',
            note: _note(),
            enableNativeMap: false,
          ),
        ),
      );

      final acknowledgement = find.byKey(
        const Key('land-access-privacy-acknowledgement'),
      );
      expect(find.textContaining('Purpose: recovery access'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('save-land-access-note')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(acknowledgement);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('save-land-access-note')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}

LandAccessNote _note() => LandAccessNote(
  id: 'field-a',
  geometry: LandAccessGeometry(
    kind: LandAccessGeometryKind.point,
    points: const [GeoPoint(latitude: 51.1, longitude: -2.1)],
  ),
  outcome: LandAccessOutcome.askFirst,
  gateNotes: 'Ask before opening the gate.',
  confirmedAt: DateTime.utc(2026, 8, 24),
  recordedBy: 'Synthetic tester',
  provenance: LandAccessProvenance.crewObservation,
  consentStatus: LandAccessConsentStatus.notRecorded,
  reviewAfter: DateTime.utc(2027, 8, 24),
  createdAt: DateTime.utc(2026, 8, 24),
  updatedAt: DateTime.utc(2026, 8, 24),
);

class _MemoryStore implements LandAccessNoteStore {
  _MemoryStore(List<LandAccessNote> notes) : _notes = [...notes];

  List<LandAccessNote> _notes;
  final List<LandAccessExportMetadata> _exports = [];

  @override
  Future<void> delete(String noteId) async {
    _notes.removeWhere((note) => note.id == noteId);
    _exports.removeWhere((item) => item.noteIds.contains(noteId));
  }

  @override
  Future<List<LandAccessExportMetadata>> loadExportMetadata() async =>
      List.unmodifiable(_exports);

  @override
  Future<List<LandAccessNote>> loadNotes() async => List.unmodifiable(_notes);

  @override
  Future<void> recordExport(LandAccessExportMetadata metadata) async {
    _exports.add(metadata);
  }

  @override
  Future<void> upsert(LandAccessNote note) async {
    _notes = [..._notes.where((item) => item.id != note.id), note];
  }
}
