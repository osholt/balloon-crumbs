import 'package:balloon_crumbs/domain/route_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('route styles', () {
    test('the twisty ladder is gone, and two chase options remain', () {
      // The inherited ladder bought bends with time: +25%, +50%, +75%. A crew
      // trying to be under a balloon when it lands has no use for any of it.
      expect(RouteStyle.values.map((style) => style.apiValue), [
        'direct',
        'major-roads',
      ]);
    });

    test('detour tolerance belongs to the trailer, not to the style', () {
      // The bug this replaced: tolerance hung off the style, the default style
      // allowed 0%, so a crew who ticked "towing" got a preference that could
      // never once change their route. Nothing failed — the field was still
      // there and still being read.
      expect(RoutePreferences.towingDetourLimit, 1.15);
    });

    test('every retired motorcycle style degrades to direct', () {
      // The trap in this change. These four are sitting in stored routes, and a
      // route stored as `twisty` asked for a 50% detour in exchange for
      // corners. There is no honest translation of that into a chase
      // preference, so none is invented — but it must not throw or read as
      // null either, because then the route will not open.
      for (final retired in ['quickest', 'balanced', 'twisty', 'very-twisty']) {
        expect(
          RouteStyle.fromApiValue(retired),
          RouteStyle.direct,
          reason: retired,
        );
        expect(
          RoutePreferences.fromJson({'style': retired}).style,
          RouteStyle.direct,
          reason: retired,
        );
      }
    });

    test('a style this build has never heard of also degrades to direct', () {
      expect(RouteStyle.fromApiValue('scenic'), isNull);
      expect(RouteStyle.fromApiValue(null), isNull);
      expect(
        RoutePreferences.fromJson(const {'style': 'scenic'}).style,
        RouteStyle.direct,
      );
      expect(RoutePreferences.fromJson(const {}).style, RouteStyle.direct);
    });

    test('preferring major roads shuts living streets out', () {
      // Where a long vehicle gets stuck and where children play.
      expect(RouteStyle.majorRoads.livingStreetPreference, 0);
      expect(RouteStyle.direct.livingStreetPreference, 0.5);
    });
  });

  group('byway default', () {
    test('unsurfaced byways are avoided unless the crew says otherwise', () {
      expect(
        RoutePreferences.defaults.bywaySurface,
        BywaySurfacePreference.avoidUnsurfaced,
      );
      expect(RoutePreferences.defaults.bywaySurface.avoidsUnsurfaced, isTrue);
    });

    test(
      'a route with no recorded preference gets the road-biased default',
      () {
        expect(
          RoutePreferences.fromJson(const {}).bywaySurface,
          BywaySurfacePreference.avoidUnsurfaced,
        );
        expect(
          RoutePreferences.fromJson(const {
            'bywaySurface': 'nonsense',
          }).bywaySurface,
          BywaySurfacePreference.avoidUnsurfaced,
        );
      },
    );
  });

  group('which Valhalla costing plans the route', () {
    test('nothing entered routes as a car, exactly as before', () {
      expect(RoutePreferences.defaults.valhallaCosting, 'auto');
      expect(RoutePreferences.defaults.vehicle.requiresTruckCosting, isFalse);
      expect(
        RoutePreferences.defaults.valhallaCostingOptions().keys,
        contains('auto'),
      );
    });

    test('a single entered dimension switches to truck costing', () {
      // The whole point of the feature. Valhalla's `auto` costing ignores
      // `maxheight` outright, so a crew who entered a height gets nothing back
      // from `auto` — the switch is what makes a low bridge avoidable at all.
      const tall = RoutePreferences(vehicle: ChaseVehicle(heightMetres: 3.2));
      expect(tall.valhallaCosting, 'truck');
      expect(tall.requiresValhallaCosting, isTrue);
      final options = tall.valhallaCostingOptions();
      expect(options.keys, ['truck']);
      expect((options['truck']! as Map)['height'], 3.2);
    });

    test('towing alone does not switch to truck costing', () {
      // The dangerous case, asserted rather than assumed. `truck` costing with
      // no dimensions inherits Valhalla's articulated-lorry defaults — 4.11 m
      // and 21.77 t — which would refuse most of the roads to a launch site,
      // for reasons the crew never stated.
      const towingOnly = RoutePreferences(vehicle: ChaseVehicle(towing: true));
      expect(towingOnly.vehicle.towing, isTrue);
      expect(towingOnly.valhallaCosting, 'auto');
      expect(towingOnly.valhallaCostingOptions().keys, ['auto']);
    });

    test('unentered dimensions are sent small, never omitted', () {
      // Omitting them would inherit the lorry defaults. A blank field means
      // "not told", which must restrict nothing, so the fallbacks understate.
      final dimensions = const ChaseVehicle(
        heightMetres: 3,
      ).valhallaTruckDimensions();
      expect(dimensions['height'], 3);
      expect(dimensions['width'], 2);
      expect(dimensions['length'], 5);
      expect(dimensions['weight'], 2);
      expect(dimensions['hazmat'], isFalse);
    });
  });

  group('Valhalla road costing options', () {
    test('the profile is auto, and never motorcycle again', () {
      // `use_tracks` is auto's lever; `use_trails` is the motorcycle one, and
      // Valhalla ignores it under auto. A naive rename would have silently
      // stopped the byway preference working at all.
      final options = RoutePreferences.defaults.valhallaRoadCostingOptions();
      expect(options.containsKey('use_tracks'), isTrue);
      expect(options.containsKey('use_trails'), isFalse);
    });

    test('a crew that has not asked to avoid unsurfaced ways gets tracks', () {
      // A landing field is usually reached down a farm track, and auto costing
      // avoids tracks by default, so they must be opened back up explicitly.
      const allowed = RoutePreferences(
        bywaySurface: BywaySurfacePreference.allowUnsurfaced,
      );
      expect(allowed.valhallaRoadCostingOptions()['use_tracks'], 0.5);
      expect(allowed.valhallaRoadCostingOptions()['exclude_unpaved'], isFalse);
      expect(
        RoutePreferences.defaults.valhallaRoadCostingOptions()['use_tracks'],
        0,
      );
    });

    test('defaults', () {
      expect(RoutePreferences.defaults.valhallaRoadCostingOptions(), {
        'use_highways': 1,
        'use_living_streets': 0.5,
        'use_tolls': 0.5,
        'use_ferry': 0.5,
        'use_tracks': 0,
        'exclude_highways': false,
        'exclude_tolls': false,
        'exclude_ferries': false,
        'exclude_unpaved': true,
      });
    });

    test('avoiding major roads beats a style that prefers them', () {
      // One is a leaning, the other is an instruction the crew typed.
      expect(
        const RoutePreferences(
          style: RouteStyle.majorRoads,
          avoidMajorRoads: true,
        ).valhallaRoadCostingOptions()['use_highways'],
        0.08,
      );
    });

    test('avoiding motorways excludes rather than penalises them', () {
      final options = const RoutePreferences(
        avoidMotorways: true,
      ).valhallaRoadCostingOptions();
      expect(options['exclude_highways'], isTrue);
      expect(options['use_highways'], 1);
    });

    test('the dimensions ride alongside the road levers, not instead', () {
      final options =
          const RoutePreferences(
                avoidMotorways: true,
                vehicle: ChaseVehicle(heightMetres: 3.1, towing: true),
              ).valhallaCostingOptions()['truck']!
              as Map;
      expect(options['exclude_highways'], isTrue);
      expect(options['use_tracks'], 0);
      expect(options['height'], 3.1);
    });
  });

  group('choosing between alternatives', () {
    test('only a towing vehicle asks for straighter roads', () {
      expect(RoutePreferences.defaults.prefersStraighterRoads, isFalse);
      expect(
        const RoutePreferences(
          vehicle: ChaseVehicle(towing: true),
        ).prefersStraighterRoads,
        isTrue,
      );
    });

    test('a length alone is not read as a bend aversion', () {
      // "5 m long" describes an ordinary estate car. Inferring that it wants
      // straighter roads would apply the preference to most of the fleet.
      expect(
        const RoutePreferences(
          vehicle: ChaseVehicle(lengthMetres: 5),
        ).prefersStraighterRoads,
        isFalse,
      );
    });
  });

  test('preferences round-trip through JSON, vehicle and all', () {
    const preferences = RoutePreferences(
      style: RouteStyle.majorRoads,
      avoidMotorways: true,
      avoidMajorRoads: true,
      avoidTolls: true,
      avoidFerries: true,
      bywaySurface: BywaySurfacePreference.allowUnsurfaced,
      vehicle: ChaseVehicle(
        heightMetres: 3.2,
        widthMetres: 2.1,
        lengthMetres: 11,
        grossWeightTonnes: 3.5,
        towing: true,
      ),
    );

    expect(RoutePreferences.fromJson(preferences.toJson()), preferences);
    expect(preferences.toJson()['style'], 'major-roads');
    expect(preferences.toJson()['bywaySurface'], 'allow-unsurfaced');
  });

  test('an unspecified vehicle is absent from the JSON, not an empty map', () {
    // "Never told us" and "told us and then cleared it" mean the same thing and
    // must read back the same.
    expect(RoutePreferences.defaults.toJson().containsKey('vehicle'), isFalse);
    expect(
      RoutePreferences.fromJson(RoutePreferences.defaults.toJson()).vehicle,
      ChaseVehicle.unspecified,
    );
  });

  test('the applied notes end with the numbers being routed against', () {
    expect(
      const RoutePreferences(
        style: RouteStyle.majorRoads,
        avoidMotorways: true,
        avoidTolls: true,
        vehicle: ChaseVehicle(heightMetres: 3.2, towing: true),
      ).appliedNotes,
      [
        'Major roads preferred',
        'motorways excluded',
        'tolls excluded',
        'unsurfaced byways avoided',
        'towing',
        '3.2 m high',
      ],
    );
  });

  test('with nothing chosen the summary says direct, not quickest', () {
    expect(RoutePreferences.defaults.summary, 'Unsurfaced byways avoided.');
    expect(
      const RoutePreferences(
        bywaySurface: BywaySurfacePreference.allowUnsurfaced,
      ).summary,
      'Unsurfaced byways allowed.',
    );
  });
}
