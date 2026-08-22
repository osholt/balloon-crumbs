import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/landing_zone.dart';

/// A small, device-local list of recently selected landing areas.
class LandingZoneLibrary {
  const LandingZoneLibrary(this._preferences);

  static const _storageKey = 'recent_landing_zones_v1';
  static const maximumEntries = 8;

  final SharedPreferences _preferences;

  static Future<LandingZoneLibrary> open() async =>
      LandingZoneLibrary(await SharedPreferences.getInstance());

  List<LandingZoneTarget> load() {
    final encoded = _preferences.getString(_storageKey);
    if (encoded == null) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      final results = <LandingZoneTarget>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          results.add(
            LandingZoneTarget.fromJson(Map<String, Object?>.from(item)),
          );
        } on Object {
          // One damaged entry must not hide the usable entries around it.
        }
      }
      return results.take(maximumEntries).toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<List<LandingZoneTarget>> remember(LandingZoneTarget target) async {
    final current = load();
    bool sameArea(LandingZoneTarget candidate) =>
        (candidate.center.latitude - target.center.latitude).abs() < 0.0001 &&
        (candidate.center.longitude - target.center.longitude).abs() < 0.0001;
    final next = [
      target,
      ...current.where((candidate) => !sameArea(candidate)),
    ].take(maximumEntries).toList(growable: false);
    await _preferences.setString(
      _storageKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
    return next;
  }
}
