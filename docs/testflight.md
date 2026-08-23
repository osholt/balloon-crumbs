# Getting Balloon Crumbs onto TestFlight

Internal testing needs **no beta review**: once Apple finishes processing an
upload it appears for everyone in an internal group, usually within minutes.
External testing needs beta review; the CI workflow can assign the processed
build to an external group and submit that review through App Store Connect's
API, following the release path used by Tail End Charlie.

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

The local uploader also requires `BALLOON_CRUMBS_OPENAIP_API_KEY` in its
environment and passes it as a `--dart-define`, matching the GitHub workflow.
Keep it transient or in a credential store; never write it into this repository.

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

The build number must be unique and increasing within the app record, and nothing
else. Apple reserves one permanently the moment it accepts an upload, and refuses
a repeat with an error that never mentions build numbers.

So nothing guesses. `tools/testflight/next_build_number.py` asks App Store
Connect for the highest build against the bundle ID and adds one, and both the
local script and CI call it — which is why a number cannot be spent twice by
uploading from a laptop and then from CI. Pass a number explicitly to override.

With no API key configured the local script falls back to the pubspec's `+N`
plus one, says out loud that the number may already be taken, and prints the
one-line command to record the key ID and issuer ID in
`~/.config/balloon-crumbs/testflight.env` so it never has to ask again.

`manageAppVersionAndBuildNumber` is deliberately `false` in the export options so
Xcode cannot quietly substitute a different number from the one the release notes
name.

The version inherited from Tail End Charlie is `1.0.1+22`, and builds 23 and 24
are already spent — so the pubspec is behind reality, which is exactly the drift
that made asking Apple the better answer.

## Relay

Tester builds require `BALLOON_CRUMBS_API_BASE_URL` to be
`https://balloon-crumbs.pages.dev/api`. The `/api` suffix is part of the relay
base: mobile clients append `/v1/...` paths to it. The release workflow rejects
an empty value or a URL without that suffix so a build cannot silently ship with
broken ride and plan-code lookups.

## CI

`.github/workflows/testflight.yml`, run from the Actions tab. It imports the
signing material into a temporary keychain, archives, checks the result, uploads,
and keeps the IPA as an artefact either way.

Deliberately **workflow_dispatch only**. Uploading on every merge would spend a
build number per commit and put half-finished work in front of a tester, and the
concurrency group means two runs cannot race for the same number. Add a `push`
trigger if that turns out to be what you want.

### Secrets it needs

Create these once, under Settings → Secrets and variables → Actions:

| secret | what |
| --- | --- |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | an Apple Distribution `.p12`, base64 |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | its export password |
| `APPLE_APPSTORE_PROFILE_BASE64` | an App Store provisioning profile, base64 |
| `APPLE_CI_KEYCHAIN_PASSWORD` | any random string, for the temporary keychain |
| `APPSTORE_CONNECT_API_KEY_ID` | the Developer-role key's ID |
| `APPSTORE_CONNECT_API_ISSUER_ID` | the account's issuer ID |
| `APPSTORE_CONNECT_API_PRIVATE_KEY_BASE64` | that key's `.p8`, base64 |
| `APPSTORE_CONNECT_REVIEW_API_KEY_ID` | the App Manager-role review key's ID |
| `APPSTORE_CONNECT_REVIEW_API_ISSUER_ID` | the review key account's issuer ID |
| `APPSTORE_CONNECT_REVIEW_API_PRIVATE_KEY_BASE64` | the review key's `.p8`, base64 |
| `BALLOON_CRUMBS_OPENAIP_API_KEY` | OpenAIP third-party application key for the advisory airspace layer |

Set the `BALLOON_CRUMBS_API_BASE_URL` **variable** (not a secret) to
`https://balloon-crumbs.pages.dev/api`. Set
`BALLOON_CRUMBS_IOS_EXTERNAL_TESTER_GROUP` to the exact external TestFlight
group name.

Keep the upload and review keys separate. The routine upload key can remain at
Developer privilege; assigning an external group and creating its beta review
submission uses the separate App Manager key. The `submit_external` workflow
input defaults to true and the operation is idempotent: a retry leaves an
existing group assignment or active review submission in place.

To produce the two base64 values:

