import 'dart:math';
import 'dart:typed_data';

import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/land_access_note.dart';
import 'package:balloon_crumbs/services/land_access_note_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LandAccessNoteExportCodec codec;

  setUp(() {
    codec = LandAccessNoteExportCodec(iterations: 10000, random: Random(42));
  });

  test(
    'authenticated encrypted export round trips governance fields',
    () async {
      final note = _note();
      final encrypted = await codec.encrypt(
        notes: [note],
        passphrase: 'correct horse battery staple',
        createdAt: DateTime.utc(2026, 8, 24),
        exportId: 'export-1',
      );

      final text = String.fromCharCodes(encrypted.contents);
      expect(text, isNot(contains('Pat')));
      expect(text, isNot(contains('07000')));
      expect(text, contains('AES-256-GCM'));

      final restored = await codec.decrypt(
        encrypted.contents,
        'correct horse battery staple',
      );
      expect(restored.single.toJson(), note.toJson());
    },
  );

  test('wrong passphrase and tampering fail authentication', () async {
    final encrypted = await codec.encrypt(
      notes: [_note()],
      passphrase: 'correct horse battery staple',
      createdAt: DateTime.utc(2026, 8, 24),
      exportId: 'export-1',
    );

    await expectLater(
      codec.decrypt(encrypted.contents, 'this passphrase is wrong'),
      throwsFormatException,
    );

    final tampered = Uint8List.fromList(encrypted.contents);
    final index = tampered.lastIndexWhere((byte) => byte != 0x7D);
    tampered[index] = tampered[index] == 0x41 ? 0x42 : 0x41;
    await expectLater(
      codec.decrypt(tampered, 'correct horse battery staple'),
      throwsFormatException,
    );
  });

  test('exports require a deliberate non-trivial passphrase', () async {
    await expectLater(
      codec.encrypt(
        notes: [_note()],
        passphrase: 'short',
        createdAt: DateTime.utc(2026, 8, 24),
        exportId: 'export-1',
      ),
      throwsFormatException,
    );
  });
}

LandAccessNote _note() => LandAccessNote(
  id: 'field-a',
  geometry: LandAccessGeometry(
    kind: LandAccessGeometryKind.point,
    points: const [GeoPoint(latitude: 51.1, longitude: -2.1)],
  ),
  outcome: LandAccessOutcome.permissionConfirmed,
  firstName: 'Pat',
  phoneNumber: '07000 000000',
  gateNotes: 'Phone before using the gate.',
  confirmedAt: DateTime.utc(2026, 8, 24),
  recordedBy: 'Synthetic tester',
  provenance: LandAccessProvenance.landContact,
  consentStatus: LandAccessConsentStatus.verbal,
  reviewAfter: DateTime.utc(2027, 8, 24),
  createdAt: DateTime.utc(2026, 8, 24),
  updatedAt: DateTime.utc(2026, 8, 24),
);
