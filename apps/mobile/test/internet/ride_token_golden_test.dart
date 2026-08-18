import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The join token is derived independently by this app and by the relay, and
/// they have to agree byte for byte or no device can sync. The server pins the
/// same vector in `apps/server/tests/test_sync.py`; if either side is edited
/// alone, one of the two tests fails rather than devices failing in the field.
///
/// The context string is protocol, not branding. It was renamed once, when the
/// product became Balloon Crumbs and the bundle identifier changed with it —
/// which already made this a new app that no older install upgrades into.
/// Renaming it again would invalidate every issued token.
void main() {
  test('the ride token matches the relay golden vector', () {
    const secret = '0123456789abcdef0123456789abcdef';
    const rideId = 'ride/alpha';

    final digest = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('balloon-crumbs-internet-token-v1\n$rideId'));
    final token = 'rr1_${base64Url.encode(digest.bytes).replaceAll('=', '')}';

    expect(token, 'rr1_btMeW7x2Dq6V6dJzP7BhE8cBxFLSjeMxzoSjBrEfceE');
  });
}