```bash
base64 -i Certificates.p12 | pbcopy
base64 -i BalloonCrumbs_AppStore.mobileprovision | pbcopy
```

**The provisioning profile must include Associated Domains.** That capability was
added to the App ID when automatic signing first archived locally, so download
the profile *after* that — one generated earlier silently strips the `applinks`
entitlement and universal links stop working, with nothing failing until a link
is tapped on a phone. The workflow asserts the entitlement is in the signed IPA
rather than trusting this, and fails with that question if it is missing.

### Why signing is overridden on the command line

The Xcode project stays on **automatic** signing for normal local builds, because
that is what works on a Mac with an Apple ID and it means a local build needs no
exported material at all. A runner has no Apple ID, so the workflow passes
`CODE_SIGN_STYLE=Manual`, an identity, a team, and a CI-only profile variable to
`xcodebuild`. Runner's Release configuration maps that variable to
`PROVISIONING_PROFILE_SPECIFIER`; dependency resource bundles do not, because
they cannot use an application provisioning profile. With the variable unset,
the local automatic-signing path is unchanged.

The inherited setup made the profile name match in three places, and its own
runbook documented the consequence: this repository shipped a stale one — `Hot
Pursuit CarPlay Navigation App Store`, from two product names ago. CI now reads
the name out of the profile it just imported, passes it through the target-scoped
variable, and writes the export options from that, so there is no second copy to
go stale.

### Build numbers

Both paths call `tools/testflight/next_build_number.py`, which asks App Store
Connect for the highest build it holds and adds one. That is why a number cannot
be spent twice by uploading from a laptop and then from CI.

Not the GitHub run number, which Tail End Charlie uses: it is monotonic per
repository rather than per app record, and it knows nothing about builds uploaded
by hand. This repository already had that collision — the pubspec said `+22`
while Apple had already taken 23.

## Universal links

Invitation and planner links use `balloon-crumbs.tailendcharlie.app` — a
subdomain of a domain that already exists rather than one bought for this app.
Deliberately temporary: that zone is already on Cloudflare and already serves
Tail End Charlie's own association file, so standing this one up is a DNS record
and a static file rather than a certificate and a server. Moving to a Balloon
Crumbs domain later is one line in `lib/domain/app_links.dart` plus the two
files that have to agree with it.

The Dart parser, native bridges, platform declarations and hosted association
files must name the same host. A test enforces the checked-in copies
(`test/domain/app_links_test.dart`):

| where | what |
| --- | --- |
| `lib/domain/app_links.dart` | `appLinkHost`, used to build and parse links |
| `ios/Runner/{DebugProfile,Release}.entitlements` | `applinks:<host>` |
| `ios/Runner/AppDelegate.swift` | accepts incoming links from `<host>` |
| `android/app/src/main/AndroidManifest.xml` and `MainActivity.kt` | claim and accept `<host>` |
| `apps/planner/.well-known/apple-app-site-association` | `appIDs: ["UY4624PH6X.dev.osholt.ballooncrumbs"]` |
| `apps/planner/.well-known/assetlinks.json` | Play app-signing certificate and Android package |

Get any one of them wrong and the failure is silent: the link opens Safari,
which is exactly what a link that was never meant to open the app does. There is
no error to notice, only somebody saying it did nothing.

### Verifying tapped links

The custom domain is served by the planner's Cloudflare Pages project. Confirm
both platform association files are reachable directly over HTTPS with no
redirect:

```bash
curl -sSI https://balloon-crumbs.tailendcharlie.app/.well-known/apple-app-site-association
curl -sSI https://balloon-crumbs.tailendcharlie.app/.well-known/assetlinks.json
```

Ship a replacement build after changing an entitlement, manifest, native link
bridge, package identity or signing certificate. iOS and Android verify the
association when the app is installed, so an existing installation can retain
stale link handling until the corrected build is installed.

The six-digit ride code remains available alongside invitation links. Web
planner codes are separate eight-character plan codes and load a route; they do
not join a live ride.

If the Caddy stack is ever the origin instead of Cloudflare, `deploy/Caddyfile`
now serves the file with `Content-Type: application/json`. Its website block is
an explicit path allowlist that 404s everything else, so without that route the
file would ship in the image and be unreachable.
