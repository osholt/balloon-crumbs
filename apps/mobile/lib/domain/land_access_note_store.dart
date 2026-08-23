import 'land_access_note.dart';

abstract interface class LandAccessNoteStore {
  Future<List<LandAccessNote>> loadNotes();

  Future<void> upsert(LandAccessNote note);

  /// Removes the note and every local export-metadata reference to it.
  Future<void> delete(String noteId);

  Future<List<LandAccessExportMetadata>> loadExportMetadata();

  Future<void> recordExport(LandAccessExportMetadata metadata);
}
