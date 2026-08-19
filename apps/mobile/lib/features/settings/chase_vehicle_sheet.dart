import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/chase_vehicle_controller.dart';
import '../../domain/chase_vehicle.dart';

/// Where the crew describes their own vehicle, once.
///
/// Four numbers and a switch, all optional. The wording is doing real work
/// here: an empty field has to read as "not told" and never as "no restriction",
/// because the failure mode is not a duller route, it is a trailer under a
/// bridge that fitted the number nobody entered.
class ChaseVehicleSheet extends StatefulWidget {
  const ChaseVehicleSheet({super.key, required this.controller});

  final ChaseVehicleController controller;

  static Future<void> show(
    BuildContext context, {
    required ChaseVehicleController controller,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => ChaseVehicleSheet(controller: controller),
  );

  @override
  State<ChaseVehicleSheet> createState() => _ChaseVehicleSheetState();
}

class _ChaseVehicleSheetState extends State<ChaseVehicleSheet> {
  late final TextEditingController _height;
  late final TextEditingController _width;
  late final TextEditingController _length;
  late final TextEditingController _weight;
  late bool _towing;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.controller.vehicle;
    _height = TextEditingController(text: _text(vehicle.heightMetres));
    _width = TextEditingController(text: _text(vehicle.widthMetres));
    _length = TextEditingController(text: _text(vehicle.lengthMetres));
    _weight = TextEditingController(text: _text(vehicle.grossWeightTonnes));
    _towing = vehicle.towing;
  }

  @override
  void dispose() {
    _height.dispose();
    _width.dispose();
    _length.dispose();
    _weight.dispose();
    super.dispose();
  }

  static String _text(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  ChaseVehicle get _edited => ChaseVehicle.fromJson({
    'heightMetres': _height.text,
    'widthMetres': _width.text,
    'lengthMetres': _length.text,
    'grossWeightTonnes': _weight.text,
    'towing': _towing,
  });

  Future<void> _save() async {
    await widget.controller.set(_edited);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chase vehicle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'All optional, and remembered between flights. Fill in what you '
              'know and routes will avoid low bridges, weight limits and width '
              'restrictions that OpenStreetMap records.',
              style: TextStyle(color: Color(0xFF9CA7B5), fontSize: 13),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('chase-vehicle-towing-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Towing a trailer'),
              subtitle: const Text(
                'Prefers straighter roads, and makes the weight below the '
                'combined weight.',
              ),
              value: _towing,
              onChanged: (value) => setState(() => _towing = value),
            ),
            const SizedBox(height: 8),
            _Dimension(
              fieldKey: const Key('chase-vehicle-height-field'),
              controller: _height,
              label: 'Height (m)',
              helper:
                  'Including anything on the roof. This is the one low '
                  'bridges care about.',
            ),
            const SizedBox(height: 12),
            _Dimension(
              fieldKey: const Key('chase-vehicle-width-field'),
              controller: _width,
              label: 'Width (m)',
              helper: 'Excluding mirrors.',
            ),
            const SizedBox(height: 12),
            _Dimension(
              fieldKey: const Key('chase-vehicle-length-field'),
              controller: _length,
              label: 'Length (m)',
              helper: _towing
                  ? 'Vehicle and trailer together.'
                  : 'Overall length.',
            ),
            const SizedBox(height: 12),
            _Dimension(
              fieldKey: const Key('chase-vehicle-weight-field'),
              controller: _weight,
              label: 'Maximum weight (tonnes)',
              // Never abbreviated in the label. Reading this as a towing
              // capacity instead of a laden weight puts the wrong number
              // against a weight-limited bridge, and it is the crew who finds
              // out.
              helper: _towing
                  ? 'The heaviest the vehicle and loaded trailer can legally be '
                        'together — not what the towbar is rated for.'
                  : 'The heaviest the vehicle can legally be when loaded.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Routes can only avoid restrictions that are mapped. A clear '
              'route means nothing was recorded on it, not that it is '
              'definitely passable — keep reading the signs.',
              key: Key('chase-vehicle-coverage-caveat'),
              style: TextStyle(color: Color(0xFFFFC857), fontSize: 12),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('chase-vehicle-save'),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Dimension extends StatelessWidget {
  const _Dimension({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.helper,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      // Not "0" and not "none": an empty field means nobody has said, and the
      // hint must not read as a value.
      hintText: 'Not set',
    ),
  );
}
