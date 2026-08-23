import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'land access contacts have no relay or diagnostics serialization path',
    () {
      final forbiddenRoots = [
        Directory('../server/src'),
        Directory('lib/internet'),
        Directory('lib/relay'),
        Directory('lib/services'),
      ];
      const forbiddenWireFields = [
        'landAccessNote',
        'landAccessNotes',
        'landContact',
        'contactPhoneNumber',
      ];

      for (final root in forbiddenRoots) {
        for (final entity in root.listSync(recursive: true).whereType<File>()) {
          if (!entity.path.endsWith('.dart') && !entity.path.endsWith('.py')) {
            continue;
          }
          if (entity.path.endsWith('land_access_note_export.dart')) continue;
          final source = entity.readAsStringSync();
          for (final field in forbiddenWireFields) {
            expect(
              source,
              isNot(contains("'$field'")),
              reason: '${entity.path} must not serialize $field',
            );
          }
        }
      }
    },
  );
}
