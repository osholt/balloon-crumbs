import '../domain/craft.dart';
import '../domain/flight_replay.dart';
import '../domain/geo_point.dart';
import '../domain/ride_event.dart';
import '../domain/ride_role.dart';
import '../domain/ride_session.dart';
import '../domain/rider_location.dart';

/// Builds a secret-free, device-local replay timeline from the flight journal.
///
/// Balloon and local-device tracks are retained by default. Independent peer
/// chaser tracks require [includePeerTracks], because another person's location
/// history is a separate privacy decision even when it was visible live.
class FlightReplayArchiver {
  const FlightReplayArchiver();

  FlightReplay create({
    required RideSession session,
    required Iterable<RideEvent> events,
    required DateTime startedAt,
    required DateTime endedAt,
    bool includePeerTracks = false,
  }) {
    final ordered = events.toList()
      ..sort((left, right) {
        final time = left.createdAt.compareTo(right.createdAt);
        return time != 0 ? time : left.id.compareTo(right.id);
      });
    final craftKinds = <String, CraftKind>{};
    final craftLabels = <String, String>{};
    final deviceCraft = <String, String>{};
    final builders = <String, _TrackBuilder>{};
    final wind = <FlightReplayWindContext>[];
    final landingAreas = <FlightReplayLandingArea>[];

    for (final event in ordered) {
      if (event.createdAt.isBefore(startedAt) ||
          event.createdAt.isAfter(endedAt)) {
        continue;
      }
      switch (event.type) {
        case RideEventType.craftRegistered:
          final craftId = event.payload['craftId'];
          final kind = event.payload['kind'];
          final label = event.payload['label'];
          if (craftId is String && kind is String) {
            craftKinds[craftId] =
                CraftKind.values
                    .where((candidate) => candidate.name == kind)
                    .firstOrNull ??
                CraftKind.vehicle;
            if (label is String && label.trim().isNotEmpty) {
              craftLabels[craftId] = label.trim();
            }
          }
        case RideEventType.deviceAttachedToCraft:
          final deviceId = event.payload['deviceId'];
          final craftId = event.payload['craftId'];
          if (deviceId is String && craftId is String) {
            deviceCraft[deviceId] = craftId;
          }
        case RideEventType.riderLocationUpdated:
          final location = _location(event.payload);
          if (location == null) break;
          final craftId = deviceCraft[event.deviceId];
          final isBalloon =
              craftKinds[craftId] == CraftKind.balloon ||
              (craftId == null && location.role == RideRole.lead);
          final isLocal = event.deviceId == session.localRiderId;
          if (!isLocal && !isBalloon && !includePeerTracks) break;
          final key = isBalloon
              ? 'balloon:${craftId ?? event.deviceId}'
              : isLocal
              ? 'local'
              : 'peer:${event.deviceId}';
          final builder = builders.putIfAbsent(
            key,
            () => _TrackBuilder(
              label: isBalloon
                  ? craftLabels[craftId] ?? 'Balloon'
                  : isLocal
                  ? session.displayName
                  : 'Chaser',
              kind: isBalloon
                  ? FlightReplayTrackKind.balloon
                  : isLocal
                  ? FlightReplayTrackKind.localChaser
                  : FlightReplayTrackKind.chaser,
            ),
          );
          builder.samples.add(
            FlightReplaySample(
              position: location.sample.position,
              recordedAt: location.sample.recordedAt,
              speedMetersPerSecond: location.sample.speedMetersPerSecond,
              headingDegrees: location.sample.headingDegrees,
              altitudeMeters: location.sample.altitudeMeters,
              altitudeSource: location.sample.altitudeSource,
              altitudeDatum: location.sample.altitudeDatum,
              verticalSpeedMetersPerSecond:
                  location.sample.verticalSpeedMetersPerSecond,
            ),
          );
        case RideEventType.windContextNoted:
          final context = _windContext(event);
          if (context != null) wind.add(context);
        case RideEventType.landingAreaNoted:
          final area = _landingArea(event);
          if (area != null) landingAreas.add(area);
        case RideEventType.rideCreated:
        case RideEventType.riderJoined:
        case RideEventType.riderLeft:
        case RideEventType.roleChanged:
        case RideEventType.rideStarted:
        case RideEventType.statusMessage:
        case RideEventType.hazardReported:
        case RideEventType.hazardCleared:
        case RideEventType.routeRevisionChunk:
        case RideEventType.routeRevisionPublished:
        case RideEventType.routeCleared:
        case RideEventType.ridePaused:
        case RideEventType.rideResumed:
        case RideEventType.rideEnded:
        case RideEventType.iceInfoShared:
        case RideEventType.iceInfoViewed:
        case RideEventType.riderContactShared:
        case RideEventType.rideReopened:
        case RideEventType.craftPrimaryDeviceNominated:
        case RideEventType.craftChaseAssigned:
          break;
        case RideEventType.operationalBoundaryUpserted:
        case RideEventType.operationalBoundaryRemoved:
          break;
      }
    }

    var balloonIndex = 0;
    var chaserIndex = 0;
    final tracks = <FlightReplayTrack>[];
    for (final builder in builders.values) {
      builder.samples.sort(
        (left, right) => left.recordedAt.compareTo(right.recordedAt),
      );
      final id = switch (builder.kind) {
        FlightReplayTrackKind.balloon => 'balloon-${++balloonIndex}',
        FlightReplayTrackKind.localChaser => 'local-chaser',
        FlightReplayTrackKind.chaser => 'chaser-${++chaserIndex}',
      };
      tracks.add(
        FlightReplayTrack(
          id: id,
          label: builder.kind == FlightReplayTrackKind.chaser
              ? 'Chaser $chaserIndex'
              : builder.label,
          kind: builder.kind,
          samples: List.unmodifiable(builder.samples),
        ),
      );
    }
    tracks.sort((left, right) => left.kind.index.compareTo(right.kind.index));

    return FlightReplay(
      startedAt: startedAt,
      endedAt: endedAt,
      tracks: List.unmodifiable(tracks),
      windContexts: List.unmodifiable(wind),
      landingAreas: List.unmodifiable(landingAreas),
      peerTracksIncluded: includePeerTracks,
    );
  }

