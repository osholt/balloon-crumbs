import 'package:balloon_crumbs/controllers/chase_vehicle_controller.dart';
import 'package:balloon_crumbs/domain/chase_vehicle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install has no vehicle and claims none', () async {
    final controller = await ChaseVehicleController.load();
    expect(controller.vehicle, ChaseVehicle.unspecified);
  });

  test('a saved vehicle survives a restart', () async {
    // The whole reason this is stored rather than asked each flight: the crew
    // tows the same trailer next weekend, and the person who would answer is
    // about to start driving.
    final controller = await ChaseVehicleController.load();
    await controller.set(
      const ChaseVehicle(
        heightMetres: 3.2,
        grossWeightTonnes: 3.5,
        towing: true,
      ),
    );

    final restarted = await ChaseVehicleController.load();
    expect(restarted.vehicle.heightMetres, 3.2);
    expect(restarted.vehicle.grossWeightTonnes, 3.5);
    expect(restarted.vehicle.towing, isTrue);
  });

  test(
    'clearing a vehicle removes the key, rather than storing an empty one',
    () async {
      // "Never told us" and "told us and then cleared it" mean the same thing, so
      // they must read back the same.
      final controller = await ChaseVehicleController.load();
      await controller.set(const ChaseVehicle(heightMetres: 3.2));
      await controller.set(ChaseVehicle.unspecified);

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey(ChaseVehicleController.preferenceKey),
        isFalse,
      );
      expect(
        (await ChaseVehicleController.load()).vehicle,
        ChaseVehicle.unspecified,
      );
    },
  );

  test('listeners hear a change, and are not woken for a no-op', () async {
    final controller = await ChaseVehicleController.load();
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.set(const ChaseVehicle(heightMetres: 3.2));
    expect(notifications, 1);
    await controller.set(const ChaseVehicle(heightMetres: 3.2));
    expect(notifications, 1, reason: 'the same vehicle is not a change');
  });

  test(
    'unreadable stored data degrades to unspecified, and does not throw',
    () async {
      // The cost of degrading is a crew re-entering four numbers. The cost of
      // throwing is an app that will not open at a launch site.
      for (final corrupt in ['not json at all', '[]', '{', '3']) {
        SharedPreferences.setMockInitialValues({
          ChaseVehicleController.preferenceKey: corrupt,
        });
        expect(
          (await ChaseVehicleController.load()).vehicle,
          ChaseVehicle.unspecified,
          reason: corrupt,
        );
      }
    },
  );

  test('a stored vehicle with a nonsense dimension keeps the rest', () async {
    SharedPreferences.setMockInitialValues({
      ChaseVehicleController.preferenceKey:
          '{"heightMetres":99,"grossWeightTonnes":3.5,"towing":true}',
    });
    final controller = await ChaseVehicleController.load();
    expect(controller.vehicle.heightMetres, isNull);
    expect(controller.vehicle.grossWeightTonnes, 3.5);
    expect(controller.vehicle.towing, isTrue);
  });
}
