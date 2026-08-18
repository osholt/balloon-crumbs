import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/route_preferences.dart';

/// These fixtures are the web planner's own numbers, copied from
/// `apps/website/planner-core.mjs`. If either side changes, one of the two test
/// suites fails, which is what stops the app and the planner disagreeing about
/// what a preference means (#182).
void main() {
  group('route styles match the web planner contract', () {
    test('api values and detour limits are the planner values', () {
      expect(RouteStyle.values.map((style) => style.apiValue), [
        'quickest',
        'balanced',
        'twisty',
        'very-twisty',
      ]);
      expect(RouteStyle.quickest.detourLimit, 1);
      expect(RouteStyle.flowing.detourLimit, 1.25);
      expect(RouteStyle.twisty.detourLimit, 1.5);
      expect(RouteStyle.veryTwisty.detourLimit, 1.75);
    });

    test('only the quickest style declines alternatives', () {
      expect(RouteStyle.quickest.prefersBends, isFalse);
      expect(RouteStyle.flowing.prefersBends, isTrue);
      expect(RouteStyle.twisty.prefersBends, isTrue);
      expect(RouteStyle.veryTwisty.prefersBends, isTrue);
    });

    test('an unknown stored style falls back to quickest', () {
      expect(RouteStyle.fromApiValue('flowing'), isNull);
      expect(
        RoutePreferences.fromJson(const {'style': 'flowing'}).style,
        RouteStyle.quickest,
      );
    });
  });

  group('byway default', () {
    test('unsurfaced byways are avoided unless a rider says otherwise', () {
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

    test('the summary always states which way round the byways are', () {
      expect(RoutePreferences.defaults.summary, 'Unsurfaced byways avoided.');
      expect(
        const RoutePreferences(
          bywaySurface: BywaySurfacePreference.allowUnsurfaced,
        ).summary,
        'Unsurfaced byways allowed.',
      );
    });
  });

  group('engine choice matches requestRoadRoute in the web planner', () {
    test('defaults stay on OSRM', () {
      expect(RoutePreferences.defaults.requiresValhallaCosting, isFalse);
    });

    test('a bendier style alone stays on OSRM', () {
      for (final style in RouteStyle.values) {
        expect(
          RoutePreferences(style: style).requiresValhallaCosting,
          isFalse,
          reason: '${style.apiValue} needs only OSRM alternatives',
        );
      }
    });

    test('each avoidance moves to the motorcycle service', () {
      expect(
        const RoutePreferences(avoidMotorways: true).requiresValhallaCosting,
        isTrue,
      );
      expect(
        const RoutePreferences(avoidMajorRoads: true).requiresValhallaCosting,
        isTrue,
      );
      expect(
        const RoutePreferences(avoidTolls: true).requiresValhallaCosting,
        isTrue,
      );
      expect(
        const RoutePreferences(avoidFerries: true).requiresValhallaCosting,
        isTrue,
      );
    });

    test('seeking byways moves to the motorcycle service', () {
      // OSRM's car profile does not route highway=track at all, so this is the
      // byway case OSRM cannot serve.
      expect(
        const RoutePreferences(
          bywaySurface: BywaySurfacePreference.allowUnsurfaced,
        ).requiresValhallaCosting,
        isTrue,
      );
    });
  });

  group('Valhalla auto costing options', () {
    test('the profile is auto, and never motorcycle again', () {
      // A chase vehicle is a Land Rover or a van, often towing. Routing it as a
      // motorbike sends it down roads it should not take and reads speed limits
      // off roads it cannot use, so the option names themselves are pinned:
      // `use_tracks` is auto's lever, `use_trails` is the motorcycle one and
      // Valhalla ignores it under auto.
      final options = RoutePreferences.defaults.valhallaAutoCostingOptions();
      expect(options.containsKey('use_tracks'), isTrue);
      expect(options.containsKey('use_trails'), isFalse);
    });

    test('a crew that has not asked to avoid unsurfaced ways gets tracks', () {
      // The one that matters for a retrieve: a landing field is usually reached
      // down a farm track, and Valhalla's auto costing avoids tracks by default,
      // so they have to be opened back up explicitly.
      const allowed = RoutePreferences(
        bywaySurface: BywaySurfacePreference.allowUnsurfaced,
      );
      expect(allowed.valhallaAutoCostingOptions()['use_tracks'], 0.5);
      expect(allowed.valhallaAutoCostingOptions()['exclude_unpaved'], isFalse);
      expect(
        RoutePreferences.defaults.valhallaAutoCostingOptions()['use_tracks'],
        0,
      );
    });

    test('defaults', () {
      expect(RoutePreferences.defaults.valhallaAutoCostingOptions(), {
        'use_highways': 1,
        'use_tolls': 0.5,
        'use_ferry': 0.5,
        'use_tracks': 0,
        'exclude_highways': false,
        'exclude_tolls': false,
        'exclude_ferries': false,
        'exclude_unpaved': true,
      });
    });

    test('each style sets its own highway preference', () {
      expect(
        RouteStyle.values.map(
          (style) => RoutePreferences(
            style: style,
          ).valhallaAutoCostingOptions()['use_highways'],
        ),
        [1, 0.6, 0.35, 0.15],
      );
    });

    test('avoiding major roads overrides the style highway preference', () {
      expect(
        const RoutePreferences(
          style: RouteStyle.veryTwisty,
          avoidMajorRoads: true,
        ).valhallaAutoCostingOptions()['use_highways'],
        0.08,
      );
    });

    test('avoiding motorways excludes rather than penalises them', () {
      final options = const RoutePreferences(
        avoidMotorways: true,
      ).valhallaAutoCostingOptions();
      expect(options['exclude_highways'], isTrue);
      // The motorway exclusion is independent of the twistiness setting.
      expect(options['use_highways'], 1);
    });

    test('allowing byways relaxes both surface levers together', () {
      final options = const RoutePreferences(
        bywaySurface: BywaySurfacePreference.allowUnsurfaced,
      ).valhallaAutoCostingOptions();
      expect(options['use_tracks'], 0.5);
      expect(options['exclude_unpaved'], isFalse);
    });

    test('the whole combination the issue asks for', () {
      expect(
        const RoutePreferences(
          style: RouteStyle.twisty,
          avoidMotorways: true,
        ).valhallaAutoCostingOptions(),
        {
          'use_highways': 0.35,
          'use_tolls': 0.5,
          'use_ferry': 0.5,
          'use_tracks': 0,
          'exclude_highways': true,
          'exclude_tolls': false,
          'exclude_ferries': false,
          'exclude_unpaved': true,
        },
      );
    });
  });

  test('preferences round-trip through JSON', () {
    const preferences = RoutePreferences(
      style: RouteStyle.veryTwisty,
      avoidMotorways: true,
      avoidMajorRoads: true,
      avoidTolls: true,
      avoidFerries: true,
      bywaySurface: BywaySurfacePreference.allowUnsurfaced,
    );

    expect(RoutePreferences.fromJson(preferences.toJson()), preferences);
    expect(preferences.toJson()['style'], 'very-twisty');
    expect(preferences.toJson()['bywaySurface'], 'allow-unsurfaced');
  });

  test('the applied notes read in the planner order', () {
    expect(
      const RoutePreferences(
        style: RouteStyle.flowing,
        avoidMotorways: true,
        avoidMajorRoads: true,
        avoidTolls: true,
        avoidFerries: true,
      ).appliedNotes,
      [
        'Flowing-road bias',
        'motorways excluded',
        'major roads avoided',
        'tolls excluded',
        'ferries excluded',
        'unsurfaced byways avoided',
      ],
    );
  });
}
