import 'package:balloon_crumbs/features/ride/flight_export_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('summary sharing does not imply consent to an exact track', (
    tester,
  ) async {
    FlightSummaryShareChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              choice = await chooseFlightSummaryShare(context);
            },
            child: const Text('Share'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Include exact flight data?'), findsOneWidget);
    expect(
      find.textContaining('positions, timestamps and altitude'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('share-summary-without-track')));
    await tester.pumpAndSettle();
    expect(choice, FlightSummaryShareChoice.summaryOnly);
  });

  testWidgets('exact export requires its own affirmative action', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              confirmed = await confirmExactFlightDataExport(context);
            },
            child: const Text('Export'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Export exact flight data?'), findsOneWidget);
    expect(find.textContaining('launch, landing and recovery'), findsOneWidget);
    expect(confirmed, isNull);

    await tester.tap(find.byKey(const Key('confirm-exact-flight-export')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
