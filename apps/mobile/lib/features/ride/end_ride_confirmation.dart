import 'package:flutter/material.dart';

import '../../controllers/ride_controller.dart';

/// The one confirmation for ending a ride, wherever it is reached from.
///
/// Ending a ride is the app's most destructive action — it stops the group, not
/// just this phone. It used to be offered independently by the ride menu and
/// dashboard header, with different dialogs saying different things (#306).
///
/// The two were not merely worded differently. Only the ride menu's told the
/// leader whether the ride could be resumed, including the sentence "this
/// action cannot be undone for the group" when the relay cannot carry a reopen.
/// Only the dashboard's offered to share the summary first. **So whether a
/// leader learned that ending the ride was irreversible depended on which
/// button they happened to press.**
///
/// This is the union of the two, not the intersection: nothing either of them
/// said was lost. The consolidation now routes the map and Ride actions through
/// one combined Leave-or-end decision before this confirmation.
/// Whether this rider may end the ride for everyone.
///
/// One named decision for every surface that offers it, because there were
/// three separate expressions of it and two were wrong: `RideController.endRide`
/// and the ride menu agreed on `isLocalRideLeader`, while the shell's end-ride
/// guard and the map's exit dialog each re-derived it and disagreed. End ride
/// did nothing at all, and LEAVE showed the follower's dialog with no "End for
/// everyone" (#306).
bool canEndRideForEveryone(RideController controller) =>
    controller.isLocalRideLeader;

Future<bool> confirmEndRide(
  BuildContext context, {
  required RideController controller,
  required bool relayCanCarryReopen,
  Future<void> Function()? onShareSummary,
}) async {
  // Offering an action and then silently refusing it is worse than not
  // offering it; see [canEndRideForEveryone].
  if (!canEndRideForEveryone(controller)) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('End this flight?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            endRideConsequence(
              relayCanCarryReopen: relayCanCarryReopen,
              isSolo: !controller.coordinationMode.isGroup,
            ),
          ),
        ],
      ),
      actions: [
        if (onShareSummary != null)
          TextButton.icon(
            key: const Key('end-ride-share-summary'),
            onPressed: () => onShareSummary(),
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('Share summary'),
          ),
        TextButton(
          key: const Key('cancel-end-ride'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-end-ride'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('End flight'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return false;
  await controller.endRide();
  return true;
}

/// What ending the ride actually does, in one place so the two entry points
/// cannot disagree about whether it can be undone.
///
/// The irreversibility sentence is the half that was missing from the dashboard
/// dialog, and it is the half a leader needs most.
String endRideConsequence({
  required bool relayCanCarryReopen,
  bool isSolo = false,
}) {
  // A solo ride has no group to end it for and no other phones to fail to
  // resume it on. Saying so anyway told a rider alone on a road that they were
  // about to affect people who were not there (#362).
  if (isSolo) {
    return 'This ends your flight. Location sharing stops on this phone, and '
        'relay recovery stays available for final queued events until you '
        'file the ended flight.\n\n'
        '${relayCanCarryReopen ? 'You can resume it within 24 hours without changing the flight code.' : 'This relay cannot resume an ended flight. This action cannot be undone.'}';
  }
  return 'This ends the group flight for everyone. Location sharing stops on '
      'this phone, and relay recovery stays available for final queued events '
      'until you file the ended flight.\n\n'
      '${relayCanCarryReopen ? 'You can resume it within 24 hours without changing the flight code.' : 'This relay cannot resume an ended flight on the other phones. This action cannot be undone for the group.'}';
}
