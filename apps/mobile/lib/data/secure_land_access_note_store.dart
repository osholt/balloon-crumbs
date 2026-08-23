import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/land_access_note.dart';
import '../domain/land_access_note_store.dart';

/// Device-local storage backed by the platform keychain/keystore.
///
/// The document is deliberately absent from SharedPreferences, SQLite, relay
/// events and diagnostic logs because it may contain a private phone number.
class SecureLandAccessNoteStore implements LandAccessNoteStore {
  const SecureLandAccessNoteStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'balloon_crumbs_land_access_notes_v1';
  static const _maximumNotes = 500;
  static const _maximumExports = 250;

  final FlutterSecureStorage _storage;

  Future<_StoredLandAccessDocument> _load() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return const _StoredLandAccessDocument();
    try {
      final value = Map<String, Object?>.from(jsonDecode(encoded) as Map);
      if (value['schemaVersion'] != 1) {
        throw const FormatException('Unsupported land access store.');
      }
      final notes = (value['notes'] as List? ?? const [])
          .map(
            (item) =>
                LandAccessNote.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(growable: false);
      final exports = (value['exports'] as List? ?? const [])
          .map(
            (item) => LandAccessExportMetadata.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
      if (notes.length > _maximumNotes ||
          exports.length > _maximumExports ||
          notes.map((note) => note.id).toSet().length != notes.length ||
          exports.map((item) => item.exportId).toSet().length !=
              exports.length) {
        throw const FormatException('Land access store is invalid.');
      }
      return _StoredLandAccessDocument(notes: notes, exports: exports);
    } on Object {
      await _storage.delete(key: _key);
      return const _StoredLandAccessDocument();
    }
  }

  Future<void> _save(_StoredLandAccessDocument document) async {
    if (document.notes.isEmpty && document.exports.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'schemaVersion': 1,
        'notes': document.notes
            .map((note) => note.toJson())
            .toList(growable: false),
        'exports': document.exports
            .map((item) => item.toJson())
            .toList(growable: false),
      }),
    );
  }

  @override
  Future<List<LandAccessNote>> loadNotes() async =>
      List.unmodifiable((await _load()).notes);

  @override
  Future<List<LandAccessExportMetadata>> loadExportMetadata() async =>
      List.unmodifiable((await _load()).exports);

  @override
  Future<void> upsert(LandAccessNote note) async {
    final document = await _load();
    final notes = [...document.notes]
      ..removeWhere((item) => item.id == note.id);
    notes.add(note);
    notes.sort((a, b) => b.confirmedAt.compareTo(a.confirmedAt));
    if (notes.length > _maximumNotes) {
      throw const FormatException(
        'No more than 500 land access notes are kept.',
      );
    }
    await _save(
      _StoredLandAccessDocument(notes: notes, exports: document.exports),
    );
  }

  @override
  Future<void> delete(String noteId) async {
    final document = await _load();
    final notes = [...document.notes]..removeWhere((item) => item.id == noteId);
    final exports = <LandAccessExportMetadata>[];
    for (final item in document.exports) {
      final remainingIds = item.noteIds
          .where((id) => id != noteId)
          .toList(growable: false);
      if (remainingIds.isEmpty) continue;
      exports.add(
        LandAccessExportMetadata(
          exportId: item.exportId,
          noteIds: remainingIds,
          createdAt: item.createdAt,
        ),
      );
    }
    await _save(_StoredLandAccessDocument(notes: notes, exports: exports));
  }

  @override
  Future<void> recordExport(LandAccessExportMetadata metadata) async {
    final document = await _load();
    final exports = [...document.exports]
      ..removeWhere((item) => item.exportId == metadata.exportId)
      ..add(metadata);
    exports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (exports.length > _maximumExports) {
      exports.removeRange(_maximumExports, exports.length);
    }
    await _save(
      _StoredLandAccessDocument(notes: document.notes, exports: exports),
    );
  }
}

class _StoredLandAccessDocument {
  const _StoredLandAccessDocument({
    this.notes = const [],
    this.exports = const [],
  });

  final List<LandAccessNote> notes;
  final List<LandAccessExportMetadata> exports;
}
