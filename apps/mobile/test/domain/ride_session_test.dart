import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:balloon_crumbs/domain/ride_coordination_mode.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/ride_session.dart';
import 'package:balloon_crumbs/features/map/craft_icon.dart';

void main() {
  final session = RideSession(
    rideId: 'ride',
    rideCode: 'SIM123',
    inviteSecret: 'secret',
    joinToken: 'aTokenWithPlentyOfEntropy',
    localRiderId: 'lead',
    displayName: 'Demo Lead',
    role: RideRole.lead,
    joinedAt: DateTime.utc(2026, 7, 17),
    isSimulation: true,
  );

  test('simulation marker survives session persistence', () {
    expect(RideSession.fromJson(session.toJson()).isSimulation, isTrue);
  });

  test('craft style storage is additive and legacy sessions still restore', () {
    final stored = RideSession(
      rideId: 'craft-style',
      rideCode: 'CRAFT1',
      inviteSecret: 'secret',
      joinToken: 'aTokenWithPlentyOfEntropy',
      localRiderId: 'crew',
      displayName: 'Alex',
      role: RideRole.rider,
      joinedAt: DateTime.utc(2026, 8, 24),
      craftStyle: CraftIconStyle.trailer,
    ).toJson();

    expect(stored[craftStyleWireKey], 'trailer');
    expect(stored[legacyCraftStyleWireKey], 'trailer');
    expect(RideSession.fromJson(stored).craftStyle, CraftIconStyle.trailer);

    final legacy = Map<String, Object?>.from(stored)
      ..remove(craftStyleWireKey)
      ..[legacyCraftStyleWireKey] = 'van';
    expect(RideSession.fromJson(legacy).craftStyle, CraftIconStyle.van);
  });

  test('flight role and craft assignment survive session persistence', () {
    final assigned = RideSession(
      rideId: 'flight',
      rideCode: '123456',
      inviteSecret: 'secret',
      joinToken: 'aTokenWithPlentyOfEntropy',
      localRiderId: 'crew',
      displayName: 'Alex',
      role: RideRole.rider,
      flightRole: FlightRole.chaseDriver,
      localCraftId: 'vehicle-land-rover',
      joinedAt: DateTime.utc(2026, 8, 23),
    );

    final restored = RideSession.fromJson(assigned.toJson());
    expect(restored.flightRole, FlightRole.chaseDriver);
    expect(restored.localCraftId, 'vehicle-land-rover');
    expect(restored.requiresFlightAssignment, isFalse);
  });

  test('legacy sessions restore least-privileged and require assignment', () {
    final legacy = session.toJson()
      ..remove('flightRole')
      ..remove('localCraftId');

    final restored = RideSession.fromJson(legacy);
    expect(restored.flightRole, FlightRole.observer);
    expect(restored.localCraftId, isNull);
    expect(restored.requiresFlightAssignment, isTrue);
  });

  test(
    'simulation rider count persists and legacy sessions use five riders',
    () {
      final configured = RideSession(
        rideId: 'ride',
        rideCode: 'SIM123',
        inviteSecret: 'secret',
        joinToken: 'aTokenWithPlentyOfEntropy',
        localRiderId: 'lead',
        displayName: 'Demo Lead',
        role: RideRole.lead,
        joinedAt: DateTime.utc(2026, 7, 17),
        isSimulation: true,
        simulationRiderCount: 30,
      );
      expect(
        RideSession.fromJson(configured.toJson()).simulationRiderCount,
        30,
      );

      final legacy = session.toJson()..remove('simulationRiderCount');
      expect(
        RideSession.fromJson(legacy).simulationRiderCount,
        RideSession.defaultSimulationRiderCount,
      );
    },
  );

  test('legacy sessions default to live rides', () {
    final json = session.toJson()..remove('isSimulation');
    expect(RideSession.fromJson(json).isSimulation, isFalse);
  });

  test('coordination mode persists and old rides keep drop-off behaviour', () {
    final solo = RideSession(
      rideId: 'ride',
      rideCode: 'SIM123',
      inviteSecret: 'secret',
      joinToken: 'aTokenWithPlentyOfEntropy',
      localRiderId: 'lead',
      displayName: 'Demo Lead',
      role: RideRole.lead,
      joinedAt: DateTime.utc(2026, 7, 17),
      coordinationMode: RideCoordinationMode.solo,
    );
    expect(
      RideSession.fromJson(solo.toJson()).coordinationMode,
      RideCoordinationMode.solo,
    );

    final legacy = solo.toJson()..remove('coordinationMode');
    expect(
      RideSession.fromJson(legacy).coordinationMode,
      RideCoordinationMode.keepTogether,
    );
  });

  test(
    'crew symbol survives session persistence and old sessions use a craft',
    () {
      final custom = RideSession(
        rideId: 'ride',
        rideCode: 'SIM123',
        inviteSecret: 'secret',
        joinToken: 'aTokenWithPlentyOfEntropy',
        localRiderId: 'lead',
        displayName: 'Demo Lead',
        role: RideRole.lead,
        joinedAt: DateTime.utc(2026, 7, 17),
        riderSymbol: const RiderSymbol.initials(),
      );
      expect(
        RideSession.fromJson(custom.toJson()).riderSymbol,
        const RiderSymbol.initials(),
      );

      final legacy = custom.toJson()..remove('riderSymbol');
      expect(RideSession.fromJson(legacy).riderSymbol, riderSymbolDefault);
    },
  );

  test(
    'a session persisted before join tokens existed gets a fresh one instead of crashing',
    () {
      final json = session.toJson()..remove('joinToken');
      final restored = RideSession.fromJson(json);
      expect(restored.joinToken.length, greaterThanOrEqualTo(16));
    },
  );
}
