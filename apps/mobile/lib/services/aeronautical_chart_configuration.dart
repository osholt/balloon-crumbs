enum AeronauticalTileScheme {
  xyz('xyz'),
  tms('tms');

  const AeronauticalTileScheme(this.mapLibreValue);

  final String mapLibreValue;
}

/// The selected, timestamped advisory aeronautical chart.
///
/// OpenAIP is deliberately presented as an advisory community layer. UK
/// temporary restrictions and NOTAMs still require an official briefing, and a
/// tester build stops rendering the layer once its configuration is stale.
class AeronauticalChartConfiguration {
  const AeronauticalChartConfiguration({
    this.tileUrlTemplate = '',
    this.providerName = '',
    this.attribution = '',
    this.effectiveAt,
    this.expiresAt,
    this.limitations = '',
    this.tileScheme = AeronauticalTileScheme.xyz,
  });

  factory AeronauticalChartConfiguration.openAip({
    required String apiKey,
    required DateTime? configuredAt,
  }) {
    final key = apiKey.trim();
    final configured = configuredAt?.toUtc();
    return AeronauticalChartConfiguration(
      tileUrlTemplate: key.isEmpty
          ? ''
          : 'https://api.tiles.openaip.net/api/data/openaip/'
                '{z}/{x}/{y}.png?apiKey=${Uri.encodeQueryComponent(key)}',
      providerName: 'openAIP',
      attribution: '© openAIP contributors · CC BY-NC 4.0',
      effectiveAt: configured,
      expiresAt: configured?.add(const Duration(days: 28)),
      limitations:
          'Advisory community data. It may be incomplete or omit current '
          'NOTAMs and temporary restrictions. Verify the official NATS AIS '
          'briefing before flight. Not for primary navigation.',
      tileScheme: AeronauticalTileScheme.tms,
    );
  }

  factory AeronauticalChartConfiguration.fromEnvironment() =>
      AeronauticalChartConfiguration.openAip(
        apiKey: const String.fromEnvironment('BALLOON_CRUMBS_OPENAIP_API_KEY'),
        configuredAt: DateTime.tryParse(
          const String.fromEnvironment('BALLOON_CRUMBS_BUILD_TIMESTAMP'),
        ),
      );

  final String tileUrlTemplate;
  final String providerName;
  final String attribution;
  final DateTime? effectiveAt;
  final DateTime? expiresAt;
  final String limitations;
  final AeronauticalTileScheme tileScheme;

  bool get usesTms => tileScheme == AeronauticalTileScheme.tms;

  bool get isComplete =>
      tileUrlTemplate.isNotEmpty &&
      tileUrlTemplate.contains('{z}') &&
      tileUrlTemplate.contains('{x}') &&
      tileUrlTemplate.contains('{y}') &&
      providerName.isNotEmpty &&
      attribution.isNotEmpty &&
      limitations.isNotEmpty &&
      effectiveAt != null &&
      expiresAt != null &&
      expiresAt!.isAfter(effectiveAt!);

  bool isCurrentAt(DateTime now) {
    if (!isComplete) return false;
    final utc = now.toUtc();
    return !utc.isBefore(effectiveAt!) && utc.isBefore(expiresAt!);
  }

  String statusLabelAt(DateTime now) {
    if (!isComplete) return 'AIRSPACE UNAVAILABLE';
    if (!isCurrentAt(now)) return 'AIRSPACE STALE';
    return 'AIRSPACE · $providerName';
  }

  String explanationAt(DateTime now) {
    if (!isComplete) {
      return 'No licensed, dated aeronautical chart source is configured. '
          'Check the current official AIP and NOTAM briefing before flight.';
    }
    final validity =
        'Configured ${_date(effectiveAt!)}; refresh by ${_date(expiresAt!)} UTC.';
    if (!isCurrentAt(now)) {
      return '$providerName chart configuration is stale. $validity '
          'It is hidden until refreshed. $limitations';
    }
    return '$providerName. $validity $limitations';
  }

  static String _date(DateTime value) {
    final utc = value.toUtc();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }
}
