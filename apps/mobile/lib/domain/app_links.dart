/// The one host Balloon Crumbs links use, and the paths that open the app.
///
/// This exists because the host used to be written out at four call sites, all
/// of them `balloon-crumbs.invalid` — a domain reserved by RFC 2606 and
/// guaranteed never to resolve, so every invitation link failed when tapped
/// (#24). Four copies of a wrong answer is also four places to miss when
/// changing it, which is the reason for a constant rather than a careful
/// find-and-replace.
///
/// The Cloudflare Pages product origin serves the planner and both association
/// files, so a browser hand-off never depends on an inherited product domain.
///
/// **Every link layer must name this host, and nothing enforces it but a test.**
///
///  1. here, for building and parsing links;
///  2. the iOS entitlement and native link bridge;
///  3. the Android manifest and native link bridge;
///  4. the Apple and Android association files hosted from `apps/planner`.
///
/// `test/domain/app_links_test.dart` asserts the checked-in layers agree. A link
/// that is wrong in any one of them fails silently by opening the browser or by
/// reaching the app without delivering its route code.
library;

/// The host that serves this app's association file.
const appLinkHost = 'balloon-crumbs.pages.dev';

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
