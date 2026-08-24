import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile release workflows never embed an OpenAIP credential', () {
    for (final path in [
      '../../.github/workflows/testflight.yml',
      '../../.github/workflows/android-internal.yml',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('BALLOON_CRUMBS_OPENAIP_API_KEY')),
        reason: path,
      );
    }
  });

  test('the live flight shell cannot enable aeronautical tiles', () {
    final source = File(
      'lib/features/ride/active_ride_shell.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('showAeronauticalChart:')));
    expect(source, isNot(contains('AeronauticalChartConfiguration')));
  });

  test('the relay keeps OpenAIP behind a bounded planner-only path', () {
    final source = File('../../deploy/Caddyfile.oracle').readAsStringSync();
    expect(source, contains('^/maps/openaip/'));
    expect(source, contains('x-openaip-api-key'));
    expect(source, contains('BALLOON_CRUMBS_OPENAIP_API_KEY'));
  });

  test('the optional OS key remains behind a close-zoom relay path', () {
    final caddy = File('../../deploy/Caddyfile.oracle').readAsStringSync();
    expect(caddy, contains('^/maps/os/outdoor/(1[3-6])/'));
    expect(caddy, isNot(contains('1[3-9]|20')));
    expect(caddy, contains('header_up key'));
    expect(caddy, contains('BALLOON_CRUMBS_OS_MAPS_API_KEY'));
    expect(caddy, contains('private, max-age=86400'));

    for (final path in [
      '../../.github/workflows/testflight.yml',
      '../../.github/workflows/android-internal.yml',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('BALLOON_CRUMBS_OS_MAPS_API_KEY')),
        reason: path,
      );
    }
  });
}
