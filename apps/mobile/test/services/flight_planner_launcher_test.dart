import 'package:balloon_crumbs/services/flight_planner_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opens the production planner with a mobile-app source marker',
    () async {
      Uri? openedUri;
      final launcher = FlightPlannerLauncher(
        openUri: (uri) async {
          openedUri = uri;
          return true;
        },
      );

      expect(await launcher.open(), isTrue);
      expect(openedUri?.scheme, 'https');
      expect(openedUri?.host, 'balloon-crumbs.pages.dev');
      expect(openedUri?.path, '/planner.html');
      expect(openedUri?.queryParameters, const {'source': 'mobile-app'});
    },
  );
}
