import 'package:flutter/material.dart';

import '../../domain/imported_route.dart' as route_domain;
import '../../domain/land_access_note.dart';
import '../../services/rider_trail_recorder.dart';
import 'ride_map_feature.dart';

class LandAccessNoteMapProjection {
  const LandAccessNoteMapProjection({
    this.markers = const [],
    this.traces = const [],
  });

  final List<MapOverlayMarker> markers;
  final List<MapOverlayTrace> traces;
}

/// Converts private notes to deliberately sparse map content.
///
/// Contact names, phone numbers, recorder identity and free-text notes never
/// reach marker labels. The management screen is the explicit place to reveal
/// those values; a recovery map may be visible to anyone in the vehicle.
LandAccessNoteMapProjection projectLandAccessNotes(
  Iterable<LandAccessNote> notes, {
  required DateTime now,
}) {
  final active = notes
      .where((note) => !note.isExpiredAt(now))
      .toList(growable: false);
  return LandAccessNoteMapProjection(
    markers: List.unmodifiable([
      for (final note in active)
        MapOverlayMarker(
          id: 'private-land-access-${note.id}',
          point: route_domain.GeoPoint(
            latitude: note.geometry.anchor.latitude,
            longitude: note.geometry.anchor.longitude,
          ),
          label: 'Private access · ${landAccessOutcomeLabel(note.outcome)}',
          icon: note.geometry.kind == LandAccessGeometryKind.point
              ? Icons.place_outlined
              : Icons.polyline_outlined,
          color: landAccessOutcomeColor(note.outcome),
        ),
    ]),
    traces: List.unmodifiable([
      for (final note in active)
        if (note.geometry.kind == LandAccessGeometryKind.polygon)
          MapOverlayTrace(
            id: 'private-land-access-outline-${note.id}',
            label: 'Private indicative access outline',
            kind: RiderTrailKind.operationalBoundary,
            color: landAccessOutcomeColor(note.outcome),
            points: [
              for (final point in note.geometry.points)
                route_domain.GeoPoint(
                  latitude: point.latitude,
                  longitude: point.longitude,
                ),
              route_domain.GeoPoint(
                latitude: note.geometry.points.first.latitude,
                longitude: note.geometry.points.first.longitude,
              ),
            ],
          ),
    ]),
  );
}

String landAccessOutcomeLabel(LandAccessOutcome outcome) => switch (outcome) {
  LandAccessOutcome.unknown => 'no access outcome recorded',
  LandAccessOutcome.askFirst => 'ask before vehicle access',
  LandAccessOutcome.permissionConfirmed => 'permission was confirmed',
  LandAccessOutcome.accessDeclined => 'vehicle access was declined',
};

Color landAccessOutcomeColor(LandAccessOutcome outcome) => switch (outcome) {
  LandAccessOutcome.unknown => const Color(0xFF9EABB9),
  LandAccessOutcome.askFirst => const Color(0xFFFFC857),
  LandAccessOutcome.permissionConfirmed => const Color(0xFF72D5A4),
  LandAccessOutcome.accessDeclined => const Color(0xFFFF8A80),
};
