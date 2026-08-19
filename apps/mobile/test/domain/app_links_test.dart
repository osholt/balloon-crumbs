import 'dart:convert';
import 'dart:io';

import 'package:balloon_crumbs/domain/app_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// A universal link needs three files to agree, and none of them can see the
/// others: the Dart constant that builds and parses links, the iOS entitlement
/// that lets the app claim the host, and the association file the host serves so
/// Apple believes the claim.
///
/// Disagreement fails silently. The link opens Safari, which is exactly what a
/// link that was never meant to open the app does, so there is no error to
/// notice - only a tester saying "it didn't do anything". That is what these
/// assert against.
void main() {
  const teamId = 'UY4624PH6X';
  const bundleId = 'dev.osholt.ballooncrumbs';

  test('the host is real, not a reserved TLD', () {
    // The bug this replaced: `balloon-crumbs.invalid`. RFC 2606 reserves
    // `.invalid` and guarantees it never resolves, so no link on it could ever
    // have opened anything, and no association file could ever be fetched.
    expect(appLinkHost, isNot(endsWith('.invalid')));
    expect(appLinkHost, isNot(endsWith('.example')));
    expect(appLinkHost, isNot(endsWith('.test')));
    expect(appLinkHost, isNot(endsWith('.localhost')));
    expect(appLinkHost, matches(RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$')));
  });

  test('both entitlement files claim exactly this host', () {
    // Debug and Release both need it: a link tapped on a development build has
    // to work too, or the feature can only ever be tested from TestFlight.
    for (final name in ['DebugProfile', 'Release']) {
      final entitlements = File(
        'ios/Runner/$name.entitlements',
      ).readAsStringSync();
      expect(
        entitlements,
        contains('<string>applinks:$appLinkHost</string>'),
        reason: '$name.entitlements does not claim $appLinkHost',
      );
    }
  });

  test('the association file names this app, and the paths the app parses', () {
    final association =
        jsonDecode(
              File(
                '../website/.well-known/apple-app-site-association',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    final details = ((association['applinks'] as Map)['details'] as List)
        .cast<Map<String, Object?>>();
    expect(details, hasLength(1));

    // Apple wants team ID and bundle ID joined, and gives no useful error when
    // it is wrong - the link simply never opens the app.
    expect(details.single['appIDs'], ['$teamId.$bundleId']);

    final components = (details.single['components'] as List)
        .cast<Map<String, Object?>>();
    final paths = components.map((component) => component['/']).toList();
    expect(
      paths,
      containsAll([rideInvitationPath, plannerPath]),
      reason: 'a path the app parses is not claimed in the association file',
    );
  });

  test('the invitation path is claimed without a query pattern', () {
    // The join code and its capability token travel in the fragment, which is
    // never sent to the host. A query pattern here would imply otherwise.
    final association =
        jsonDecode(
              File(
                '../website/.well-known/apple-app-site-association',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final components =
        ((((association['applinks'] as Map)['details'] as List).first
                    as Map)['components']
                as List)
            .cast<Map<String, Object?>>();
    final invitation = components.firstWhere(
      (component) => component['/'] == rideInvitationPath,
    );
    expect(invitation.containsKey('?'), isFalse);
  });

  test('isAppLink accepts this app own links and nothing else', () {
    expect(
      isAppLink(
        Uri.parse('https://$appLinkHost$rideInvitationPath'),
        rideInvitationPath,
      ),
      isTrue,
    );
    // Case-insensitive host: a pasted link may be capitalised.
    expect(
      isAppLink(
        Uri.parse('https://${appLinkHost.toUpperCase()}$rideInvitationPath'),
        rideInvitationPath,
      ),
      isTrue,
    );
    // Plain HTTP is not this app's link, whatever the host says.
    expect(
      isAppLink(
        Uri.parse('http://$appLinkHost$rideInvitationPath'),
        rideInvitationPath,
      ),
      isFalse,
    );
    // A lookalike host must not be honoured.
    expect(
      isAppLink(
        Uri.parse('https://evil-$appLinkHost$rideInvitationPath'),
        rideInvitationPath,
      ),
      isFalse,
    );
    expect(
      isAppLink(
        Uri.parse('https://$appLinkHost$plannerPath'),
        rideInvitationPath,
      ),
      isFalse,
    );
  });
}
