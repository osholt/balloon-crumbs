import '../domain/crew_room.dart';
import '../domain/crew_room_store.dart';

class InMemoryCrewRoomStore implements CrewRoomStore {
  final Map<String, CrewRoomMembership> _rooms = {};

  @override
  Future<List<CrewRoomMembership>> loadAll() async => List.unmodifiable(
    _rooms.values.toList()..sort((a, b) => a.alias.compareTo(b.alias)),
  );

  @override
  Future<void> upsert(CrewRoomMembership membership) async {
    _rooms[membership.roomId] = membership;
  }

  @override
  Future<void> delete(String roomId) async {
    _rooms.remove(roomId);
  }
}