  static RiderLocation? _location(Map<String, Object?> payload) {
    final raw = payload['location'];
    if (raw is! Map) return null;
    try {
      return RiderLocation.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      return null;
    }
  }

  static FlightReplayWindContext? _windContext(RideEvent event) {
    final payload = event.payload;
    final validAt = payload['validAt'];
    final source = payload['source'];
    final isForecast = payload['isForecast'];
    final latitude = payload['latitude'];
    final longitude = payload['longitude'];
    final rawVectors = payload['vectors'];
    if (validAt is! String ||
        source is! String ||
        isForecast is! bool ||
        latitude is! num ||
        longitude is! num ||
        rawVectors is! List) {
      return null;
    }
    try {
      return FlightReplayWindContext(
        recordedAt: event.createdAt,
        validAt: DateTime.parse(validAt).toUtc(),
        source: source,
        isForecast: isForecast,
        position: GeoPoint(
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
        ),
        vectors: [
          for (final vector in rawVectors.whereType<Map>())
            FlightReplayWindVector(
              altitudeMetersMsl: (vector['altitudeMetersMsl'] as num)
                  .toDouble(),
              fromDegrees: (vector['fromDegrees'] as num).toDouble(),
              speedKmh: (vector['speedKmh'] as num).toDouble(),
            ),
        ],
      );
    } on Object {
      return null;
    }
  }

  static FlightReplayLandingArea? _landingArea(RideEvent event) {
    final latitude = event.payload['latitude'];
    final longitude = event.payload['longitude'];
    final radius = event.payload['radiusMeters'];
    final label = event.payload['label'];
    if (latitude is! num ||
        longitude is! num ||
        radius is! num ||
        label is! String) {
      return null;
    }
    return FlightReplayLandingArea(
      recordedAt: event.createdAt,
      center: GeoPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
      radiusMeters: radius.toDouble(),
      label: label,
    );
  }
}

class _TrackBuilder {
  _TrackBuilder({required this.label, required this.kind});

  final String label;
  final FlightReplayTrackKind kind;
  final List<FlightReplaySample> samples = [];
}
