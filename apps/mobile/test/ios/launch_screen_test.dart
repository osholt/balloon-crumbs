import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The launch screen is the first thing a tester sees, and it is the easiest
/// thing in the build to leave wrong: nothing fails, no warning appears in a
/// normal build, and it is on screen for the half second nobody screenshots.
///
/// Flutter ships 68-byte 1x1 transparent placeholders. `flutter build ipa` does
/// say so, but only in the middle of a long release log.
void main() {
  const imageset = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

  /// Width and height straight out of the PNG IHDR chunk: 8-byte signature,
  /// then a 4-byte length and the "IHDR" tag, then width and height as
  /// big-endian 32-bit integers. Cheaper and more honest than decoding.
  ({int width, int height}) pngSize(Uint8List bytes) {
    expect(bytes.sublist(0, 8), [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ], reason: 'not a PNG');
    expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR');
    final header = ByteData.sublistView(bytes, 16, 24);
    return (width: header.getUint32(0), height: header.getUint32(4));
  }

  test('the launch images are not Flutter placeholders', () {
    for (final scale in [1, 2, 3]) {
      final suffix = scale == 1 ? '' : '@${scale}x';
      final file = File('$imageset/LaunchImage$suffix.png');
      expect(file.existsSync(), isTrue, reason: file.path);
      final bytes = file.readAsBytesSync();
      // The placeholder is a 68-byte 1x1. Any real artwork is far larger, and
      // the size check is what catches a revert rather than a redraw.
      expect(
        bytes.length,
        greaterThan(1000),
        reason: '${file.path} looks like the 68-byte placeholder',
      );
      final size = pngSize(bytes);
      expect(
        size.height,
        160 * scale,
        reason: '${file.path} should be 160pt tall at ${scale}x',
      );
      expect(size.width, greaterThan(0));
    }
  });

  test('the launch images keep the balloon aspect ratio across scales', () {
    // A generator bug that resized one asset differently would be invisible on
    // a device: iOS picks exactly one scale for the screen it is on.
    final ratios = [1, 2, 3].map((scale) {
      final suffix = scale == 1 ? '' : '@${scale}x';
      final size = pngSize(
        File('$imageset/LaunchImage$suffix.png').readAsBytesSync(),
      );
      return size.width / size.height;
    }).toList();
    for (final ratio in ratios) {
      expect(ratio, closeTo(ratios.first, 0.01));
    }
    // Taller than wide: a balloon, not the whole square icon. The first cut of
    // the generator caught antialiasing noise across the icon, which put the
    // bounding box around all of it and produced exactly 1.0 here.
    expect(ratios.first, lessThan(0.95));
  });

  test('the storyboard paints the app background, not white', () {
    // A white launch screen on a dark app flashes white at every launch.
    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    expect(
      storyboard,
      contains('red="0.050980392156862744"'),
      reason: 'expected 0xFF0D1117, the app scaffoldBackgroundColor',
    );
    expect(
      storyboard.contains('red="1" green="1" blue="1" alpha="1"'),
      isFalse,
      reason: 'the white background is back',
    );
  });
}
