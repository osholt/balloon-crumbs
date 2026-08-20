import 'package:balloon_crumbs/domain/app_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/services/planner_link_channel.dart';

void main() {
  test('accepts the production planner URL and normalises its code', () {
    expect(
      planCodeFromPlannerLink(
        'https://$appLinkHost/planner.html?code=7f3k9qrt',
      ),
      '7F3K9QRT',
    );
  });

  test('rejects other origins, paths, fragments and ambiguous codes', () {
    expect(
      planCodeFromPlannerLink('http://$appLinkHost/planner.html?code=7F3K9QRT'),
      isNull,
    );
    expect(
      planCodeFromPlannerLink(
        'https://evil.example/planner.html?code=7F3K9QRT',
      ),
      isNull,
    );
    expect(
      planCodeFromPlannerLink('https://$appLinkHost/?code=7F3K9QRT'),
      isNull,
    );
    expect(
      planCodeFromPlannerLink(
        'https://$appLinkHost/planner.html?code=7F3K9QRT#route',
      ),
      isNull,
    );
    expect(
      planCodeFromPlannerLink(
        'https://$appLinkHost/planner.html?code=AAAA&code=BBBB',
      ),
      isNull,
    );
    expect(
      planCodeFromPlannerLink(
        'https://$appLinkHost/planner.html?code=bad-code',
      ),
      isNull,
    );
  });
}
