import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/land_access_note.dart';
import '../domain/land_access_note_store.dart';
import '../services/land_access_note_export.dart';

class LandAccessNoteController extends ChangeNotifier {
  LandAccessNoteController(
    this._store, {
    LandAccessNoteExportCodec? exportCodec,
    Uuid? uuid,
  }) : _exportCodec = exportCodec ?? LandAccessNoteExportCodec(),
       _uuid = uuid ?? const Uuid();

  final LandAccessNoteStore _store;
  final LandAccessNoteExportCodec _exportCodec;
  final Uuid _uuid;

  List<LandAccessNote> _notes = const [];
  bool _loaded = false;
  bool _busy = false;
  String? _errorMessage;
  bool _showOnMap = false;

  List<LandAccessNote> get notes => _notes;
  bool get loaded => _loaded;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  bool get showOnMap => _showOnMap;

  void setShowOnMap(bool value) {
    if (_showOnMap == value) return;
    _showOnMap = value;
    notifyListeners();
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _notes = await _store.loadNotes();
      _loaded = true;
    } on Object {
      _errorMessage = 'Private land access notes could not be opened.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> save(LandAccessNote note) async {
    await _run(() async {
      await _store.upsert(note);
      _notes = await _store.loadNotes();
      _loaded = true;
    });
  }

  Future<void> delete(String noteId) async {
    await _run(() async {
      await _store.delete(noteId);
      _notes = await _store.loadNotes();
    });
  }

  Future<LandAccessNoteExport?> export({
    required Iterable<String> noteIds,
    required String passphrase,
    DateTime? now,
  }) async {
    LandAccessNoteExport? result;
    await _run(() async {
      final selectedIds = noteIds.toSet();
      final selected = _notes
          .where((note) => selectedIds.contains(note.id))
          .toList(growable: false);
      final createdAt = (now ?? DateTime.now()).toUtc();
      result = await _exportCodec.encrypt(
        notes: selected,
        passphrase: passphrase,
        createdAt: createdAt,
        exportId: _uuid.v4(),
      );
      await _store.recordExport(
        LandAccessExportMetadata(
          exportId: result!.exportId,
          noteIds: result!.noteIds,
          createdAt: createdAt,
        ),
      );
    });
    return result;
  }

  Future<int> import(Uint8List contents, String passphrase) async {
    var imported = 0;
    await _run(() async {
      final incoming = await _exportCodec.decrypt(contents, passphrase);
      final existing = {
        for (final note in await _store.loadNotes()) note.id: note,
      };
      for (final note in incoming) {
        final current = existing[note.id];
        if (current == null || note.updatedAt.isAfter(current.updatedAt)) {
          await _store.upsert(note);
          imported += 1;
        }
      }
      _notes = await _store.loadNotes();
      _loaded = true;
    });
    return imported;
  }

  String newId() => _uuid.v4();

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } on FormatException catch (error) {
      _errorMessage = error.message;
    } on Object {
      _errorMessage = 'The private land access notes action failed.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
