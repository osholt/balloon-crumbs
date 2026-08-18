import 'package:balloon_crumbs/domain/chase_vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('an empty field means "not told", never "no restriction"', () {
    test('nothing entered claims nothing and routes as before', () {
      const vehicle = ChaseVehicle.unspecified;
      expect(vehicle.hasDimensions, isFalse);
      expect(vehicle.isSpecified, isFalse);
      expect(vehicle.requiresTruckCosting, isFalse);
      expect(vehicle.appliedNotes, isEmpty);
      expect(vehicle.toJson(), isEmpty);
    });

    test('a single dimension is enough to route on', () {
      // A crew who knows only their height should get bridges avoided for it.
      const vehicle = ChaseVehicle(heightMetres: 3.2);
      expect(vehicle.hasDimensions, isTrue);
      expect(vehicle.requiresTruckCosting, isTrue);
    });

    test('towing alone is specified, but is not a dimension', () {
      const vehicle = ChaseVehicle(towing: true);
      expect(vehicle.isSpecified, isTrue);
      expect(vehicle.hasDimensions, isFalse);
      // The distinction that keeps Valhalla's lorry defaults out: 4.11 m and
      // 21.77 t applied to a vehicle nobody measured would refuse most of the
      // roads to a launch site.
      expect(vehicle.requiresTruckCosting, isFalse);
    });
  });

  group('reading a stored vehicle', () {
    test('a plausible number is kept, whether typed or stored', () {
      expect(
        ChaseVehicle.fromJson(const {'heightMetres': 3.2}).heightMetres,
        3.2,
      );
      // The editor hands over what the crew typed, so strings must parse.
      expect(
        ChaseVehicle.fromJson(const {'heightMetres': '3.2'}).heightMetres,
        3.2,
      );
      expect(
        ChaseVehicle.fromJson(const {'heightMetres': ' 3.2 '}).heightMetres,
        3.2,
      );
    });

    test('an implausible number degrades to not-told, not to a clamp', () {
      // Clamping would invent a restriction the crew never entered, and a
      // restriction is the thing that reroutes them. Zero and negatives are not
      // small vehicles: they are empty or broken fields.
      for (final value in [0, -3, 'abc', '', null, double.nan, true]) {
        expect(
          ChaseVehicle.fromJson({'heightMetres': value}).heightMetres,
          isNull,
          reason: '$value',
        );
      }
    });

    test('each dimension has its own plausible ceiling', () {
      // 8 m is not a chase vehicle, it is a typo for 1.8.
      expect(
        ChaseVehicle.fromJson(const {'heightMetres': 8}).heightMetres,
        isNull,
      );
      expect(ChaseVehicle.fromJson(const {'heightMetres': 4}).heightMetres, 4);
      expect(
        ChaseVehicle.fromJson(const {'widthMetres': 6}).widthMetres,
        isNull,
      );
      expect(
        ChaseVehicle.fromJson(const {'lengthMetres': 40}).lengthMetres,
        isNull,
      );
      expect(
        ChaseVehicle.fromJson(const {'lengthMetres': 12}).lengthMetres,
        12,
      );
      expect(
        ChaseVehicle.fromJson(const {
          'grossWeightTonnes': 60,
        }).grossWeightTonnes,
        isNull,
      );
      expect(
        ChaseVehicle.fromJson(const {
          'grossWeightTonnes': 3.5,
        }).grossWeightTonnes,
        3.5,
      );
    });

    test('a vehicle round-trips through JSON', () {
      const vehicle = ChaseVehicle(
        heightMetres: 3.2,
        widthMetres: 2.1,
        lengthMetres: 11,
        grossWeightTonnes: 3.5,
        towing: true,
      );
      expect(ChaseVehicle.fromJson(vehicle.toJson()), vehicle);
    });

    test('unset dimensions are absent from the JSON, not null entries', () {
      expect(const ChaseVehicle(heightMetres: 3).toJson(), {
        'heightMetres': 3.0,
      });
    });
  });

  group('what gets sent to the router', () {
    test('an unentered dimension restricts nothing', () {
      // Understating is the safe direction: it applies no restriction on that
      // axis, which is the answer the crew got before they told us anything.
      // Omitting the key instead would inherit Valhalla's lorry defaults.
      final dimensions = const ChaseVehicle(
        grossWeightTonnes: 3.5,
      ).valhallaTruckDimensions();
      expect(dimensions['weight'], 3.5);
      expect(dimensions['height'], 2);
      expect(dimensions['width'], 2);
      expect(dimensions['length'], 5);
    });

    test('hazmat is never asserted', () {
      // A chase vehicle carries propane cylinders, and propane is a dangerous
      // good — but hazmat routing is a legal regime about placarded loads that
      // the crew has not declared, and the app must not declare it for them.
      expect(
        const ChaseVehicle(
          heightMetres: 3,
          towing: true,
        ).valhallaTruckDimensions()['hazmat'],
        isFalse,
      );
    });
  });

  group('what the crew reads back', () {
    test('the notes name every number entered, and nothing else', () {
      expect(
        const ChaseVehicle(
          heightMetres: 3.2,
          grossWeightTonnes: 3.5,
          towing: true,
        ).appliedNotes,
        ['towing', '3.2 m high', '3.5 t'],
      );
    });

    test('whole numbers read as whole numbers', () {
      expect(
        const ChaseVehicle(heightMetres: 3, lengthMetres: 11).appliedNotes,
        ['3 m high', '11 m long'],
      );
    });
  });

  test('clearing a dimension is distinguishable from not changing it', () {
    const vehicle = ChaseVehicle(heightMetres: 3.2, towing: true);
    expect(vehicle.copyWith(towing: false).heightMetres, 3.2);
    expect(vehicle.copyWith(clearHeight: true).heightMetres, isNull);
    expect(vehicle.copyWith(clearHeight: true).towing, isTrue);
  });
}
