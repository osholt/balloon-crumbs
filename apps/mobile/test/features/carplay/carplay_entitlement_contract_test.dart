import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every signed iOS configuration requests the CarPlay maps entitlement',
    () {
      for (final path in [
        'ios/Runner/DebugProfile.entitlements',
        'ios/Runner/Release.entitlements',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('<key>com.apple.developer.carplay-maps</key>'),
          reason: path,
        );
        expect(source, contains('<true/>'), reason: path);
      }
    },
  );

  test('Info.plist registers the CarPlay navigation scene', () {
    final source = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      source,
      contains('<key>CPTemplateApplicationSceneSessionRoleApplication</key>'),
    );
    expect(source, contains('<string>CPTemplateApplicationScene</string>'));
    expect(
      source,
      contains('<string>\$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>'),
    );
  });

  test(
    'both distribution paths reject an IPA without the granted entitlement',
    () {
      final workflow = File(
        '../../.github/workflows/testflight.yml',
      ).readAsStringSync();
      final localUpload = File(
        '../../tools/testflight/build-and-upload.sh',
      ).readAsStringSync();
      expect(workflow, contains('com.apple.developer.carplay-maps'));
      expect(workflow, contains('The IPA has no CarPlay maps entitlement'));
      expect(localUpload, contains('com.apple.developer.carplay-maps'));
      expect(localUpload, contains('signed IPA is missing'));
    },
  );
}
