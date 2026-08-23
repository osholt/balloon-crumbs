import 'package:shared_preferences/shared_preferences.dart';

import '../domain/map_orientation.dart';

enum MapOrientationScope { phoneBalloon, phoneChase, carPlay }

class MapOrientationPreferences {
  const MapOrientationPreferences(this.preferences);

  final SharedPreferences preferences;

  static const _prefix = 'map_orientation';

  MapOrientationMode read(
    MapOrientationScope scope, {
    required MapOrientationMode fallback,
  }) {
    final stored = preferences.getString(_key(scope));
    return MapOrientationMode.values
            .where((mode) => mode.name == stored)
            .firstOrNull ??
        fallback;
  }

  Future<void> write(MapOrientationScope scope, MapOrientationMode mode) =>
      preferences.setString(_key(scope), mode.name);

  static String _key(MapOrientationScope scope) => '$_prefix:${scope.name}';
}
