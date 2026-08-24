import 'package:flutter_test/flutter_test.dart';
import 'package:balloon_crumbs/domain/ride_join_payload.dart';

/// A QR code is arbitrary input from a camera - anyone can print one - so every
/// bound here is checked rather than trusted (#279).
void main() {
  const secret = '0123456789abcdef0123456789abcdef';
  const joinToken = 'resolve-token-0123456789';
  const rootKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  const payload = RideJoinPayload(
    rideId: '019fb78c-4045-7213-b053-9197b4c2669f',
    rideCode: '934893',
    inviteSecret: secret,
    joinToken: joinToken,
  );

  test('round-trips', () {
    final decoded = RideJoinPayload.decode(payload.encode());

    expect(decoded.rideId, payload.rideId);
    expect(decoded.rideCode, payload.rideCode);
    expect(decoded.inviteSecret, payload.inviteSecret);
    expect(decoded.joinToken, payload.joinToken);
  });

  test('current invitation carries the authority root', () {
    const current = RideJoinPayload(
      rideId: 'ride-1',
      rideCode: '934893',
      inviteSecret: secret,
      joinToken: joinToken,
      authorityRootPublicKey: rootKey,
    );

    final decoded = RideJoinPayload.decode(current.encode());

    expect(current.encode(), startsWith('bc2:'));
    expect(decoded.authorityRootPublicKey, rootKey);
  });

  test('tolerates surrounding whitespace from a scan', () {
    expect(
      RideJoinPayload.decode('  ${payload.encode()}\n').rideCode,
      '934893',
    );
  });

  test('never puts the secret in toString', () {
    // toString reaches logs and error reports, and a ride secret has no business
    // in either.
    expect(payload.toString(), isNot(contains(secret)));
    expect(payload.toString(), isNot(contains(joinToken)));
    expect(payload.toString(), contains('934893'));
  });

  group('refuses', () {
    void expectRejected(String raw, {String? because}) {
      expect(
        () => RideJoinPayload.decode(raw),
        throwsA(isA<FormatException>()),
        reason: because,
      );
    }

    test('anything that is not one of ours', () {
      expectRejected('https://example.com/join');
      expectRejected('just some text');
      expectRejected('');
    });

    test('a future format rather than half-understanding it', () {
      // A wrong join is worse than a refused one: a rider who silently ends up in
      // a degraded session has no way to tell.
      expectRejected('tec2:934893:ride:$secret:$joinToken');
    });

    test('a malformed ride code', () {
      expectRejected('bc1:93489:ride-1:$secret:$joinToken');
      expectRejected('bc1:abcdef:ride-1:$secret:$joinToken');
      expectRejected('bc1:9348931:ride-1:$secret:$joinToken');
    });

    test('a missing ride', () {
      expectRejected('bc1:934893::$secret:$joinToken');
    });

    test('a secret too short to drive authenticated transport', () {
      // The relay, push registration and the event authenticator all check the
      // same 16-character floor. Accepting less would produce a session that looks
      // joined and silently cannot talk to anybody.
      expectRejected(
        'bc1:934893:ride-1:tooshort:$joinToken',
        because:
            'a short secret cannot authenticate, so joining would be a lie',
      );
    });

    test('a join token too short', () {
      expectRejected('bc1:934893:ride-1:$secret:short');
    });

    test('too few or too many fields', () {
      expectRejected('bc1:934893:ride-1:$secret');
      expectRejected('bc1:934893:ride-1:$secret:$joinToken:extra');
    });

    test('a malformed authority root', () {
      expectRejected('bc2:934893:ride-1:$secret:$joinToken:short');
    });
  });

  test('an invitation written under the old name still joins', () {
    // The rename from `tec1` cannot orphan an invitation that is already on a
    // QR code or in somebody's messages. The format is identical, so only the
    // label needs recognising - and every other check still has to run.
    const secret = 'invite-secret-long-enough';
    const joinToken = 'join-token-0123456789';
    final legacy = RideJoinPayload.decode(
      'tec1:934893:ride-1:$secret:$joinToken',
    );
    expect(legacy.rideCode, '934893');
    expect(legacy.rideId, 'ride-1');
    expect(legacy.inviteSecret, secret);
    expect(legacy.joinToken, joinToken);

    // Re-encoding moves it to the current name rather than preserving the old
    // one, so an invitation only ever travels backwards once.
    expect(legacy.encode(), startsWith('bc1:'));
  });

  test('the old name is accepted, not merely tolerated in place of checks', () {
    // A legacy prefix must not become a way past the bounds. If it did, an
    // attacker printing a QR code would just use the old label.
    const joinToken = 'join-token-0123456789';
    expect(
      () => RideJoinPayload.decode('tec1:93489:ride-1:short:$joinToken'),
      throwsFormatException,
    );
  });
}
