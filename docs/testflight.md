# Getting Balloon Crumbs onto TestFlight

For internal testers, which for now means the one person who needs to fly with
it. Internal testing needs **no beta review**: once Apple finishes processing an
upload it appears for everyone in an internal group, usually within minutes.
External testing is the thing that needs review, and it is not what this
document is about.

## The short version

```bash
tools/testflight/build-and-upload.sh
```

That derives the next build number, builds a signed App Store IPA with automatic
signing, and uploads it if an App Store Connect API key is configured. If no key
is configured it stops after building and tells you the Xcode Organizer route,
which needs no key at all.

Everything below is either what has to exist first, or why it is set up this way.

## What only you can do

None of this can be done from the repository, because all of it is account
access. In order:

1. **Register the App ID.** Apple Developer portal > Identifiers > + > App IDs >
   App, description `Balloon Crumbs`, explicit bundle ID
   `dev.osholt.ballooncrumbs`. Enable **Push Notifications** and nothing else —
   see "Why the entitlements shrank" below.
2. **Create the app record.** App Store Connect > Apps > + > New App, iOS,
   the bundle ID from step 1, SKU anything stable (`balloon-crumbs`), and a
   name. **The name must be unique across the whole App Store**, so if
   "Balloon Crumbs" is taken you will be told here; the display name on the
   phone comes from `CFBundleDisplayName` and does not have to match.
3. **Accept any outstanding agreements**, or the upload is rejected with an
   error that does not mention agreements.
4. **Add yourself as an internal tester.** TestFlight > Internal Testing > new
   group > add your Apple ID. Do this once; later builds appear automatically.
5. Optionally, **create an API key** so uploads do not need Xcode: Users and
   Access > Integrations > App Store Connect API > **Developer** role. The `.p8`
   downloads exactly once. Put it at
   `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, `chmod 600`, and keep
   an encrypted copy — Apple will not give it to you again.

Then:

```bash
export APPSTORE_CONNECT_API_KEY_ID=<KEY_ID>
export APPSTORE_CONNECT_API_ISSUER_ID=<ISSUER_ID>
```

A bundle ID can never be changed on an existing app record. If
`dev.osholt.ballooncrumbs` is ever renamed, that is a new App ID, a new record,
and internal testers re-added by hand — build history does not follow.

## Why signing is automatic here

The inherited `ios/ExportOptions-TestFlight.plist` used **manual** signing and
named the profile `Hot Pursuit CarPlay Navigation App Store` — a product name
from two renames ago. Manual signing existed for one reason: CarPlay
entitlements are restricted, and automatic signing will not mint a profile
carrying them.

Balloon Crumbs declares no CarPlay entitlements, so that constraint is gone with
the surfaces it belonged to (CarPlay for the chase driver is #15, still an
evaluation). Automatic signing now applies, which means no certificate to
export, no profile to download, no name to keep synchronised across three files,
and nothing secret in the repository. A stale profile name is not a soft
failure: the export dies with "No profile found", which is what that file would
have done on its first use.

`Release` also pinned `CODE_SIGN_IDENTITY = "Apple Development"`. A development
certificate cannot sign an App Store archive, so the first archive would have
failed on that too. It is removed, and automatic signing picks the distribution
certificate.

## Why the entitlements shrank

Both entitlement files claimed an Associated Domain of
`applinks:balloon-crumbs.invalid`. `.invalid` is reserved by RFC 2606 and
guaranteed never to resolve, so that entitlement could never do anything: no
universal link could ever be verified against a domain that cannot exist. It is
removed, which is also why the App ID needs only Push.

The `.invalid` host is still used in several places the app builds URLs for —
invitation links, the observer page, the GPX namespace — and those are a
separate, user-facing problem (#24). Removing a dead entitlement does not fix
them and does not pretend to.

## Build numbers

The build number must be unique and increasing within the app record, and
nothing else. `build-and-upload.sh` takes the pubspec's `+N` and adds one, or
uses a number you pass. `manageAppVersionAndBuildNumber` is deliberately
`false` in the export options so Xcode cannot quietly substitute a different
one than the number the release notes name.

The version inherited from Tail End Charlie is `1.0.1+22`. A new app record has
no build history, so starting near 22 collides with nothing — it just means the
first Balloon Crumbs build is not build 1.

## Without a relay

`BALLOON_CRUMBS_API_BASE_URL` has no default and no relay is deployed for this
app yet. A build without it is still usable: nearby transport carries the
journal between devices, and the app says `Set BALLOON_CRUMBS_API_BASE_URL - no
server traffic` on its own status card rather than looking like a broken relay.
The script warns and continues, because an honest offline build is worth having
and a silent one is not.

Export the variable to point at a deployed relay when there is one.

## CI

There is deliberately no TestFlight workflow yet. CI has no Apple ID signed
into Xcode, so it cannot use automatic signing — a workflow means exporting a
distribution `.p12`, a provisioning profile and an upload key into repository
secrets, which is real work and real key custody for a build that one person
currently installs. The local path needs none of it.

When more than one person needs builds, that trade changes. Tail End Charlie's
`testflight.yml` is the reference: temporary keychain, imported cert and
profile, manual signing, `xcrun altool` upload with a Developer-role key,
retrying once on Apple's 5xx.
