import 'package:balloon_crumbs/services/aeronautical_chart_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final effective = DateTime.utc(2026, 8, 6);
  final expires = DateTime.utc(2026, 9, 3);

  AeronauticalChartConfiguration chart() => AeronauticalChartConfiguration(
    tileUrlTemplate: 'https://charts.example/{z}/{x}/{y}.png',
    providerName: 'Test AIS',
    attribution: 'Test AIS chart data',
    effectiveAt: effective,
    expiresAt: expires,
    limitations: 'Check current NOTAMs. Not for primary navigation.',
  );

  test('a complete chart only renders inside its validity window', () {
    expect(chart().isCurrentAt(DateTime.utc(2026, 8, 20)), isTrue);
    expect(
      chart().isCurrentAt(effective.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(chart().isCurrentAt(expires), isFalse);
  });

  test('missing provenance is unavailable rather than partially trusted', () {
    const incomplete = AeronauticalChartConfiguration(
      tileUrlTemplate: 'https://charts.example/{z}/{x}/{y}.png',
      providerName: 'Unknown chart',
    );

    expect(incomplete.isComplete, isFalse);
    expect(
      incomplete.statusLabelAt(DateTime.utc(2026, 8, 20)),
      'AIRSPACE UNAVAILABLE',
    );
    expect(
      incomplete.explanationAt(DateTime.utc(2026, 8, 20)),
      contains('official AIP and NOTAM'),
    );
  });

  test('an expired chart is labelled stale and is not rendered', () {
    final stale = chart();
    final now = DateTime.utc(2026, 9, 4);

    expect(stale.isCurrentAt(now), isFalse);
    expect(stale.statusLabelAt(now), 'AIRSPACE STALE');
    expect(stale.explanationAt(now), contains('hidden until refreshed'));
  });

  test('OpenAIP is selected with TMS tiles and a bounded build lifetime', () {
    final configured = DateTime.utc(2026, 8, 20, 9, 30);
    final openAip = AeronauticalChartConfiguration.openAip(
      apiKey: 'key with symbols/+',
      configuredAt: configured,
    );

    expect(openAip.providerName, 'openAIP');
    expect(openAip.tileScheme, AeronauticalTileScheme.tms);
    expect(openAip.tileUrlTemplate, contains('/openaip/{z}/{x}/{y}.png'));
    expect(openAip.tileUrlTemplate, contains('apiKey=key+with+symbols%2F%2B'));
    expect(openAip.attribution, contains('CC BY-NC 4.0'));
    expect(openAip.expiresAt, configured.add(const Duration(days: 28)));
    expect(openAip.isCurrentAt(DateTime.utc(2026, 9, 1)), isTrue);
    expect(openAip.limitations, contains('NOTAMs'));
    expect(openAip.limitations, contains('Not for primary navigation'));
  });

  test('OpenAIP remains unavailable without an API key or build timestamp', () {
    expect(
      AeronauticalChartConfiguration.openAip(
        apiKey: '',
        configuredAt: DateTime.utc(2026, 8, 20),
      ).isComplete,
      isFalse,
    );
    expect(
      AeronauticalChartConfiguration.openAip(
        apiKey: 'test-key',
        configuredAt: null,
      ).isComplete,
      isFalse,
    );
  });
}
