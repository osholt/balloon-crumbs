import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/services/route_twistiness.dart';

/// Geometry fixtures for the bend score (#46, #182).
///
/// These were described as pinning the score against
/// `apps/website/planner-core.test.mjs`, so that a drift in either
/// implementation failed one of two suites. That file does not exist in this
/// repository and never has, so what these actually do is pin the score against
/// itself — a regression test, not a cross-check. Still worth having, and worth
/// not being wrong about.
void main() {
  test('the calibration fixture scores what it has always scored', () {
    final score = RouteTwistiness.score(
      _sinusoidalLane,
      distanceMeters: _sinusoidalLaneMeters,
    );

    expect(score, closeTo(29.115031244781, 1e-9));
    expect(RouteTwistiness.label(score), 'Twisty');
    expect(RouteTwistiness.describe(score), '29°/km · Twisty');
  });

  test('the score falls back to the geometry length', () {
    expect(
      RouteTwistiness.geometryLengthMeters(_sinusoidalLane),
      closeTo(_sinusoidalLaneMeters, 1e-6),
    );
    expect(
      RouteTwistiness.score(_sinusoidalLane),
      closeTo(29.115031244781, 1e-9),
    );
  });

  test('a straight road scores zero', () {
    const straight = [
      GeoPoint(latitude: 51.4, longitude: -2.5),
      GeoPoint(latitude: 51.4, longitude: -2.4),
      GeoPoint(latitude: 51.4, longitude: -2.3),
      GeoPoint(latitude: 51.4, longitude: -2.2),
    ];

    expect(RouteTwistiness.score(straight), 0);
    expect(RouteTwistiness.label(0), 'Gentle');
  });

  test('geometry too short to carry a bend scores zero', () {
    expect(RouteTwistiness.score(const []), 0);
    expect(
      RouteTwistiness.score(const [
        GeoPoint(latitude: 51.4, longitude: -2.5),
        GeoPoint(latitude: 51.4, longitude: -2.4),
      ]),
      0,
    );
    expect(
      RouteTwistiness.score(_sinusoidalLane, distanceMeters: 0),
      0,
      reason: 'a zero distance is not a divisor',
    );
  });

  test('label bands are the published thresholds', () {
    expect(RouteTwistiness.label(11.9), 'Gentle');
    expect(RouteTwistiness.label(12), 'Flowing');
    expect(RouteTwistiness.label(24.9), 'Flowing');
    expect(RouteTwistiness.label(25), 'Twisty');
    expect(RouteTwistiness.label(44.9), 'Twisty');
    expect(RouteTwistiness.label(45), 'Very twisty');
    expect(RouteTwistiness.describe(-1), '—');
    expect(RouteTwistiness.describe(double.nan), '—');
  });

  group('alternative selection within the detour allowance', () {
    // Named for the road, not the rider: the straight one is the one a trailer
    // can follow, the bendy ones are the ones it cannot.
    const straightest = (duration: 3600.0, bends: 5.0);
    const bendy = (duration: 4000.0, bends: 40.0);
    const hairpins = (duration: 4100.0, bends: 90.0);

    ({double duration, double bends})? choose(
      List<({double duration, double bends})> candidates, {
      RoutePreferences preferences = RoutePreferences.defaults,
    }) => RouteTwistiness.chooseWithinDetour(
      candidates,
      preferences: preferences,
      duration: (candidate) => candidate.duration,
      bendScore: (candidate) => candidate.bends,
    );

    const towing = RoutePreferences(vehicle: ChaseVehicle(towing: true));

    test('not towing keeps the provider order and ignores bends', () {
      // The engine's first route is its quickest. With no trailer there is
      // nothing to trade time for, so it is taken as offered.
      expect(choose(const [hairpins, straightest]), hairpins);
    });

    test('towing takes the straightest route it can afford', () {
      // The inversion this change is built on: the same score the motorcycle
      // build used to seek corners now avoids them.
      expect(
        choose(const [bendy, hairpins, straightest], preferences: towing),
        straightest,
      );
    });

    test('towing will not exceed the allowance to straighten a route', () {
      // 3600 * 1.15 = 4140 s. A straighter road half an hour away is not worth
      // it to a crew whose balloon is coming down now.
      expect(
        choose(const [
          bendy,
          (duration: 9000.0, bends: 1.0),
        ], preferences: towing),
        bendy,
        reason: '9000 s exceeds the 4600 s allowance',
      );
    });

    test('the allowance does not depend on the road style', () {
      // It is the trailer that makes a straighter road worth 15% more time, so
      // both styles reach the same alternative. Hanging tolerance off the style
      // is what previously made the default style allow nothing at all.
      for (final style in RouteStyle.values) {
        expect(
          choose(
            const [bendy, (duration: 4500.0, bends: 2.0)],
            preferences: RoutePreferences(
              style: style,
              vehicle: const ChaseVehicle(towing: true),
            ),
          ),
          (duration: 4500.0, bends: 2.0),
          reason: '4000 * 1.15 = 4600 s, so it fits — ${style.name}',
        );
      }
    });

    test('a single alternative is the answer whatever is towed', () {
      expect(choose(const [hairpins], preferences: towing), hairpins);
    });

    test('no alternatives at all is null, never an invented route', () {
      expect(choose(const [], preferences: towing), isNull);
    });
  });
}

