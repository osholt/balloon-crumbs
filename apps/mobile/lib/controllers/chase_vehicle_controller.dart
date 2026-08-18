import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chase_vehicle.dart';

/// Remembers the crew's own vehicle across flights.
///
/// Deliberately a stored device preference rather than a question at the start
/// of each flight. The same Land Rover tows the same trailer next weekend, and
/// the person who would have to answer is about to start driving — a form
/// between them and a launch is a form that gets dismissed, which would leave
/// the height blank exactly when the crew believed they had set it.
///
/// Stored as JSON under one key so [ChaseVehicle]'s own degrading parse handles
/// anything unexpected, and so adding a dimension later does not need a
/// migration or a second key.
class ChaseVehicleController extends ChangeNotifier {
  ChaseVehicleController._(this._preferences, this._vehicle);

  static const preferenceKey = 'chase-vehicle-v1';

  final SharedPreferences? _preferences;
  ChaseVehicle _vehicle;

  ChaseVehicle get vehicle => _vehicle;

  static Future<ChaseVehicleController> load() async {
    final preferences = await SharedPreferences.getInstance();
    return ChaseVehicleController._(
      preferences,
      _read(preferences.getString(preferenceKey)),
    );
  }

  @visibleForTesting
  factory ChaseVehicleController.memory({
    ChaseVehicle vehicle = ChaseVehicle.unspecified,
  }) => ChaseVehicleController._(null, vehicle);

  Future<void> set(ChaseVehicle vehicle) async {
    if (_vehicle == vehicle) return;
    _vehicle = vehicle;
    // Nothing specified is stored as nothing at all, not as an empty object, so
    // "never told us" and "told us and then cleared it" read back the same. They
    // mean the same thing and must not diverge.
    if (vehicle.isSpecified) {
      await _preferences?.setString(
        preferenceKey,
        jsonEncode(vehicle.toJson()),
      );
    } else {
      await _preferences?.remove(preferenceKey);
    }
    notifyListeners();
  }

  /// A stored vehicle that cannot be read degrades to unspecified rather than
  /// throwing. The cost of that is a crew re-entering four numbers; the cost of
  /// throwing is an app that will not open.
  static ChaseVehicle _read(String? stored) {
    if (stored == null || stored.isEmpty) return ChaseVehicle.unspecified;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return ChaseVehicle.unspecified;
      return ChaseVehicle.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      return ChaseVehicle.unspecified;
    }
  }
}
