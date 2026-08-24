import 'dart:math' as math;

import '../domain/geo_point.dart' as awareness;
import '../domain/imported_route.dart' as route;
import '../domain/route_preferences.dart';
import 'chase_guidance_target.dart';
import 'geo_calculations.dart';
import 'road_routing.dart';

enum RendezvousAccessConfidence {
  mappedRoadProfile(
    'The routing provider applied its mapped vehicle and access restrictions. '
    'Private access, field entry and safe stopping remain unverified.',
  );

  const RendezvousAccessConfidence(this.limitation);

  final String limitation;
}

class ChaseRendezvousSelection {
  const ChaseRendezvousSelection({
    required this.routeResult,
    required this.requestedCandidate,
    required this.roadEndpoint,
    required this.targetSeparationMeters,
    required this.scoreSeconds,
    required this.accessConfidence,
    required this.retainedPreviousEndpoint,
    required this.candidatesAttempted,
    required this.candidatesAccepted,
  });

  final RoadRouteResult routeResult;
  final route.GeoPoint requestedCandidate;
  final route.GeoPoint roadEndpoint;
  final double targetSeparationMeters;
  final double scoreSeconds;
  final RendezvousAccessConfidence accessConfidence;
  final bool retainedPreviousEndpoint;
  final int candidatesAttempted;
  final int candidatesAccepted;
}

