# Observer sharing and flight-data exports

Observer access is a deliberately smaller product surface than flight
membership. A watcher link can show bounded last-known state; it cannot resolve
the flight code, download the event journal, publish events, or join the crew.

## Credentials and authority

Each grant receives three independent random credentials. The relay stores only
their SHA-256 hashes:

- `om1_…` manages and revokes the grant;
- `op1_…` publishes its minimized snapshot; and
- `ro1_…` reads the snapshot.

The viewer credential is placed in the URL fragment so it is not sent in the
initial HTTP request, proxy logs, or referrer headers. Management and publisher
credentials stay in platform secure storage on the phone. Possession of the
ordinary shared flight bearer is insufficient to read, publish, or revoke a
grant.

A participant may create a personal grant for the state their own phone
publishes. A whole-flight grant additionally requires:

1. the in-app disclosure that the crew has been told;
2. a current, operation-scoped Ed25519 pilot signature over the grant scope,
   duration, precision, label, flight ID, key identity, and signing time; and
3. server verification of the signed device-authority journal, including key
   rotation, revocation, and accepted pilot handover.

This prevents a crew member who knows the shared flight code from silently
creating a view of everybody.

## Precision and content

Approximate sharing is the default. Before storage, the relay rounds latitude
and longitude to two decimal places and reports at least 1,500 metres of
uncertainty. This reduction is applied independently to personal positions,
group participants, and group route points, so a publisher cannot bypass it.

Exact last-known position is an explicit choice with separate warning and
consent text. Observer snapshots never contain the event journal, invitation
credentials, historical trails, altitude, wind, private contact data, or land
access notes. Responses name whether their precision is `reduced` or `exact`.

## Lifetime, revocation, and retention

Grants last from 30 minutes to 24 hours. Expiry denies all three credentials.
Revocation immediately denies viewing, publishing, and management, and clears
the encrypted snapshot. Scheduled relay cleanup removes expired grants and
ended-flight data within the retention bounds in
`security-privacy-field-gate.md`.

The phone retains only active grant credentials in secure storage. Expired or
revoked entries are removed. Completed-flight archives are local, opt-in
retention and can be deleted from Previous flights; deletion does not retract a
file the user already exported to another app.

## Flight-data export

Ordinary summary sharing contains no location trail. Adding exact flight data
requires a separate affirmative choice that names the privacy consequence.
Previous-flight export repeats that confirmation before opening the system
share sheet.

An exact export contains:

- GPX 1.1 for interoperable track geometry and altitude metadata;
- KML with recorded and planned/forecast lines kept distinct; and
- CSV with each telemetry row classified as `measured`, `calculated`,
  `missing`, or `rejected`.

The CSV preserves timestamps, metres, altitude source, altitude datum,
uncertainty, recording gaps, and rejected malformed samples. It excludes crew
device identifiers and invitation credentials. A missing altitude remains
blank and is never replaced with zero.

## Verification evidence

The automated evidence includes relay tests for token separation, scope
isolation, reduced-precision enforcement, pilot authorization, forged shared
bearers, expiry, revocation, retention cleanup, races, and rate limits. Mobile
tests cover secure credential persistence, scoped publishing, canonical pilot
signatures, disclosure UI, exact-export confirmation, KML separation, and all
four telemetry-quality states.

The remaining field check is deliberately manual: exercise creation,
foreground/background publication, expiry, and revocation on real iOS and
Android devices against the production TLS endpoint before treating the feature
as operationally validated.
