import 'package:balloon_crumbs/domain/map_orientation.dart';
import 'package:balloon_crumbs/services/map_orientation_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'phone balloon, phone chase and CarPlay orientations are independent',
    () async {
      SharedPreferences.setMockInitialValues(const {});
      final preferences = MapOrientationPreferences(
        await SharedPreferences.getInstance(),
      );

      expect(
        preferences.read(
          MapOrientationScope.phoneBalloon,
          fallback: MapOrientationMode.northUp,
        ),
        MapOrientationMode.northUp,
      );
      await preferences.write(
        MapOrientationScope.phoneChase,
        MapOrientationMode.northUp,
      );
      await preferences.write(
        MapOrientationScope.carPlay,
        MapOrientationMode.directionUp,
      );

      expect(
        preferences.read(
          MapOrientationScope.phoneChase,
          fallback: MapOrientationMode.directionUp,
        ),
        MapOrientationMode.northUp,
      );
      expect(
        preferences.read(
          MapOrientationScope.phoneBalloon,
          fallback: MapOrientationMode.directionUp,
        ),
        MapOrientationMode.directionUp,
      );
      expect(
        preferences.read(
          MapOrientationScope.carPlay,
          fallback: MapOrientationMode.northUp,
        ),
        MapOrientationMode.directionUp,
      );
    },
  );
}
