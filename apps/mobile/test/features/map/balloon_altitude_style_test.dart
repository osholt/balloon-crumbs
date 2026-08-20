import 'package:balloon_crumbs/domain/imported_route.dart';
import 'package:balloon_crumbs/features/map/balloon_altitude_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('colours each leg from the mean of two known metric altitudes', () {
    final segments = BalloonAltitudeStyle.segments(const [
      GeoPoint(latitude: 51, longitude: -2, elevationMeters: 50),
      GeoPoint(latitude: 51.01, longitude: -2, elevationMeters: 250),
      GeoPoint(latitude: 51.02, longitude: -2, elevationMeters: 950),
    ]);

    expect(segments, hasLength(2));
    expect(segments.first.altitudeMeters, 150);
    expect(segments.first.color, BalloonAltitudeStyle.bands[1].color);
    expect(segments.last.altitudeMeters, 600);
    expect(segments.last.color, BalloonAltitudeStyle.bands[3].color);
  });

  test('does not infer altitude when either endpoint is unknown', () {
    final segments = BalloonAltitudeStyle.segments(const [
      GeoPoint(latitude: 51, longitude: -2, elevationMeters: 100),
      GeoPoint(latitude: 51.01, longitude: -2),
    ]);

    expect(segments.single.hasAltitude, isFalse);
    expect(segments.single.color, BalloonAltitudeStyle.unknownColor);
  });
}