class ChaseRendezvousPlanningException implements Exception {
  const ChaseRendezvousPlanningException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Chooses a stable provider-routed endpoint around flight evidence.
///
/// The evidence coordinate is deliberately never submitted as the driving
/// destination. Four bounded points around its uncertainty area are routed in
/// a deterministic order. The provider's returned endpoint must remain close
/// enough to the evidence, and the previous endpoint is retained unless a new
/// candidate improves the fresh travel-time score materially.
class ChaseRendezvousPlanner {
  ChaseRendezvousPlanner({
    required this.routingService,
    this.requestSpacing = Duration.zero,
    this.minimumScoreImprovement = const Duration(seconds: 90),
    this.minimumCandidateRadiusMeters = 250,
    this.maximumCandidateRadiusMeters = 750,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final RoadRoutingService routingService;
  final Duration requestSpacing;
  final Duration minimumScoreImprovement;
  final double minimumCandidateRadiusMeters;
  final double maximumCandidateRadiusMeters;
  final Future<void> Function(Duration) _delay;

  Future<ChaseRendezvousSelection> plan({
    required route.GeoPoint origin,
    required ChaseGuidanceDestination destination,
    RoutePreferences preferences = RoutePreferences.defaults,
    route.GeoPoint? previousEndpoint,
    double? originBearingDegrees,
  }) async {
    final requests = _candidateRequests(
      destination: destination,
      previousEndpoint: previousEndpoint,
    );
    final accepted = <_ScoredCandidate>[];
    var attempted = 0;
    for (final request in requests) {
      if (attempted > 0 && requestSpacing > Duration.zero) {
        await _delay(requestSpacing);
      }
      attempted += 1;
      try {
        final result = await routingService.routeThrough(
          [origin, request.point],
          preferences: preferences,
          originBearingDegrees: originBearingDegrees,
        );
        if (result.points.length < 2) continue;
        final endpoint = result.points.last;
        final separation = GeoCalculations.distanceMeters(
          awareness.GeoPoint(
            latitude: endpoint.latitude,
            longitude: endpoint.longitude,
          ),
          destination.point,
        );
        if (!separation.isFinite ||
            separation > destination.maximumRoadSeparationMeters) {
          continue;
        }
        accepted.add(
          _ScoredCandidate(
            request: request,
            result: result,
            endpoint: endpoint,
            separationMeters: separation,
            // Prefer real provider travel time. The small endpoint-separation
            // term breaks otherwise-equal routes toward the flight evidence.
            scoreSeconds:
                result.duration.inMilliseconds / 1000 + separation / 10,
          ),
        );
      } on Object {
        // One unreachable or provider-rejected point does not make the other
        // bounded road candidates unsafe to try.
      }
    }
    if (accepted.isEmpty) {
      throw const ChaseRendezvousPlanningException(
        'No provider-routed endpoint stayed within the allowed rendezvous area.',
      );
    }

    accepted.sort((left, right) {
      final byScore = left.scoreSeconds.compareTo(right.scoreSeconds);
      if (byScore != 0) return byScore;
      return left.request.order.compareTo(right.request.order);
    });
    var selected = accepted.first;
    final previous = accepted
        .where((candidate) => candidate.request.isPreviousEndpoint)
        .firstOrNull;
    if (previous != null &&
        !selected.request.isPreviousEndpoint &&
        previous.scoreSeconds - selected.scoreSeconds <
            minimumScoreImprovement.inMilliseconds / 1000) {
      selected = previous;
    }
    return ChaseRendezvousSelection(
      routeResult: selected.result,
      requestedCandidate: selected.request.point,
      roadEndpoint: selected.endpoint,
      targetSeparationMeters: selected.separationMeters,
      scoreSeconds: selected.scoreSeconds,
      accessConfidence: RendezvousAccessConfidence.mappedRoadProfile,
      retainedPreviousEndpoint: selected.request.isPreviousEndpoint,
      candidatesAttempted: attempted,
      candidatesAccepted: accepted.length,
    );
  }

  List<_CandidateRequest> _candidateRequests({
    required ChaseGuidanceDestination destination,
    required route.GeoPoint? previousEndpoint,
  }) {
    final requests = <_CandidateRequest>[];
    if (previousEndpoint != null) {
      final previousAwareness = awareness.GeoPoint(
        latitude: previousEndpoint.latitude,
        longitude: previousEndpoint.longitude,
      );
      if (GeoCalculations.distanceMeters(
            previousAwareness,
            destination.point,
          ) <=
          destination.maximumRoadSeparationMeters) {
        requests.add(
          _CandidateRequest(
            point: previousEndpoint,
            order: 0,
            isPreviousEndpoint: true,
          ),
        );
      }
    }

    final maximumRadius = math.min(
      maximumCandidateRadiusMeters,
      destination.maximumRoadSeparationMeters * 0.65,
    );
    final radius = math
        .max(
          minimumCandidateRadiusMeters,
          math.min(
            maximumRadius,
            math.max(
              destination.uncertaintyRadiusMeters,
              minimumCandidateRadiusMeters,
            ),
          ),
        )
        .toDouble();
    final firstBearing = destination.preferredBearingDegrees ?? 0;
    for (final (index, offset) in const [0.0, 90.0, 180.0, 270.0].indexed) {
      final point = _offset(
        destination.point,
        bearingDegrees: firstBearing + offset,
        distanceMeters: radius,
      );
      final candidate = route.GeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (requests.any(
        (existing) => _routeDistanceMeters(existing.point, candidate) < 30,
      )) {
        continue;
      }
      requests.add(
        _CandidateRequest(
          point: candidate,
          order: index + 1,
          isPreviousEndpoint: false,
        ),
      );
    }
    return List.unmodifiable(requests);
  }

  static awareness.GeoPoint _offset(
    awareness.GeoPoint point, {
    required double bearingDegrees,
    required double distanceMeters,
  }) {
    final angularDistance = distanceMeters / GeoCalculations.earthRadiusMeters;
    final bearing = bearingDegrees * math.pi / 180;
    final latitude = point.latitude * math.pi / 180;
    final longitude = point.longitude * math.pi / 180;
    final destinationLatitude = math.asin(
      math.sin(latitude) * math.cos(angularDistance) +
          math.cos(latitude) * math.sin(angularDistance) * math.cos(bearing),
    );
    final destinationLongitude =
        longitude +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(latitude),
          math.cos(angularDistance) -
              math.sin(latitude) * math.sin(destinationLatitude),
        );
    return awareness.GeoPoint(
      latitude: destinationLatitude * 180 / math.pi,
      longitude: ((destinationLongitude * 180 / math.pi + 540) % 360) - 180,
    );
  }

  static double _routeDistanceMeters(
    route.GeoPoint first,
    route.GeoPoint second,
  ) => GeoCalculations.distanceMeters(
    awareness.GeoPoint(latitude: first.latitude, longitude: first.longitude),
    awareness.GeoPoint(latitude: second.latitude, longitude: second.longitude),
  );
}

class _CandidateRequest {
  const _CandidateRequest({
    required this.point,
    required this.order,
    required this.isPreviousEndpoint,
  });

  final route.GeoPoint point;
  final int order;
  final bool isPreviousEndpoint;
}

class _ScoredCandidate {
  const _ScoredCandidate({
    required this.request,
    required this.result,
    required this.endpoint,
    required this.separationMeters,
    required this.scoreSeconds,
  });

  final _CandidateRequest request;
  final RoadRouteResult result;
  final route.GeoPoint endpoint;
  final double separationMeters;
  final double scoreSeconds;
}
