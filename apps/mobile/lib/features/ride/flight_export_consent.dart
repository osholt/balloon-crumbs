import 'package:flutter/material.dart';

enum FlightSummaryShareChoice { summaryOnly, exactFlightData }

Future<FlightSummaryShareChoice?> chooseFlightSummaryShare(
  BuildContext context,
) => showDialog<FlightSummaryShareChoice>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Include exact flight data?'),
    content: const Text(
      'The summary does not contain a location trail. Exact flight data adds '
      'the recorded positions, timestamps and altitude as GPX, KML and CSV '
      'files. An instrumented tester build may also add its opted-in diagnostic '
      'log. Anyone you send those files to can retain them.',
    ),
    actions: [
      TextButton(
        key: const Key('cancel-flight-summary-share'),
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('share-summary-without-track'),
        onPressed: () =>
            Navigator.pop(dialogContext, FlightSummaryShareChoice.summaryOnly),
        child: const Text('Summary only'),
      ),
      FilledButton(
        key: const Key('share-exact-flight-data'),
        onPressed: () => Navigator.pop(
          dialogContext,
          FlightSummaryShareChoice.exactFlightData,
        ),
        child: const Text('Include exact data'),
      ),
    ],
  ),
);

Future<bool> confirmExactFlightDataExport(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export exact flight data?'),
        content: const Text(
          'This exports precise recorded positions, timestamps and altitude. '
          'The files may reveal launch, landing and recovery locations. Only '
          'share them with someone you trust.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-exact-flight-export'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-exact-flight-export'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Export exact data'),
          ),
        ],
      ),
    ) ??
    false;
