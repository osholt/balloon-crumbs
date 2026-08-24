import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, Object?> fixture;

  setUpAll(() {
    fixture = Map<String, Object?>.from(
      jsonDecode(
            File(
              'test/fixtures/launch_recovery_acceptance.json',
            ).readAsStringSync(),
          )
          as Map,
    );
  });

  test('the acceptance fixture is deterministic and wholly synthetic', () {
    expect(fixture['schemaVersion'], 1);
    expect(fixture['seed'], 742023);
    expect(fixture['generatedCoordinates'], isTrue);
    expect(DateTime.parse(fixture['startTime']! as String).isUtc, isTrue);

    final encoded = jsonEncode(fixture).toLowerCase();
    for (final privateField in ['phone', 'email', 'contact', 'tucker']) {
      expect(encoded, isNot(contains(privateField)));
    }
  });

  test('five devices occupy one balloon and three independent vehicles', () {
    final crafts = (fixture['crafts']! as List).cast<Map<String, Object?>>();
    final devices = (fixture['devices']! as List).cast<Map<String, Object?>>();
    final craftIds = {for (final craft in crafts) craft['id']};

    expect(fixture['preLaunchSeconds'], greaterThanOrEqualTo(45 * 60));
    expect(devices, hasLength(5));
    expect({for (final device in devices) device['id']}, hasLength(5));
    expect(crafts.where((craft) => craft['kind'] == 'balloon'), hasLength(1));
    expect(crafts.where((craft) => craft['kind'] == 'vehicle'), hasLength(3));
    expect(
      devices.every((device) => craftIds.contains(device['craftId'])),
      isTrue,
    );
  });

  test('the timeline and fault matrix cover the complete recovery loop', () {
    final timeline = (fixture['timeline']! as List)
        .cast<Map<String, Object?>>();
    final events = {for (final item in timeline) item['event']};
    expect(
      events,
      containsAll({
        'settingUp',
        'deviceReconnect',
        'flightStartedByCrew',
        'intendedLandingUpdated',
        'flightLanded',
        'flightLandingRetracted',
        'recoveryComplete',
      }),
    );
    expect(
      timeline.where((item) => item['event'] == 'flightLanded'),
      hasLength(2),
    );

    final faults = (fixture['faults']! as List).cast<Map<String, Object?>>();
    expect(
      {for (final fault in faults) fault['kind']},
      containsAll({
        'gpsLoss',
        'inaccurateFix',
        'altitudeLoss',
        'staleWind',
        'clockSkew',
        'relayDelay',
        'duplicateEvent',
        'outOfOrderReplay',
        'routeProviderFailure',
        'unreachableRoadCandidates',
      }),
    );

    final linkModes = (fixture['linkModes']! as List)
        .cast<Map<String, Object?>>();
    expect({
      for (final change in linkModes) change['mode'],
    }, containsAll({'internetAndNearby', 'nearbyOnly', 'disconnected'}));

    final carPlay = Map<String, Object?>.from(fixture['carPlay']! as Map);
    expect(carPlay['orientations'], containsAll(['northUp', 'directionUp']));
    expect(
      carPlay['targets'],
      containsAll(['balloonRendezvous', 'intendedLandingArea']),
    );
  });
}
