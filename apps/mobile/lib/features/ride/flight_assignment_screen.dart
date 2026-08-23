import 'package:flutter/material.dart';

import '../../controllers/ride_controller.dart';
import '../../domain/flight_role.dart';
import '../../domain/ride_role.dart';

/// One-time repair gate for sessions created before flight roles and crafts.
///
/// No live-flight service is mounted behind this screen. Until assignment is
/// explicit, the app cannot know whether road guidance or airborne information
/// is appropriate and therefore shows neither.
class FlightAssignmentScreen extends StatefulWidget {
  const FlightAssignmentScreen({super.key, required this.controller});

  final RideController controller;

  @override
  State<FlightAssignmentScreen> createState() => _FlightAssignmentScreenState();
}

class _FlightAssignmentScreenState extends State<FlightAssignmentScreen> {
  final _vehicleLabelController = TextEditingController(text: 'Land Rover');
  FlightRole _role = FlightRole.chaseCrew;

  bool get _legacyCreator => widget.controller.session?.role == RideRole.lead;

  @override
  void dispose() {
    _vehicleLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Confirm your flight role')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _legacyCreator
                        ? Icons.air_outlined
                        : Icons.groups_2_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _legacyCreator
                        ? 'Restore this phone as the pilot'
                        : 'Where are you in this flight?',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _legacyCreator
                        ? 'This flight predates separate balloon and chase roles. Confirming creates the balloon and restores pilot authority.'
                        : 'This flight predates separate balloon and chase roles. Choose your job before location sharing or live controls resume.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFABB5C1)),
                  ),
                  if (!_legacyCreator) ...[
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _roleChip(
                          FlightRole.balloonCrew,
                          Icons.air,
                          'Balloon crew',
                        ),
                        _roleChip(
                          FlightRole.chaseDriver,
                          Icons.directions_car,
                          'Driver',
                        ),
                        _roleChip(
                          FlightRole.chaseCrew,
                          Icons.groups_2_outlined,
                          'Chase crew',
                        ),
                      ],
                    ),
                    if (_role.isChasing) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('repair-vehicle-label-field'),
                        controller: _vehicleLabelController,
                        maxLength: 32,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Chase vehicle',
                          helperText:
                              'Use the same name as crewmates in this vehicle.',
                          counterText: '',
                        ),
                      ),
                    ],
                  ],
                  if (widget.controller.errorMessage case final message?) ...[
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('confirm-flight-assignment'),
                    onPressed: widget.controller.busy ? null : _submit,
                    icon: widget.controller.busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _legacyCreator
                          ? 'Restore pilot view'
                          : 'Continue as ${_role.label}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _roleChip(FlightRole role, IconData icon, String label) => ChoiceChip(
    key: Key('repair-role-${role.name}'),
    selected: _role == role,
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onSelected: (_) => setState(() => _role = role),
  );

  Future<void> _submit() => widget.controller.repairFlightAssignment(
    role: _legacyCreator ? FlightRole.pilot : _role,
    vehicleLabel: _vehicleLabelController.text,
  );
}
