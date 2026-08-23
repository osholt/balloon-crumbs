import 'crew_room.dart';

abstract interface class CrewRoomStore {
  Future<List<CrewRoomMembership>> loadAll();

  Future<void> upsert(CrewRoomMembership membership);

  Future<void> delete(String roomId);
}
