/// Optional Ordnance Survey detail used only for the last part of a recovery.
///
/// The API credential never belongs here. [tileUrlTemplate] must name the
/// Balloon Crumbs relay's bounded proxy, which supplies the provider key from
/// server-side configuration. The ordinary road map remains mounted underneath
/// this raster layer, so an absent or failed tile reveals the road map rather
/// than taking the flight geometry with it.
class OsFinalApproachMapConfiguration {
  const OsFinalApproachMapConfiguration({
    this.enabled = false,
    this.tileUrlTemplate = '',
    this.attribution = defaultAttribution,
    this.minimumZoom = 13,
    this.maximumZoom = 16,
  });

  factory OsFinalApproachMapConfiguration.fromEnvironment() =>
      OsFinalApproachMapConfiguration(
        enabled: const bool.fromEnvironment(
          'BALLOON_CRUMBS_OS_FINAL_APPROACH_ENABLED',
        ),
        tileUrlTemplate: const String.fromEnvironment(
          'BALLOON_CRUMBS_OS_FINAL_APPROACH_TILE_URL',
          defaultValue:
              'https://balloon-crumbs.pages.dev/maps/os/outdoor/{z}/{x}/{y}.png',
        ),
      );

  static const defaultAttribution =
      'Contains OS data © Crown copyright and database right 2026';
  static const openGovernmentLicenceUrl =
      'https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/';
  static const apiTermsUrl = 'https://osdatahub.os.uk/support/legal/api-terms';
  static const mapErrorUrl = 'https://www.ordnancesurvey.co.uk/contact-us';

  final bool enabled;
  final String tileUrlTemplate;
  final String attribution;
  final int minimumZoom;
  final int maximumZoom;

  bool get isConfigured =>
      enabled &&
      attribution.trim().isNotEmpty &&
      minimumZoom >= 7 &&
      maximumZoom >= minimumZoom &&
      // Outdoor_3857 zooms 17–20 are Premium. Production intentionally uses
      // the free OS OpenData plan, so the app rejects a configuration that
      // could ever ask the protected relay for one of those tiles.
      maximumZoom <= 16 &&
      _hasRequiredPlaceholders(tileUrlTemplate) &&
      _isSecureHttpTemplate(tileUrlTemplate);

  /// OS Maps API coverage is Great Britain. These deliberately conservative
  /// bounds avoid offering the control in Northern Ireland or beyond the
  /// provider's advertised coverage. They are a UI guard, not a cadastral or
  /// political boundary.
  bool covers({required double latitude, required double longitude}) {
    if (latitude < 49.8 ||
        latitude > 61.0 ||
        longitude < -8.7 ||
        longitude > 1.8) {
      return false;
    }
    // A single Great Britain rectangle also contains Northern Ireland. Keep
    // the deliberately coarse UI guard from advertising GB-only tiles there.
    if (latitude >= 54.0 && latitude <= 55.5 && longitude < -5.3) {
      return false;
    }
    return true;
  }

  String get unavailableMessage => !enabled
      ? 'The optional OS final-approach map is not enabled for this build.'
      : !isConfigured
      ? 'The optional OS final-approach map is misconfigured.'
      : 'The OS final-approach map covers Great Britain only.';

  static bool _hasRequiredPlaceholders(String template) =>
      template.contains('{z}') &&
      template.contains('{x}') &&
      template.contains('{y}');

  static bool _isSecureHttpTemplate(String template) {
    final uri = Uri.tryParse(
      template
          .replaceAll('{z}', '13')
          .replaceAll('{x}', '4096')
          .replaceAll('{y}', '2724'),
    );
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }
}
