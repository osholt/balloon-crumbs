import 'package:url_launcher/url_launcher.dart';

typedef FlightPlannerUriOpener = Future<bool> Function(Uri uri);

/// Opens the production pilot planner without sending the user out of the app.
///
/// Keeping the forecast UI hosted means the app and website use the same wind
/// model, safety wording and current route-search implementation. The platform
/// browser view still gives iOS and Android an obvious close control.
class FlightPlannerLauncher {
  const FlightPlannerLauncher({this.openUri});

  static final plannerUri = Uri.https(
    'balloon-crumbs.pages.dev',
    '/planner.html',
    const {'source': 'mobile-app'},
  );

  final FlightPlannerUriOpener? openUri;

  Future<bool> open() => (openUri ?? _openInAppBrowser)(plannerUri);
}

Future<bool> _openInAppBrowser(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.inAppBrowserView);
