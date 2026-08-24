import 'dart:math' as math;

import '../domain/rider_location.dart';

enum BalloonTelemetryRejectionReason {
  impossibleGroundSpeed,
  impossibleVerticalSpeed,
}

class BalloonTelemetryPlausibilityDecision {
  const BalloonTelemetryPlausibilityDecision.accepted()
    : rejectionReason = null,
      observedRate = null;

  const BalloonTelemetryPlausibilityDecision.rejected(
    this.rejectionReason,
    this.observedRate,
  );

  final BalloonTelemetryRejectionReason? rejectionReason;
  final double? observedRate;

  bool get accepted => rejectionReason == null;
}

/// Rejects only physically impossible jumps from the measured balloon trail.
///
/// The limits are deliberately generous and are not operating limits. They are
/// an integrity backstop for a GNSS teleport: 60 m/s across the ground and
/// 12 m/s vertically. Reported horizontal/vertical accuracy is added to the
/// permitted displacement, missing altitude is accepted as unknown, and a gap
/// over two minutes starts a new honest trail segment instead of guessing what
/// happened while fixes were absent.
class BalloonTelemetryPlausibilityPolicy {
  const BalloonTelemetryPlausibilityPolicy({
    this.maximumGroundSpeedMetersPerSecond = 60,
    this.maximumVerticalSpeedMetersPerSecond = 12,
    this.maximumComparableGap = const Duration(minutes: 2),
  });

  final double maximumGroundSpeedMetersPerSecond;
  final double maximumVerticalSpeedMetersPerSecond;
  final Duration maximumComparableGap;

  BalloonTelemetryPlausibilityDecision assess({
    required LocationSample previous,
    required LocationSample candidate,
  }) {
    final elapsed = candidate.recordedAt.difference(previous.recordedAt);
    if (elapsed <= Duration.zero || elapsed > maximumComparableGap) {
      return const BalloonTelemetryPlausibilityDecision.accepted();
    }
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final distance = _distanceMeters(previous, candidate);
    final horizontalAllowance =
        maximumGroundSpeedMetersPerSecond * seconds +
        previous.accuracyMeters +
        candidate.accuracyMeters;
    if (distance > horizontalAllowance) {
      return BalloonTelemetryPlausibilityDecision.rejected(
        BalloonTelemetryRejectionReason.impossibleGroundSpeed,
        distance / seconds,
      );
    }

    final previousAltitude = previous.altitudeMeters;
    final candidateAltitude = candidate.altitudeMeters;
    final comparableAltitude =
        previousAltitude != null &&
        candidateAltitude != null &&
        previous.altitudeDatum == candidate.altitudeDatum;
    if (comparableAltitude) {
      final verticalDistance = (candidateAltitude - previousAltitude).abs();
      final verticalAllowance =
          maximumVerticalSpeedMetersPerSecond * seconds +
          (previous.altitudeAccuracyMeters ?? 0) +
          (candidate.altitudeAccuracyMeters ?? 0);
      if (verticalDistance > verticalAllowance) {
        return BalloonTelemetryPlausibilityDecision.rejected(
          BalloonTelemetryRejectionReason.impossibleVerticalSpeed,
          verticalDistance / seconds,
        );
      }
    }

    final reportedVerticalSpeed = candidate.verticalSpeedMetersPerSecond?.abs();
    if (reportedVerticalSpeed != null &&
        reportedVerticalSpeed > maximumVerticalSpeedMetersPerSecond) {
      return BalloonTelemetryPlausibilityDecision.rejected(
        BalloonTelemetryRejectionReason.impossibleVerticalSpeed,
        reportedVerticalSpeed,
      );
    }
    return const BalloonTelemetryPlausibilityDecision.accepted();
  }

  static double _distanceMeters(LocationSample first, LocationSample second) {
    const earthRadiusMeters = 6371008.8;
    double radians(double degrees) => degrees * math.pi / 180;
    final lat1 = radians(first.position.latitude);
    final lat2 = radians(second.position.latitude);
    final deltaLat = lat2 - lat1;
    final deltaLon = radians(
      second.position.longitude - first.position.longitude,
    );
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final bounded = a.clamp(0.0, 1.0);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(bounded), math.sqrt(1 - bounded));
  }
}
