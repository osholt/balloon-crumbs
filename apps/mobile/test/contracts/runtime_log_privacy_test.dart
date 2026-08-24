import 'dart:io';

import 'package:balloon_crumbs/data/ride_diagnostics_log_store.dart';
import 'package:balloon_crumbs/services/ride_diagnostics_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime debug output cannot interpolate locations or raw failures', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final unsafe = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r'debugPrint\([\s\S]{0,240}?\);',
      ).allMatches(source)) {
        final statement = match.group(0)!;
        if (statement.contains(r'$error') ||
            statement.contains('camera.target.latitude') ||
            statement.contains('camera.target.longitude')) {
          unsafe.add('${file.path}: $statement');
        }
      }
      for (final match in RegExp(
        r'recordNote\([\s\S]{0,180}?\);',
      ).allMatches(source)) {
        if (match.group(0)!.contains(r'$error')) {
          unsafe.add('${file.path}: ${match.group(0)}');
        }
      }
    }
    expect(unsafe, isEmpty, reason: unsafe.join('\n'));
  });

  test('diagnostic exports never retain the reusable flight code', () {
    final recorder = RideDiagnosticsRecorder(
      clock: () => DateTime.utc(2026, 8, 24),
    )..recordNote('test');
    final rendered = recorder.render(rideCode: 'TUCKER', appBuild: 'test');
    expect(rendered, isNot(contains('TUCKER')));

    final inherited = '$rendered\nFlight: TUCKER\nRide: TUCKER';
    final sanitized = RideDiagnosticsLog.withoutCredentialHeader(inherited);
    expect(sanitized, isNot(contains('TUCKER')));
  });
}
