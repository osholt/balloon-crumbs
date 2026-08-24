import 'package:balloon_crumbs/domain/geo_point.dart' as awareness;
import 'package:balloon_crumbs/domain/imported_route.dart' as route;
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/domain/route_preferences.dart';
import 'package:balloon_crumbs/services/chase_guidance_target.dart';
import 'package:balloon_crumbs/services/chase_rendezvous_planner.dart';
import 'package:balloon_crumbs/services/geo_calculations.dart';
import 'package:balloon_crumbs/services/road_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 9);
  const origin = route.GeoPoint(latitude: 51.40, longitude: -2.60);

  test(
    'raw flight evidence is never submitted as a driving endpoint',
    () async {
      final routing = _FakeRoutingService();
      final destination = const ChaseGuidanceTargetResolver().resolve(
        target: ChaseGuidanceTarget.balloon,
        now: now,
        balloonFix: _fix(now, heading: 45, speed: 5),
      )!;

      final selection = await ChaseRendezvousPlanner(
        routingService: routing,
      ).plan(origin: origin, destination: destination);

      expect(routing.requests, hasLength(4));
      for (final request in routing.requests) {
        final submitted = awareness.GeoPoint(
          latitude: request.last.latitude,
          longitude: request.last.longitude,
        );
        expect(
          GeoCalculations.distanceMeters(submitted, destination.point),
          greaterThanOrEqualTo(245),
        );
      }
      expect(selection.candidatesAccepted, 4);
      expect(selection.accessConfidence.limitation, contains('unverified'));
    },
  );

  test('provider-rejected and unreachable candidates are excluded', () async {
    final routing = _FakeRoutingService(
      reject: (point) => point.latitude > 51.451,
    );
    final destination = _stationaryDestination(now);

    final selection = await ChaseRendezvousPlanner(
      routingService: routing,
    ).plan(origin: origin, destination: destination);

    expect(selection.candidatesAttempted, 4);
    expect(selection.candidatesAccepted, lessThan(4));
    expect(selection.roadEndpoint.latitude, lessThanOrEqualTo(51.451));
  });

  test(
    'the previous endpoint survives small score gains but not large ones',
    () async {
      final destination = _stationaryDestination(now);
      const previous = route.GeoPoint(latitude: 51.45225, longitude: -2.61);
      final stableRouting = _FakeRoutingService(
        durationFor: (point) => _near(point, previous)
            ? const Duration(seconds: 100)
            : const Duration(seconds: 30),
      );

      final retained =
          await ChaseRendezvousPlanner(routingService: stableRouting).plan(
            origin: origin,
            destination: destination,
            previousEndpoint: previous,
          );

      expect(retained.retainedPreviousEndpoint, isTrue);
      expect(_near(retained.roadEndpoint, previous), isTrue);

      final materialRouting = _FakeRoutingService(
        durationFor: (point) => _near(point, previous)
            ? const Duration(seconds: 240)
            : const Duration(seconds: 20),
      );
      final changed =
          await ChaseRendezvousPlanner(routingService: materialRouting).plan(
            origin: origin,
            destination: destination,
            previousEndpoint: previous,
          );

      expect(changed.retainedPreviousEndpoint, isFalse);
      expect(_near(changed.roadEndpoint, previous), isFalse);
    },
  );

  test(
    'all unreachable candidates fail without inventing an endpoint',
    () async {
      final planner = ChaseRendezvousPlanner(
        routingService: _FakeRoutingService(reject: (_) => true),
      );

      await expectLater(
        planner.plan(origin: origin, destination: _stationaryDestination(now)),
        throwsA(isA<ChaseRendezvousPlanningException>()),
      );
    },
  );

  test(
    'crossing, reversal and stationary replay stays deterministic',
    () async {
      final fixes = [
        _fix(now, heading: 0, speed: 5),
        _fix(now.add(const Duration(seconds: 5)), heading: 180, speed: 5),
        _fix(now.add(const Duration(seconds: 10)), heading: null, speed: 0),
      ];

      Future<List<route.GeoPoint>> replay() async {
        final selected = <route.GeoPoint>[];
        for (final fix in fixes) {
          final destination = const ChaseGuidanceTargetResolver().resolve(
            target: ChaseGuidanceTarget.balloon,
            now: fix.recordedAt,
            balloonFix: fix,
          )!;
          final result = await ChaseRendezvousPlanner(
            routingService: _FakeRoutingService(
              durationFor: (point) => Duration(
                seconds: ((point.latitude.abs() * 100000) % 240).round() + 30,
              ),
            ),
          ).plan(origin: origin, destination: destination);
          selected.add(result.roadEndpoint);
        }
        return selected;
      }

      final first = await replay();
      final second = await replay();
      expect(
        first.map((point) => (point.latitude, point.longitude)),
        second.map((point) => (point.latitude, point.longitude)),
      );
      expect(first, hasLength(3));
      expect(
        (first[0].latitude, first[0].longitude),
        isNot((first[1].latitude, first[1].longitude)),
        reason: 'reversal changes the candidates',
      );
    },
  );

  test(
    'request spacing is applied between, never before, candidates',
    () async {
      final delays = <Duration>[];
      final planner = ChaseRendezvousPlanner(
        routingService: _FakeRoutingService(),
        requestSpacing: const Duration(milliseconds: 1100),
        delay: (duration) async => delays.add(duration),
      );

      await planner.plan(
        origin: origin,
        destination: _stationaryDestination(now),
      );

      expect(delays, const [
        Duration(milliseconds: 1100),
        Duration(milliseconds: 1100),
        Duration(milliseconds: 1100),
      ]);
    },
  );

  test('every candidate uses the stated chase-vehicle constraints', () async {
    final routing = _FakeRoutingService();
    const preferences = RoutePreferences(
      vehicle: ChaseVehicle(heightMetres: 2.8, towing: true),
    );

    await ChaseRendezvousPlanner(routingService: routing).plan(
      origin: origin,
      destination: _stationaryDestination(now),
      preferences: preferences,
    );

    expect(routing.recordedPreferences, everyElement(preferences));
    expect(preferences.requiresValhallaCosting, isTrue);
  });
}

