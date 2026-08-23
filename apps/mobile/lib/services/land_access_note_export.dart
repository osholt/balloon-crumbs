import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/land_access_note.dart';

class LandAccessNoteExport {
  const LandAccessNoteExport({
    required this.exportId,
    required this.createdAt,
    required this.contents,
    required this.noteIds,
  });

  final String exportId;
  final DateTime createdAt;
  final Uint8List contents;
  final List<String> noteIds;
}

/// Password-encrypted, authenticated export format for deliberate crew sharing.
class LandAccessNoteExportCodec {
  LandAccessNoteExportCodec({
    this.iterations = 210000,
    Random? random,
    AesGcm? cipher,
  }) : _random = random ?? Random.secure(),
       _cipher = cipher ?? AesGcm.with256bits() {
    if (iterations < 10000 || iterations > 2000000) {
      throw ArgumentError.value(iterations, 'iterations');
    }
  }

  static const _associatedData = 'balloon-crumbs-land-access-notes-v1';
  final int iterations;
  final Random _random;
  final AesGcm _cipher;

  Future<LandAccessNoteExport> encrypt({
    required List<LandAccessNote> notes,
    required String passphrase,
    required DateTime createdAt,
    required String exportId,
  }) async {
    if (notes.isEmpty) throw const FormatException('Select at least one note.');
    if (passphrase.runes.length < 12) {
      throw const FormatException(
        'Use an export passphrase of at least 12 characters.',
      );
    }
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(passphrase, salt, iterations);
    final clearText = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'exportId': exportId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'notes': notes.map((note) => note.toJson()).toList(growable: false),
      }),
    );
    final box = await _cipher.encrypt(
      clearText,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(_associatedData),
    );
    final envelope = {
      'format': _associatedData,
      'schemaVersion': 1,
      'kdf': {
        'name': 'PBKDF2-HMAC-SHA256',
        'iterations': iterations,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'name': 'AES-256-GCM',
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'cipherText': base64Encode(box.cipherText),
      },
    };
    return LandAccessNoteExport(
      exportId: exportId,
      createdAt: createdAt.toUtc(),
      contents: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      noteIds: List.unmodifiable(notes.map((note) => note.id)),
    );
  }

  Future<List<LandAccessNote>> decrypt(
    Uint8List contents,
    String passphrase,
  ) async {
    if (passphrase.runes.length < 12) {
      throw const FormatException('The export passphrase is too short.');
    }
    try {
      final envelope = Map<String, Object?>.from(
        jsonDecode(utf8.decode(contents, allowMalformed: false)) as Map,
      );
      if (envelope['format'] != _associatedData ||
          envelope['schemaVersion'] != 1) {
        throw const FormatException(
          'This is not a Balloon Crumbs land access export.',
        );
      }
      final kdf = Map<String, Object?>.from(envelope['kdf']! as Map);
      final cipher = Map<String, Object?>.from(envelope['cipher']! as Map);
      final exportIterations = kdf['iterations']! as int;
      if (kdf['name'] != 'PBKDF2-HMAC-SHA256' ||
          cipher['name'] != 'AES-256-GCM' ||
          exportIterations < 10000 ||
          exportIterations > 2000000) {
        throw const FormatException(
          'The encrypted export settings are unsupported.',
        );
      }
      final salt = base64Decode(kdf['salt']! as String);
      final nonce = base64Decode(cipher['nonce']! as String);
      final mac = base64Decode(cipher['mac']! as String);
      final cipherText = base64Decode(cipher['cipherText']! as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException('The encrypted export is malformed.');
      }
      final key = await _deriveKey(passphrase, salt, exportIterations);
      final clearText = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(_associatedData),
      );
      final payload = Map<String, Object?>.from(
        jsonDecode(utf8.decode(clearText, allowMalformed: false)) as Map,
      );
      if (payload['schemaVersion'] != 1 || payload['notes'] is! List) {
        throw const FormatException('The decrypted export is invalid.');
      }
      final notes = (payload['notes']! as List)
          .map(
            (item) =>
                LandAccessNote.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(growable: false);
      if (notes.isEmpty ||
          notes.length > 500 ||
          notes.map((note) => note.id).toSet().length != notes.length) {
        throw const FormatException('The decrypted export is invalid.');
      }
      return List.unmodifiable(notes);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'The passphrase is wrong or the export was changed.',
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('The encrypted export could not be opened.');
    }
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt, int rounds) =>
      Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: rounds,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256), growable: false),
  );
}
