import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/rider_color.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/features/map/craft_icon.dart';
import 'package:balloon_crumbs/features/map/rider_symbol_picker.dart';

void main() {
  group('the motorcycle styles this replaced', () {
    // Fifteen bike names are in stored sessions and on the wire from peers that
    // have not updated. None of them may throw, and none may resolve to the
    // balloon: putting a chase vehicle's marker on the aircraft would be worse
    // than showing the wrong vehicle.
    const retiredBikeNames = [
      'adventureTourer', 'roadster', 'dualSport', 'sportNaked',
      'cruiserClassic', 'standardTwin', 'cafeRacer', 'dirtBike',
      'fullTourer', 'cruiserBagger', 'scrambler', 'sportTouring',
      'scooter', 'sidecarRig', 'streetFighter',
    ];

    test('degrade to the default craft rather than failing to parse', () {
      for (final name in retiredBikeNames) {
        expect(
          craftIconStyleFromName(name),
          craftIconStyleDefault,
          reason: name,
        );
      }
      expect(craftIconStyleFromName(null), craftIconStyleDefault);
      expect(craftIconStyleFromName('somethingNewer'), craftIconStyleDefault);
    });

    test('never resolve to the balloon', () {
      for (final name in retiredBikeNames) {
        expect(craftIconStyleFromName(name).isBalloon, isFalse, reason: name);
      }
      expect(craftIconStyleDefault.isBalloon, isFalse);
    });

    test('a craft this build knows round-trips by name', () {
      for (final style in CraftIconStyle.values) {
        expect(craftIconStyleFromName(style.name), style);
      }
    });

    test('a retired bike name still yields a usable rider symbol', () {
      // `fromWireValue` reads the same field, so an older peer's snapshot has to
      // produce the craft symbol rather than an absent one.
      expect(
        RiderSymbol.fromWireValue('scrambler').kind,
        RiderSymbolKind.craft,
      );
    });
  });

  test('initials use first and last names, or two letters from one name', () {
    expect(riderInitials('Keith Simmonds'), 'KS');
    expect(riderInitials('  Katherine   L  '), 'KL');
    expect(riderInitials('Muffin'), 'MU');
    expect(riderInitials(''), '?');
  });

  test('symbol wire values remain backward compatible with bike styles', () {
    const initials = RiderSymbol.initials();
    const emoji = RiderSymbol.emoji('😈');

    expect(
      const RiderSymbol.craft().wireValue(CraftIconStyle.van),
      CraftIconStyle.van.name,
    );
    expect(initials.wireValue(CraftIconStyle.van), 'initials');
    expect(emoji.wireValue(CraftIconStyle.van), 'emoji:😈');
    expect(
      RiderSymbol.fromWireValue(CraftIconStyle.van.name),
      riderSymbolDefault,
    );
    expect(RiderSymbol.fromWireValue('initials'), initials);
    expect(RiderSymbol.fromWireValue('emoji:😈'), emoji);
    expect(RiderSymbol.fromWireValue('emoji:not-an-emoji'), riderSymbolDefault);
  });

  test('custom initials and ink round-trip inside the legacy wire field', () {
    const custom = RiderSymbol.initials(
      customInitials: 'OH',
      initialsInk: RiderInitialsInk.purple,
    );

    expect(custom.storageValue, 'initials:v1:T0g:purple');
    expect(custom.storageValue.length, lessThanOrEqualTo(40));
    expect(custom.initialsFor('Different Name'), 'OH');
    expect(RiderSymbol.fromStorageValue(custom.storageValue), custom);
    expect(
      RiderSymbol.fromWireValue(
        custom.wireValue(CraftIconStyle.van),
      ),
      custom,
    );
    expect(
      RiderSymbol.fromStorageValue('initials:v1::white'),
      const RiderSymbol.initials(initialsInk: RiderInitialsInk.white),
    );
  });

  test('malformed or oversized initials fail back to the legacy bike', () {
    expect(normalizeCustomRiderInitials('oh'), 'OH');
    expect(normalizeCustomRiderInitials('É2'), 'É2');
    expect(normalizeCustomRiderInitials('ABCD'), isNull);
    expect(normalizeCustomRiderInitials('A:B'), isNull);
    expect(
      RiderSymbol.fromStorageValue('initials:v1:!!!:purple'),
      riderSymbolDefault,
    );
    expect(
      RiderSymbol.fromStorageValue('initials:v1:QUJDRA:purple'),
      riderSymbolDefault,
    );
    expect(
      RiderSymbol.fromStorageValue('initials:v1:T0g:ultraviolet'),
      riderSymbolDefault,
    );
  });

  test('the expanded rider palette includes visible Purple and White', () {
    expect(riderColorFromName('purple'), RiderColor.purple);
    expect(riderColorFromName('white'), RiderColor.white);
    expect(RiderColor.purple.color, const Color(0xFF9B7BFF));
    expect(RiderColor.white.color, const Color(0xFFF4F6F8));
    expect(RiderColor.values.length, greaterThanOrEqualTo(13));
    expect(
      riderBadgeStrokeColor(RiderColor.white.color),
      const Color(0xFF10151C),
    );
  });

  test('the curated emoji catalogue includes more rider identities', () {
    expect(riderEmojiChoices.length, greaterThanOrEqualTo(30));
    expect(riderEmojiChoices, containsAll(const ['🧭', '🍩', '🦅', '🥷']));
  });

  test('live location carries a custom symbol through the existing field', () {
    final location = RiderLocation(
      riderId: 'keith',
      displayName: 'Keith Simmonds',
      role: RideRole.rider,
      sample: LocationSample(
        position: const GeoPoint(latitude: 51.5, longitude: -2.5),
        recordedAt: DateTime.utc(2026, 7, 29),
        accuracyMeters: 4,
      ),
      receivedAt: DateTime.utc(2026, 7, 29),
      motorcycleStyle: CraftIconStyle.van,
      riderSymbol: const RiderSymbol.emoji('😈'),
    );

    final json = location.toJson();
    expect(json['motorcycleStyle'], 'emoji:😈');
    expect(
      RiderLocation.fromJson(json).riderSymbol,
      const RiderSymbol.emoji('😈'),
    );
  });

  testWidgets('picker switches between initials and a chosen emoji', (
    tester,
  ) async {
    var symbol = riderSymbolDefault;
    var style = CraftIconStyle.fourByFour;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SingleChildScrollView(
                child: RiderSymbolPicker(
                  displayName: 'Keith Simmonds',
                  selectedSymbol: symbol,
                  motorcycleStyle: style,
                  badgeColor: Colors.teal,
                  keyPrefix: 'test-symbol',
                  bikeKeyPrefix: 'test-bike',
                  onSymbolChanged: (value) => update(() => symbol = value),
                  onMotorcycleStyleChanged: (value) =>
                      update(() => style = value),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('test-symbol-initials')));
    await tester.pump();
    expect(symbol, const RiderSymbol.initials());
    expect(find.text('KS'), findsWidgets);

    await tester.tap(find.byKey(const Key('test-symbol-emoji')));
    await tester.pump();
    final devilKey = Key(
      'test-symbol-emoji-${'😈'.runes.map((rune) => rune.toRadixString(16)).join('-')}',
    );
    await tester.ensureVisible(find.byKey(devilKey));
    await tester.tap(find.byKey(devilKey));
    await tester.pump();

    expect(symbol, const RiderSymbol.emoji('😈'));
    expect(find.text('😈'), findsWidgets);
  });

  testWidgets('picker edits initials and their ink with a live preview', (
    tester,
  ) async {
    var symbol = const RiderSymbol.initials();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: RiderSymbolPicker(
                displayName: 'Oliver Holt',
                selectedSymbol: symbol,
                motorcycleStyle: CraftIconStyle.van,
                badgeColor: RiderColor.white.color,
                keyPrefix: 'custom-symbol',
                bikeKeyPrefix: 'custom-bike',
                onSymbolChanged: (value) => setState(() => symbol = value),
                onMotorcycleStyleChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('rider-custom-initials')),
      'tec',
    );
    await tester.pump();
    final purpleInk = find.byKey(
      const Key('custom-symbol-initials-ink-purple'),
    );
    await tester.ensureVisible(purpleInk);
    await tester.tap(purpleInk);
    await tester.pump();

    expect(symbol.storageValue, 'initials:v1:VEVD:purple');
    expect(find.text('TEC'), findsWidgets);
    expect(find.textContaining('in purple'), findsOneWidget);
  });

  testWidgets('initials use the available rider badge instead of body text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: RiderMarkerBadge(
            style: CraftIconStyle.van,
            badgeColor: Colors.teal,
            symbol: RiderSymbol.initials(),
            displayName: 'Keith Simmonds',
            size: 34,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('KS'));
    expect(text.style?.fontSize, 34);
    expect(find.byKey(const Key('rider-marker-initials-fill')), findsOneWidget);
  });

  test('MapLibre raster keeps two initials on one line', () async {
    final result = await rasterizeRiderSymbolPng(
      symbol: const RiderSymbol.initials(),
      displayName: 'Keith Simmonds',
      motorcycleStyle: CraftIconStyle.van,
      size: 128,
    );
    final codec = await ui.instantiateImageCodec(result.bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final pixels = data!.buffer.asUint8List();
    var left = 128;
    var right = -1;
    var top = 128;
    var bottom = -1;
    for (var y = 0; y < 128; y += 1) {
      for (var x = 0; x < 128; x += 1) {
        if (pixels[(y * 128 + x) * 4 + 3] == 0) continue;
        left = x < left ? x : left;
        right = x > right ? x : right;
        top = y < top ? y : top;
        bottom = y > bottom ? y : bottom;
      }
    }

    expect(right - left, greaterThan(bottom - top));
    expect(right - left, greaterThan(100));
  });

  test('MapLibre raster preserves the chosen initials ink', () async {
    const symbol = RiderSymbol.initials(
      customInitials: 'OH',
      initialsInk: RiderInitialsInk.purple,
    );
    final result = await rasterizeRiderSymbolPng(
      symbol: symbol,
      displayName: 'Ignored Name',
      motorcycleStyle: CraftIconStyle.van,
    );
    final frame = await (await ui.instantiateImageCodec(
      result.bytes,
    )).getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final pixels = data!.buffer.asUint8List();
    var purplePixels = 0;
    for (var index = 0; index < pixels.length; index += 4) {
      if (pixels[index] > 140 &&
          pixels[index + 1] > 100 &&
          pixels[index + 2] > 220 &&
          pixels[index + 3] > 180) {
        purplePixels += 1;
      }
    }

    expect(result.sdf, isFalse);
    expect(purplePixels, greaterThan(100));
    expect(
      symbol.imageName('Ignored Name', CraftIconStyle.van),
      contains('purple'),
    );
  });

  group('the map and the picker size initials by one rule (#259)', () {
    // Two failed validations sized the marker alone. What was left was that the
    // three renderers each had their own answer, and the one riders actually
    // see was the smallest: initials inherited the icon size chosen for a bike,
    // which is a pictogram meant to sit *inside* the badge. On the native map
    // they came out at about 0.76 of the badge while the symbol picker's
    // preview drew them at 0.94 — a quarter smaller than the thing the rider
    // picked them from.

    /// The side of the box the badge gives its glyph, measured on the widget
    /// both the picker and the flutter_map marker use.
    Future<double> glyphBox(
      WidgetTester tester, {
      required double size,
      required double borderWidth,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RiderMarkerBadge(
                style: CraftIconStyle.van,
                symbol: const RiderSymbol.initials(),
                displayName: 'Keith Simmonds',
                badgeColor: const Color(0xFF2F80ED),
                size: size,
                borderWidth: borderWidth,
              ),
            ),
          ),
        ),
      );
      return tester
          .getSize(find.byKey(const Key('rider-marker-initials-fill')))
          .width;
    }

    testWidgets('the badge gives its initials the shared share of the circle', (
      tester,
    ) async {
      // Measured against the coloured circle, not the widget's outer box: the
      // border is drawn inside that box, so a rule written against the outer
      // box makes a bordered marker and a borderless preview disagree.
      expect(
        await glyphBox(tester, size: 34, borderWidth: 0),
        closeTo(34 * riderInitialsBadgeFill, 0.01),
      );
      expect(
        await glyphBox(tester, size: 34, borderWidth: 2),
        closeTo(30 * riderInitialsBadgeFill, 0.01),
      );
    });

    test('the raster fills its square by the shared constant', () async {
      // The other half of the native map's answer. The icon size below maps
      // this square onto the badge one to one, so whatever share the ink takes
      // of the square is the share it takes of the badge — which means this
      // constant and the badge widget's inset have to be the same number, and
      // a test has to say so or they will drift apart again.
      final result = await rasterizeRiderSymbolPng(
        symbol: const RiderSymbol.initials(),
        displayName: 'Keith Simmonds',
        motorcycleStyle: CraftIconStyle.van,
      );
      final frame = await (await ui.instantiateImageCodec(
        result.bytes,
      )).getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final pixels = data!.buffer.asUint8List();
      const side = riderSymbolRasterSize;
      var left = side.toInt();
      var right = -1;
      for (var y = 0; y < side; y += 1) {
        for (var x = 0; x < side; x += 1) {
          if (pixels[(y * side.toInt() + x) * 4 + 3] == 0) continue;
          left = x < left ? x : left;
          right = x > right ? x : right;
        }
      }

      // Measured on ink rather than on layout, so it is a lower bound: the span
      // includes antialiasing at both edges and cannot be compared to the
      // constant exactly. What it establishes is that the glyph reaches the
      // fill and does not stop short of it — 0.76, the share it used to get on
      // the native map, measures 0.80 here and fails.
      final inkShare = (right - left + 1) / side;
      expect(
        inkShare,
        greaterThan(riderInitialsBadgeFill - 0.03),
        reason:
            'two letters are wider than they are tall, so the fill is what '
            'bounds them, and they have to actually reach it',
      );
      expect(inkShare, lessThanOrEqualTo(1));
    });

    test('the native map draws them at the same share of the same badge', () {
      // The raster insets by the same constant inside its own square, and the
      // icon size maps that square one to one onto the badge — so the two
      // renderers of the same marker land on the same number.
      const badgeDiameter = 30.0;
      final onScreen =
          riderSymbolRasterSize *
          riderInitialsIconSize(badgeDiameter: badgeDiameter) *
          riderInitialsBadgeFill;

      expect(onScreen, closeTo(badgeDiameter * riderInitialsBadgeFill, 0.01));
    });

    test('initials are given more room than a bike, not the same', () {
      // The whole defect in one line. 0.19, 0.2 and 0.09 are the sizes the
      // three rider layers use for a pictogram, and initials took them.
      for (final (badgeDiameter, pictogram) in const [
        (30.0, 0.19), // other riders on the ride map
        (32.0, 0.2), // the local rider's own marker
        (14.0, 0.09), // the group overview
      ]) {
        final initials = riderInitialsIconSize(badgeDiameter: badgeDiameter);
        expect(
          initials,
          greaterThan(pictogram * 1.15),
          reason:
              'a badge of $badgeDiameter should not size its initials like '
              'a bike',
        );
        expect(
          riderSymbolRasterSize * initials * riderInitialsBadgeFill,
          closeTo(badgeDiameter * riderInitialsBadgeFill, 0.01),
        );
      }
    });

    test('the rule is derived from the badge, not tuned per layer', () {
      // A change to a badge's radius must carry its initials with it. Leaving
      // them behind is precisely how they ended up at three quarters size.
      expect(riderInitialsIconSize(badgeDiameter: 60), 60 / 128);
      expect(riderInitialsIconSize(badgeDiameter: 30, rasterSize: 64), 30 / 64);
    });
  });
}
