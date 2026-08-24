import 'package:balloon_crumbs/services/os_final_approach_map_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires an explicit enable flag and bounded secure XYZ template', () {
    const disabled = OsFinalApproachMapConfiguration(
      tileUrlTemplate:
          'https://balloon-crumbs.pages.dev/maps/os/outdoor/{z}/{x}/{y}.png',
    );
    expect(disabled.isConfigured, isFalse);

    const configured = OsFinalApproachMapConfiguration(
      enabled: true,
      tileUrlTemplate:
          'https://balloon-crumbs.pages.dev/maps/os/outdoor/{z}/{x}/{y}.png',
    );
    expect(configured.isConfigured, isTrue);
    expect(configured.minimumZoom, 13);
    expect(configured.maximumZoom, 16);

    const premiumZooms = OsFinalApproachMapConfiguration(
      enabled: true,
      tileUrlTemplate:
          'https://balloon-crumbs.pages.dev/maps/os/outdoor/{z}/{x}/{y}.png',
      maximumZoom: 17,
    );
    expect(premiumZooms.isConfigured, isFalse);

    const insecure = OsFinalApproachMapConfiguration(
      enabled: true,
      tileUrlTemplate: 'http://example.test/{z}/{x}/{y}.png',
    );
    expect(insecure.isConfigured, isFalse);
  });

  test('advertises conservative Great Britain coverage honestly', () {
    const configuration = OsFinalApproachMapConfiguration(enabled: true);
    expect(configuration.covers(latitude: 51.45, longitude: -2.58), isTrue);
    expect(configuration.covers(latitude: 55.95, longitude: -3.19), isTrue);
    expect(configuration.covers(latitude: 54.6, longitude: -5.93), isFalse);
    expect(configuration.covers(latitude: 51.5, longitude: -10), isFalse);
  });
}
