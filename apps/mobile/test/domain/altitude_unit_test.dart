import 'package:balloon_crumbs/domain/altitude_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metric altitude and vertical rate remain the default presentation', () {
    expect(AltitudeUnit.metres.altitude(300), '300 m');
    expect(AltitudeUnit.metres.accuracy(6), '±6 m');
    expect(AltitudeUnit.metres.verticalRate(1.5), '1.5 m/s');
  });

  test(
    'feet conversion updates altitude accuracy and vertical rate together',
    () {
      expect(AltitudeUnit.feet.altitude(300), '984 ft');
      expect(AltitudeUnit.feet.accuracy(6), '±20 ft');
      expect(AltitudeUnit.feet.verticalRate(1.5), '295 ft/min');
    },
  );
}
