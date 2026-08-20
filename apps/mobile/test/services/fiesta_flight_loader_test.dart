import 'package:balloon_crumbs/services/fiesta_flight_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled Fiesta assets, checked as shipped rather than as generated.
///
/// The generator is a Python script that is not run in CI, so these assert the
/// committed assets are the ones the app expects. A regenerated flight that
/// changed shape would fail here rather than in a demo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const loader = BundledFiestaFlightLoader();

  test(
    'the flight is the measured 8 August ascent from Ashton Court',
    () async {
      final flight = await loader.load();
      expect(flight.launch.latitude, closeTo(51.4459, 0.001));
      expect(flight.launch.longitude, closeTo(-2.6413, 0.001));
      expect(flight.source, contains('Open-Meteo'));

      // The wind layers are the point of the scenario: a hundred degrees of
      // directional split between 173 m and 832 m.
      final low = flight.windLayers.firstWhere(
        (layer) => layer.heightMetres == 173,
      );
      final high = flight.windLayers.firstWhere(
        (layer) => layer.heightMetres == 832,
      );
      expect(low.towardDegrees, closeTo(235, 1));
      expect(high.towardDegrees, closeTo(339, 1));
    },
  );

  test('it lands on the moor at West Town, and takes about an hour', () async {
    final flight = await loader.load();
    expect(flight.landing.latitude, closeTo(51.4128, 0.005));
    expect(flight.landing.longitude, closeTo(-2.7585, 0.005));
    expect(flight.duration.inMinutes, inInclusiveRange(45, 60));
    expect(flight.peakHeightMetres, inInclusiveRange(300, 500));
    // Starts and finishes on the ground. A flight that begins at altitude is a
    // generator bug, and one that ends there never landed.
    expect(flight.samples.first.heightMetres, 0);
    expect(flight.samples.last.heightMetres, 0);
  });

  test('the chase route carries turn manoeuvres', () async {
    // Without these the chase falls back to "follow the line on the map",
    // which is what the route this replaced already did better.
    final route = await loader.loadChaseRoute();
    expect(route.maneuvers, isNotEmpty);
    expect(route.paths, isNotEmpty);
  });
}
