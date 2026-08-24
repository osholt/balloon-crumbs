/// Everything needed to join a ride, carried directly rather than looked up.
///
/// This is what makes an offline join possible at all (#279). Every existing join
/// path - typed code or pasted invite - ends in `RideCodeDirectory.resolve`, an
/// HTTPS call to the relay whose entire job is turning a six-digit code into
/// `{rideId, inviteSecret, resolveToken}`. So a group standing in a car park with
/// no signal cannot form a ride at all, which is precisely the situation this
/// product exists for.
///
/// A QR code has room for the relay fields and (for current invitations) the
/// authority root key, so scanning one needs no network.
///
/// ## Why not a URL
///
/// A URL would spend bytes on a scheme and host to no purpose, and would invite
/// the secret into a path or query where web-server logs and browser history can
/// see it. Making an invitation *tappable* is a separate job with its own
/// constraints (#275); this is a machine-readable payload for a camera, and is
/// deliberately not something a browser will do anything with.
///
/// ## What it exposes
///
/// The ride's invite secret, in the clear. Anyone who photographs a displayed code
/// can join the ride. That is the same exposure as a shared invite link and is
/// acceptable for a private group, but it is the reason a display of this must be
/// deliberate and short-lived rather than a screen left sitting open.
class RideJoinPayload {
  const RideJoinPayload({
    required this.rideId,
    required this.rideCode,
    required this.inviteSecret,
    required this.joinToken,
    this.authorityRootPublicKey,
    this.crewRoomId,
    this.crewRoomAlias,
    this.crewRoomInviteToken,
  });

  /// Version prefix, so a payload from a future format is **rejected** rather
  /// than half-understood. A wrong join is worse than a refused one: a rider who
  /// silently ends up in a degraded session has no way to tell.
  static const scheme = 'bc2';

  /// The same format under its old name.
  ///
  /// This was `tec1` when the app was Tail End Charlie. Accepting it is not the
  /// half-understanding the paragraph above refuses: the legacy fields and their
  /// bounds are byte-identical, so only the label differs, and every check below
  /// still runs. An invitation already printed on a QR code, or sitting in a
  /// message from an older build, still joins.
  ///
  /// New payloads are written as [scheme]. This can go once no build old enough
  /// to have written `tec1` is still installed anywhere.
  static const legacyScheme = 'bc1';
  static const inheritedScheme = 'tec1';

  /// Colon-separated because none of the fields can contain a colon: identifiers
  /// and aliases are bounded tokens, while secrets and public keys are base64url,
  /// whose alphabet is `A-Za-z0-9-_`. So splitting cannot be ambiguous, and no
  /// escaping is needed to keep the payload short.
  static const _separator = ':';

  final String rideId;
  final String rideCode;
  final String inviteSecret;
  final String joinToken;
  final String? authorityRootPublicKey;
  final String? crewRoomId;
  final String? crewRoomAlias;
  final String? crewRoomInviteToken;

  String encode() {
    final rootKey = authorityRootPublicKey;
    final base = rootKey == null
        ? [legacyScheme, rideCode, rideId, inviteSecret, joinToken]
        : [scheme, rideCode, rideId, inviteSecret, joinToken, rootKey];
    if (crewRoomId == null ||
        crewRoomAlias == null ||
        crewRoomInviteToken == null) {
      return base.join(_separator);
    }
    return [
      ...base,
      crewRoomId!,
      crewRoomAlias!,
      crewRoomInviteToken!,
    ].join(_separator);
  }

  /// Parses [raw], or throws [FormatException] with a reason a person can act on.
  ///
  /// The bounds mirror what the relay itself enforces when it serves these fields,
  /// so a payload this accepts is one the rest of the app can already handle. They
  /// are checked here rather than trusted because a QR code is arbitrary input
  /// from a camera - anyone can print one.
  static RideJoinPayload decode(String raw) {
    final parts = raw.trim().split(_separator);
    final isCurrent = parts.firstOrNull == scheme;
    final isLegacy =
        parts.firstOrNull == legacyScheme ||
        parts.firstOrNull == inheritedScheme;
    if ((!isCurrent && !isLegacy) ||
        (isCurrent && parts.length != 6 && parts.length != 9) ||
        (isLegacy && parts.length != 5 && parts.length != 8)) {
      throw const FormatException(
        'That code is not a Balloon Crumbs flight invitation.',
      );
    }
    final rideCode = parts[1];
    final rideId = parts[2];
    final inviteSecret = parts[3];
    final joinToken = parts[4];
    final authorityRootPublicKey = isCurrent ? parts[5] : null;

    if (!RegExp(r'^\d{6}$').hasMatch(rideCode)) {
      throw const FormatException('That invitation has no valid flight code.');
    }
    if (rideId.isEmpty || rideId.length > 128) {
      throw const FormatException('That invitation has no valid flight.');
    }
    // Below 16 characters the secret cannot drive authenticated transport - the
    // relay, push registration and the event authenticator all check the same
    // floor - so accepting a shorter one would produce a session that looks
    // joined and silently cannot talk to anybody.
    if (inviteSecret.length < 16 || inviteSecret.length > 512) {
      throw const FormatException(
        'That invitation is incomplete and cannot join securely.',
      );
    }
    if (joinToken.length < 16 || joinToken.length > 128) {
      throw const FormatException(
        'That invitation is incomplete and cannot join securely.',
      );
    }
    if (isCurrent &&
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(authorityRootPublicKey!)) {
      throw const FormatException(
        'That invitation has no valid device authority.',
      );
    }
    String? crewRoomId;
    String? crewRoomAlias;
    String? crewRoomInviteToken;
    if (parts.length == 8 || parts.length == 9) {
      final offset = isCurrent ? 1 : 0;
      crewRoomId = parts[5 + offset];
      crewRoomAlias = parts[6 + offset];
      crewRoomInviteToken = parts[7 + offset];
      if (crewRoomId.isEmpty || crewRoomId.length > 128) {
        throw const FormatException('That invitation has no valid crew room.');
      }
      if (!RegExp(r'^[A-Z0-9]{5,12}$').hasMatch(crewRoomAlias)) {
        throw const FormatException(
          'That invitation has no valid crew room alias.',
        );
      }
      if (!RegExp(r'^cri1_[A-Za-z0-9_-]{43}$').hasMatch(crewRoomInviteToken)) {
        throw const FormatException(
          'That invitation cannot grant returning crew access.',
        );
      }
    }
    return RideJoinPayload(
      rideId: rideId,
      rideCode: rideCode,
      inviteSecret: inviteSecret,
      joinToken: joinToken,
      authorityRootPublicKey: authorityRootPublicKey,
      crewRoomId: crewRoomId,
      crewRoomAlias: crewRoomAlias,
      crewRoomInviteToken: crewRoomInviteToken,
    );
  }

  /// Never includes the secrets. A payload's `toString` reaches logs and error
  /// reports, and a ride secret has no business in either.
  @override
  String toString() => 'RideJoinPayload(ride $rideCode)';
}
