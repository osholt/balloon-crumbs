import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS declares active-flight location and spoken-audio background modes',
    () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('<key>UIBackgroundModes</key>'));
      expect(plist, contains('<string>location</string>'));
      expect(plist, contains('<string>audio</string>'));
    },
  );
}