/// Distance of [_sinusoidalLane].
const _sinusoidalLaneMeters = 12963.688380;

/// A deterministic sinusoidal lane.
const _sinusoidalLane = [
  GeoPoint(latitude: 51.4, longitude: -2.5),
  GeoPoint(latitude: 51.402337, longitude: -2.496),
  GeoPoint(latitude: 51.404304, longitude: -2.492),
  GeoPoint(latitude: 51.405592, longitude: -2.488),
  GeoPoint(latitude: 51.405997, longitude: -2.484),
  GeoPoint(latitude: 51.405456, longitude: -2.48),
  GeoPoint(latitude: 51.404053, longitude: -2.476),
  GeoPoint(latitude: 51.40201, longitude: -2.472),
  GeoPoint(latitude: 51.39965, longitude: -2.468),
  GeoPoint(latitude: 51.397345, longitude: -2.464),
  GeoPoint(latitude: 51.395459, longitude: -2.46),
  GeoPoint(latitude: 51.39429, longitude: -2.456),
  GeoPoint(latitude: 51.394023, longitude: -2.452),
  GeoPoint(latitude: 51.394699, longitude: -2.448),
  GeoPoint(latitude: 51.396212, longitude: -2.444),
  GeoPoint(latitude: 51.398324, longitude: -2.44),
  GeoPoint(latitude: 51.400699, longitude: -2.436),
  GeoPoint(latitude: 51.402965, longitude: -2.432),
  GeoPoint(latitude: 51.404762, longitude: -2.428),
  GeoPoint(latitude: 51.405808, longitude: -2.424),
  GeoPoint(latitude: 51.405936, longitude: -2.42),
  GeoPoint(latitude: 51.405128, longitude: -2.416),
  GeoPoint(latitude: 51.40351, longitude: -2.412),
  GeoPoint(latitude: 51.401337, longitude: -2.408),
  GeoPoint(latitude: 51.398954, longitude: -2.404),
  GeoPoint(latitude: 51.396736, longitude: -2.4),
  GeoPoint(latitude: 51.395033, longitude: -2.396),
  GeoPoint(latitude: 51.394114, longitude: -2.392),
  GeoPoint(latitude: 51.394125, longitude: -2.388),
  GeoPoint(latitude: 51.395063, longitude: -2.384),
  GeoPoint(latitude: 51.396781, longitude: -2.38),
  GeoPoint(latitude: 51.399006, longitude: -2.376),
  GeoPoint(latitude: 51.401389, longitude: -2.372),
  GeoPoint(latitude: 51.403552, longitude: -2.368),
  GeoPoint(latitude: 51.405155, longitude: -2.364),
  GeoPoint(latitude: 51.405944, longitude: -2.36),
  GeoPoint(latitude: 51.405794, longitude: -2.356),
  GeoPoint(latitude: 51.40473, longitude: -2.352),
  GeoPoint(latitude: 51.402918, longitude: -2.348),
  GeoPoint(latitude: 51.400647, longitude: -2.344),
];
