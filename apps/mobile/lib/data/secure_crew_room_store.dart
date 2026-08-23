import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/crew_room.dart';
import '../domain/crew_room_store.dart';

class SecureCrewRoomStore implements CrewRoomStore {
  const SecureCrewRoomStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'balloon_crumbs_crew_rooms_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<List<CrewRoomMembership>> loadAll() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return const [];
    try {
      final value = Map<String, Object?>.from(jsonDecode(encoded) as Map);
      if (value['schemaVersion'] != 1 || value['rooms'] is! List) {
        throw const FormatException('Crew room store is invalid.');
      }
      final memberships = (value['rooms']! as List)
          .map(
            (item) => CrewRoomMembership.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
      if (memberships.length > 50 ||
          memberships.map((room) => room.roomId).toSet().length !=
              memberships.length) {
        throw const FormatException('Crew room store is invalid.');
      }
      return List.unmodifiable(memberships);
    } on Object {
      await _storage.delete(key: _key);
      return const [];
    }
  }

  @override
  Future<void> upsert(CrewRoomMembership membership) async {
    final rooms = [...await loadAll()];
    rooms.removeWhere((room) => room.roomId == membership.roomId);
    rooms.add(membership);
    rooms.sort((a, b) => a.alias.compareTo(b.alias));
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'schemaVersion': 1,
        'rooms': rooms.map((room) => room.toJson()).toList(growable: false),
      }),
    );
  }

  @override
  Future<void> delete(String roomId) async {
    final rooms = [...await loadAll()]
      ..removeWhere((room) => room.roomId == roomId);
    if (rooms.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'schemaVersion': 1,
        'rooms': rooms.map((room) => room.toJson()).toList(growable: false),
      }),
    );
  }
}