ChaseGuidanceDestination _stationaryDestination(DateTime now) =>
    const ChaseGuidanceTargetResolver().resolve(
      target: ChaseGuidanceTarget.balloon,
      now: now,
      balloonFix: _fix(now, heading: null, speed: 0),
    )!;

LocationSample _fix(
  DateTime recordedAt, {
  required double? heading,
  required double speed,
}) => LocationSample(
  position: const awareness.GeoPoint(latitude: 51.45, longitude: -2.61),
  recordedAt: recordedAt,
  accuracyMeters: 8,
  speedMetersPerSecond: speed,
  headingDegrees: heading,
);

bool _near(route.GeoPoint first, route.GeoPoint second) =>
    (first.latitude - second.latitude).abs() < 0.0001 &&
    (first.longitude - second.longitude).abs() < 0.0001;

class _FakeRoutingService implements RoadRoutingService {
  _FakeRoutingService({this.reject, this.durationFor = _defaultDuration});

  final bool Function(route.GeoPoint point)? reject;
  final Duration Function(route.GeoPoint point) durationFor;
  final List<List<route.GeoPoint>> requests = [];
  final List<RoutePreferences?> recordedPreferences = [];

  @override
  Future<RoadRouteResult> routeThrough(
    List<route.GeoPoint> waypoints, {
    RoutePreferences? preferences,
    double? originBearingDegrees,
  }) async {
    requests.add(List.unmodifiable(waypoints));
    recordedPreferences.add(preferences);
    final endpoint = waypoints.last;
    if (reject?.call(endpoint) == true) {
      throw const FormatException('provider rejected candidate');
    }
    return RoadRouteResult(
      points: List.unmodifiable(waypoints),
      distanceMeters: 1000,
      duration: durationFor(endpoint),
      preferences: preferences,
    );
  }

  static Duration _defaultDuration(route.GeoPoint _) =>
      const Duration(minutes: 5);
}
