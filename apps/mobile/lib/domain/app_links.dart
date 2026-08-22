/// The one host Balloon Crumbs links use, and the paths that open the app.
///
/// This exists because the host used to be written out at four call sites, all
/// of them `balloon-crumbs.invalid` — a domain reserved by RFC 2606 and
/// guaranteed never to resolve, so every invitation link failed when tapped
/// (#24). Four copies of a wrong answer is also four places to miss when
/// changing it, which is the reason for a constant rather than a careful
/// find-and-replace.
///
/// A subdomain of an existing domain rather than one bought for this app, which
/// is deliberate and temporary. It is a Cloudflare zone that already serves
/// Tail End Charlie's own Apple App Site Association file, so standing this one
/// up is a DNS record and a static file rather than a certificate and a server.
/// Moving to a Balloon Crumbs domain later is a change to this one line, plus
/// the two places outside Dart that have to agree with it.
///
/// **Three files must name this host, and nothing enforces it but a test.**
///
///  1. here, for building and parsing links;
///  2. `ios/Runner/*.entitlements`, as `applinks:<host>`, or iOS will not offer
///     the app when a link is tapped;
///  3. `apps/planner/.well-known/apple-app-site-association`, served by that
///     host over HTTPS with no redirect, or iOS will not believe the app owns
///     it.
///
/// `test/domain/app_links_test.dart` asserts all three agree. A universal link
/// that is wrong in any one of them fails silently by opening Safari, which
/// looks exactly like a link that was never meant to open the app.
library;

/// The host that serves this app's association file.
const appLinkHost = 'balloon-crumbs.tailendcharlie.app';

/// A private flight invitation. The join code and its capability token travel in
/// the URL *fragment*, which browsers never send to a server, so the host can
/// serve this page without ever being able to read an invitation.
const rideInvitationPath = '/join.html';

/// A route planned elsewhere, opened by code in the query string.
const plannerPath = '/planner.html';

/// Whether [uri] is one of this app's links on the expected host.
///
/// Case-insensitive on the host because a pasted link may be capitalised, exact
/// on the path because these are two specific pages rather than a namespace.
bool isAppLink(Uri uri, String path) =>
    uri.scheme == 'https' &&
    uri.host.toLowerCase() == appLinkHost &&
    uri.path == path;
