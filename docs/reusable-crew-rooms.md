# Reusable crew rooms

Status: **implemented for the private tester relay**

Ticket: [#71](https://github.com/osholt/balloon-crumbs/issues/71)

## What a room is

A crew room is a persistent, memorable label for a regular balloon recovery
team. `TUCKER` can be opened again on another day, but it is not a flight code
and it is never accepted as proof of access.

Every launch beneath a room has a fresh operation ID, six-digit flight code,
event journal, invitation secret, relay credential and retention window. Starting
a fresh operation rotates the private invitation and prevents old tracks or
events appearing in the new flight.

## Joining and returning

- The owner creates a 5–12 character alphanumeric alias while creating a normal
  private group flight.
- The flight QR always contains the current operation bootstrap, so a nearby
  device can still join the flight while the internet relay is unavailable.
- When online, the same QR also carries a single current room invitation. A new
  device exchanges it for its own returning-device credential.
- A returning device keeps that credential in platform secure storage and can
  open the current room operation without entering the human alias again.
- An owner can rename the room, transfer ownership, revoke a returning device or
  delete the room. Transfer, revocation and deletion require an explicit
  confirmation in the app.

If online room enrolment fails after an offline QR join, the device remains in
the current flight but does not silently gain returning access. It must scan a
current invitation again when connectivity is restored.

## Authority and privacy model

The relay deliberately exposes only generic POST endpoints under
`/api/v1/crew-rooms/`; aliases and credentials do not appear in URL paths or
ordinary access logs. Missing rooms, guessed aliases and invalid device
credentials return the same bounded response. Attempts are rate limited.

At rest on the relay:

- aliases and device profiles are encrypted;
- alias and device lookup values use namespace-separated keyed blind indexes;
- returning-device credentials and room invitation tokens are stored only as
  one-way token hashes;
- the current operation bootstrap is encrypted with room-scoped associated
  data; and
- exact device identifiers and membership profiles are not stored in cleartext.

On a phone, returning credentials are isolated in `FlutterSecureStorage` rather
than the ordinary session preferences. Existing account-free flight membership,
event authentication and encrypted relay retention continue to apply to each
fresh operation.

The room owner can see the encrypted profile names of enrolled devices because
they need that information to transfer or revoke access. No public room lookup,
roster, discovery feed or account directory exists.

## Revocation and retention

Revocation prevents the device credential opening the room or accessing later
operations. It does not remotely erase a current flight already bootstrapped on
that device; that flight remains governed by its own credential and normal
retention window. Starting a fresh operation rotates the room invitation, so a
previous QR cannot enrol another device into the next flight.

Deleting a room revokes all future returning access. It does not claim to remove
copies of a still-retained operation from participant devices. Expiring an
operation hides it from room-open responses without deleting the room alias or
returning membership.

## Verification evidence

Automated coverage exercises:

- two isolated operations under `TUCKER` with invitation rotation;
- rejection of an alias without private authority;
- first-time QR enrolment and returning-device access;
- encrypted/keyed server storage and generic request paths;
- rename, ownership transfer, revocation and deletion;
- expired-operation handling and request rate limits;
- secure mobile persistence and corrupt-state removal; and
- backward-compatible offline QR parsing and operation join.

The user-facing reachability test also keeps the optional reusable-room field and
its “alias is not a password” explanation discoverable in group-flight setup.
