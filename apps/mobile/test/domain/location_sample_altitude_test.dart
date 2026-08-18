import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';

/// Balloon altitude on the live telemetry type (`docs/delivery-plan.md` WP2,
/// issue #16).
///
/// The rule these tests exist to hold: an absent altitude and a measured zero
/// are different answers, and no path may quietly turn one into the other.
void main() {
  final at = DateTime.utc(2026, 7, 17, 10);
  const somewhere = GeoPoint(latitude: 51.45, longitude: -2.59);

  LocationSample sample({
    double? altitudeMeters,
    AltitudeSource altitudeSource = AltitudeSource.unknown,
    double? altitudeAccuracyMeters,
    double? verticalSpeedMetersPerSecond,
  }) => LocationSample(
    position: somewhere,
    recordedAt: at,
    accuracyMeters: 5,
    altitudeMeters: altitudeMeters,
    altitudeSource: altitudeSource,
    altitudeAccuracyMeters: altitudeAccuracyMeters,
    verticalSpeedMetersPerSecond: verticalSpeedMetersPerSecond,
  );

  group('an absent altitude is not a zero altitude', () {
    test(
      'a fix with no altitude says so rather than reporting ground level',
      () {
        final fix = sample();

        expect(fix.hasAltitude, isFalse);
        expect(fix.altitudeMeters, isNull);
        expect(fix.altitudeSource, AltitudeSource.unknown);
        expect(fix.altitudeAccuracyMeters, isNull);
      },
    );

    test('a balloon measured at ground level still has an altitude', () {
      final fix = sample(
        altitudeMeters: 0,
        altitudeSource: AltitudeSource.gnss,
        altitudeAccuracyMeters: 3,
      );

      expect(fix.hasAltitude, isTrue);
      expect(fix.altitudeMeters, 0);
    });

    test('a source or an accuracy without a reading is rejected outright', () {
      expect(
        () => sample(altitudeAccuracyMeters: 3),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => sample(altitudeSource: AltitudeSource.barometric),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a negative vertical accuracy is rejected', () {
      expect(
        () => sample(altitudeMeters: 400, altitudeAccuracyMeters: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('the wire form', () {
    test('round-trips a measured altitude with its source and accuracy', () {
      final fix = sample(
        altitudeMeters: 412.5,
        altitudeSource: AltitudeSource.barometric,
        altitudeAccuracyMeters: 2.5,
        verticalSpeedMetersPerSecond: -1.4,
      );

      final decoded = LocationSample.fromJson(fix.toJson());

      expect(decoded.altitudeMeters, 412.5);
      expect(decoded.altitudeSource, AltitudeSource.barometric);
      expect(decoded.altitudeAccuracyMeters, 2.5);
      expect(decoded.verticalSpeedMetersPerSecond, -1.4);
    });

    test('a fix without altitude writes no altitude keys at all', () {
      final json = sample().toJson();

      expect(json.containsKey('altitudeMeters'), isFalse);
      expect(json.containsKey('altitudeSource'), isFalse);
      expect(json.containsKey('altitudeAccuracyMeters'), isFalse);
      expect(LocationSample.fromJson(json).hasAltitude, isFalse);
    });

    test("an older peer's payload reads as a fix without altitude", () {
      final legacy = {
        'position': somewhere.toJson(),
        'recordedAt': at.toIso8601String(),
        'accuracyMeters': 5.0,
        'speedMetersPerSecond': 12.0,
        'headingDegrees': 90.0,
      };

      final decoded = LocationSample.fromJson(legacy);

      expect(decoded.hasAltitude, isFalse);
      expect(decoded.altitudeSource, AltitudeSource.unknown);
      expect(decoded.speedMetersPerSecond, 12.0);
    });

    test('an altitude source this build does not know degrades', () {
      final decoded = LocationSample.fromJson({
        ...sample(
          altitudeMeters: 400,
          altitudeSource: AltitudeSource.gnss,
        ).toJson(),
        'altitudeSource': 'lidarSomething',
      });

      expect(decoded.altitudeMeters, 400);
      expect(decoded.altitudeSource, AltitudeSource.unknown);
    });

    test('a source or accuracy arriving without a reading is dropped', () {
      final decoded = LocationSample.fromJson({
        'position': somewhere.toJson(),
        'recordedAt': at.toIso8601String(),
        'accuracyMeters': 5.0,
        'altitudeSource': 'barometric',
        'altitudeAccuracyMeters': 2.0,
      });

      expect(decoded.hasAltitude, isFalse);
      expect(decoded.altitudeSource, AltitudeSource.unknown);
      expect(decoded.altitudeAccuracyMeters, isNull);
    });
  });

  test('measurement time stays distinct from receipt time', () {
    final fix = sample(
      altitudeMeters: 400,
      altitudeSource: AltitudeSource.gnss,
    );
    final location = RiderLocation(
      riderId: 'pilot',
      displayName: 'Oliver',
      role: RideRole.rider,
      sample: fix,
      receivedAt: at.add(const Duration(seconds: 30)),
    );

    final decoded = RiderLocation.fromJson(location.toJson());

    expect(decoded.sample.recordedAt, at.toLocal());
    expect(decoded.receivedAt, at.add(const Duration(seconds: 30)).toLocal());
    expect(decoded.sample.altitudeMeters, 400);
  });
}
