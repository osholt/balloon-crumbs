import 'package:balloon_crumbs/domain/craft.dart';
import 'package:balloon_crumbs/domain/flight_role.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP3. The craft model, and the constraints that keep multiple balloons
/// (backlog items 22 and 23) from needing the data model re-cut.
void main() {
  group('a flight holds a set of crafts, not a balloon slot', () {
    test('the balloon is a lookup over crafts, so several are representable', () {
      // Not being built: one balloon is a cardinality the UI enforces. But the
      // shape has to allow the question to be asked, or adding a second balloon
      // later means re-cutting every read model.
      const crafts = [
        Craft(id: 'b1', kind: CraftKind.balloon, label: 'Balloon'),
        Craft(id: 'v1', kind: CraftKind.vehicle, label: 'Land Rover'),
        Craft(id: 'v2', kind: CraftKind.vehicle, label: 'Vehicle 2'),
      ];

      final balloons = crafts.where((c) => c.isBalloon);
      expect(balloons.map((c) => c.id), ['b1']);
      expect(crafts.where((c) => !c.isBalloon), hasLength(2));
    });

    test('icon styles are properties of crafts and must match their kind', () {
      const vehicle = Craft(
        id: 'v1',
        kind: CraftKind.vehicle,
        label: 'Recovery van',
        iconStyle: CraftIconStyle.van,
      );
      expect(vehicle.iconStyle, CraftIconStyle.van);
      expect(
        () => Craft(
          id: 'b1',
          kind: CraftKind.balloon,
          label: 'Balloon',
          iconStyle: CraftIconStyle.van,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test(
      'a chase assignment is its own fact, reassignable without a schema change',
      () {
        const vehicle = Craft(
          id: 'v1',
          kind: CraftKind.vehicle,
          label: 'Land Rover',
          chasing: 'b1',
        );

        // With one balloon this is implicit. With several, reassigning a vehicle
        // mid-flight is just a new value rather than a new data model.
        final switched = vehicle.copyWith(chasing: 'b2');
        expect(switched.chasing, 'b2');
        expect(vehicle.chasing, 'b1', reason: 'crafts are immutable');

        expect(vehicle.copyWith(clearChasing: true).chasing, isNull);
      },
    );

    test('only a vehicle chases, and nothing chases itself', () {
      expect(
        () => Craft(
          id: 'b1',
          kind: CraftKind.balloon,
          label: 'Balloon',
          chasing: 'v1',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Craft(
          id: 'v1',
          kind: CraftKind.vehicle,
          label: 'Vehicle',
          chasing: 'v1',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('the wire form', () {
    test('round-trips a vehicle with its assignment', () {
      const vehicle = Craft(
        id: 'v1',
        kind: CraftKind.vehicle,
        label: 'Land Rover',
        chasing: 'b1',
      );

      expect(Craft.fromJson(vehicle.toJson()), vehicle);
    });

    test('a balloon writes no assignment field at all', () {
      const balloon = Craft(
        id: 'b1',
        kind: CraftKind.balloon,
        label: 'Balloon',
      );

      expect(balloon.toJson().containsKey('chasing'), isFalse);
      expect(Craft.fromJson(balloon.toJson()), balloon);
    });

    test('a mismatched or absent style degrades to the kind default', () {
      final balloon = Craft.fromJson({
        'id': 'b1',
        'kind': 'balloon',
        'label': 'Balloon',
        'craftStyle': 'van',
      });
      final vehicle = Craft.fromJson({
        'id': 'v1',
        'kind': 'vehicle',
        'label': 'Vehicle',
      });

      expect(balloon.iconStyle, CraftIconStyle.balloon);
      expect(vehicle.iconStyle, craftIconStyleDefault);
    });

    test('an assignment arriving on a balloon is dropped, not fatal', () {
      // A malformed peer payload should degrade rather than take out a whole
      // flight's read model on a constructor assertion.
      final craft = Craft.fromJson({
        'id': 'b1',
        'kind': 'balloon',
        'label': 'Balloon',
        'chasing': 'v1',
      });

      expect(craft.isBalloon, isTrue);
      expect(craft.chasing, isNull);
    });

    test('an unknown craft kind degrades to vehicle, never to balloon', () {
      // Treating an unknown craft as a balloon would put a second aircraft on
      // the map and could hand guidance a target that is not flying.
      expect(craftKindFromName('airship'), CraftKind.vehicle);
      expect(craftKindFromName(null), CraftKind.vehicle);
      expect(craftKindFromName('balloon'), CraftKind.balloon);
    });
  });

  group('flight roles separate the job from the craft', () {
    test('aboard, chasing, and neither are distinguishable', () {
      expect(FlightRole.pilot.isAboardBalloon, isTrue);
      expect(FlightRole.balloonCrew.isAboardBalloon, isTrue);
      expect(FlightRole.chaseDriver.isAboardBalloon, isFalse);

      expect(FlightRole.chaseDriver.isChasing, isTrue);
      expect(FlightRole.chaseCrew.isChasing, isTrue);
      expect(FlightRole.observer.isChasing, isFalse);
    });

    test('only the driver sees road furniture', () {
      // Speed limits, cameras and enforcement alerts are kept for the chase
      // driver and must not reach the basket: a camera warning is attention
      // taken from flying.
      for (final role in FlightRole.values) {
        expect(
          role.seesRoadFurniture,
          role == FlightRole.chaseDriver,
          reason:
              '${role.name} should${role == FlightRole.chaseDriver ? '' : ' not'} see road furniture',
        );
      }
    });

    test('only the pilot holds flight authority', () {
      for (final role in FlightRole.values) {
        expect(role.hasFlightAuthority, role == FlightRole.pilot);
      }
    });

    test('an unknown role degrades to the least privileged one', () {
      // Never silently acquire authority or become trusted to report a balloon.
      expect(flightRoleFromName('groundHandler'), FlightRole.observer);
      expect(flightRoleFromName(null), FlightRole.observer);
      expect(flightRoleFromName('pilot'), FlightRole.pilot);
      expect(flightRoleFromName(42), FlightRole.observer);
    });

    test('known role names round-trip', () {
      for (final role in FlightRole.values) {
        expect(flightRoleFromName(role.name), role);
      }
    });
  });
}
