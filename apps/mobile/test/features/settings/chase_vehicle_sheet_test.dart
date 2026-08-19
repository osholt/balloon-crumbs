import 'package:balloon_crumbs/controllers/chase_vehicle_controller.dart';
import 'package:balloon_crumbs/domain/chase_vehicle.dart';
import 'package:balloon_crumbs/features/settings/chase_vehicle_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(
  WidgetTester tester,
  ChaseVehicleController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                ChaseVehicleSheet.show(context, controller: controller),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Scrolls to Save before tapping it.
///
/// Toggling towing rewrites two helper lines, which is enough to push the button
/// off an 800x600 test viewport. Tapping blind then misses and the test fails
/// for a reason that has nothing to do with what it is checking.
Future<void> _save(WidgetTester tester) async {
  final save = find.byKey(const Key('chase-vehicle-save'));
  await tester.scrollUntilVisible(
    save,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a crew enters what they know and it is saved', (tester) async {
    final controller = ChaseVehicleController.memory();
    await _open(tester, controller);

    await tester.enterText(
      find.byKey(const Key('chase-vehicle-height-field')),
      '3.2',
    );
    await tester.enterText(
      find.byKey(const Key('chase-vehicle-weight-field')),
      '3.5',
    );
    final towing = find.byKey(const Key('chase-vehicle-towing-switch'));
    await tester.scrollUntilVisible(
      towing,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(towing);
    await tester.pumpAndSettle();
    await _save(tester);

    expect(controller.vehicle.heightMetres, 3.2);
    expect(controller.vehicle.grossWeightTonnes, 3.5);
    expect(controller.vehicle.towing, isTrue);
    // Untouched fields stay untold rather than becoming a number.
    expect(controller.vehicle.widthMetres, isNull);
    expect(controller.vehicle.lengthMetres, isNull);
  });

  testWidgets('saving nothing saves nothing', (tester) async {
    final controller = ChaseVehicleController.memory();
    await _open(tester, controller);
    await _save(tester);

    expect(controller.vehicle, ChaseVehicle.unspecified);
  });

  testWidgets('an existing vehicle opens with its numbers in the fields', (
    tester,
  ) async {
    final controller = ChaseVehicleController.memory(
      vehicle: const ChaseVehicle(heightMetres: 3.2, lengthMetres: 11),
    );
    await _open(tester, controller);

    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('chase-vehicle-height-field')),
          )
          .controller
          ?.text,
      '3.2',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('chase-vehicle-length-field')),
          )
          .controller
          ?.text,
      '11',
    );
  });

  testWidgets('an empty field is hinted as not set, never as zero', (
    tester,
  ) async {
    // "0" would read as a value, and a height of zero fits under everything.
    await _open(tester, ChaseVehicleController.memory());
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('chase-vehicle-height-field')),
          )
          .decoration
          ?.hintText,
      'Not set',
    );
  });

  testWidgets('the weight label says which weight, never just "MTW"', (
    tester,
  ) async {
    // Reading this as a towing capacity instead of a laden weight puts the
    // wrong number against a weight-limited bridge, and it is the crew who
    // finds out.
    final controller = ChaseVehicleController.memory(
      vehicle: const ChaseVehicle(towing: true),
    );
    await _open(tester, controller);

    final weight = tester.widget<TextField>(
      find.byKey(const Key('chase-vehicle-weight-field')),
    );
    expect(weight.decoration?.labelText, 'Maximum weight (tonnes)');
    expect(weight.decoration?.helperText, contains('together'));
    expect(weight.decoration?.helperText, contains('not what the towbar'));
  });

  testWidgets('the mapping caveat is on screen, not buried', (tester) async {
    // The feature can only avoid restrictions OpenStreetMap records, and UK
    // maxheight coverage is patchy. A clear route must not read as a promise.
    await _open(tester, ChaseVehicleController.memory());
    expect(
      tester
          .widget<Text>(find.byKey(const Key('chase-vehicle-coverage-caveat')))
          .data,
      allOf(
        contains('only avoid restrictions that are mapped'),
        contains('keep reading the signs'),
      ),
    );
  });

  testWidgets('a nonsense number is discarded rather than stored', (
    tester,
  ) async {
    final controller = ChaseVehicleController.memory();
    await _open(tester, controller);
    await tester.enterText(
      find.byKey(const Key('chase-vehicle-height-field')),
      '0',
    );
    await _save(tester);

    expect(controller.vehicle.heightMetres, isNull);
  });
}
