# Android closed testing

Balloon Crumbs follows Tail End Charlie's release path: one manual
**Android closed testing** workflow builds a signed App Bundle, uploads it to
Google Play's `internal` track, and promotes that exact bundle to the closed
`alpha` track. The upload remains on `internal` as a recovery source.

This is deliberately not triggered by every merge. A release is a maintainer
decision, just like the TestFlight workflow.

## One-time account setup

These are the only steps that cannot be committed to the repository:

1. In Google Play Console, create **Balloon Crumbs** with package name
   `dev.osholt.ballooncrumbs`. The package name cannot be changed after the
   first upload. Enrol it in Play App Signing.
2. Complete Play Console's required app-content and testing declarations. A
   bundle can upload before every store-listing field is finished, but Play may
   block a closed-track rollout until its required declarations are complete.
3. Create a dedicated upload key; do not reuse Tail End Charlie's key:

   ```bash
   keytool -genkeypair -v -keystore balloon-crumbs-upload.jks \
     -alias balloon-crumbs-upload -keyalg RSA -keysize 2048 -validity 10000
   ```

   Keep an encrypted backup. Google holds the app-signing key; this keystore is
   the replaceable upload key, but losing it still interrupts releases.
4. Create a Google Cloud service account, enable the **Google Play Android
   Developer API** in that Cloud project, and download one JSON key.
5. In Play Console's **Users and permissions**, invite the JSON key's
   `client_email`, scope it to Balloon Crumbs only, and grant **Release apps to
   testing tracks**. Creating it in Google Cloud alone gives it no Play access.
6. Create a closed-testing track named **Alpha**, add the intended tester list,
   and keep managed publishing off unless every release will also be published
   manually in the Console.

The tester opt-in page will be:
`https://play.google.com/apps/testing/dev.osholt.ballooncrumbs`.

## GitHub environment

Create an Actions environment named `android-internal` and add these environment
secrets. The repository environment is already restricted to workflow runs from
`main`:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i balloon-crumbs-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Upload keystore password |
| `ANDROID_KEY_ALIAS` | `balloon-crumbs-upload`, or the alias chosen above |
| `ANDROID_KEY_PASSWORD` | Upload-key password |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Full service-account JSON key |

On macOS, `base64 -i balloon-crumbs-upload.jks | pbcopy` copies the first value
without writing another file. Never commit the keystore, passwords, or JSON.

Optional repository variables:

| Variable | Purpose |
| --- | --- |
| `BALLOON_CRUMBS_API_BASE_URL` | HTTPS relay base URL; unset builds remain nearby/offline-only and say so |
| `BALLOON_CRUMBS_FIREBASE_API_KEY` | Android Firebase configuration |
| `BALLOON_CRUMBS_FIREBASE_PROJECT_ID` | Android Firebase configuration |
| `BALLOON_CRUMBS_FIREBASE_MESSAGING_SENDER_ID` | Android Firebase configuration |
| `BALLOON_CRUMBS_FIREBASE_ANDROID_APP_ID` | Android Firebase configuration |

Push is enabled only when all four Firebase variables are present. Tester email
configuration is also optional and is documented in the workflow's variable
names; the default release mode is `dry-run`, so no mail can be sent during the
first setup run.

## Releasing

Run **Android closed testing** from the Actions tab, normally with:

- `promote_to: alpha`
- `notification_mode: dry-run` until the rendered mail is approved
- an explicit `build_number` if any App Bundle has ever been uploaded outside
  this workflow

With no explicit build number, the workflow adds its GitHub run number to the
build in `pubspec.yaml`; the first run therefore starts above the inherited
`+22` baseline. Google Play version codes must be unique and greater than every
version already served to a user. If Play is ahead, run **Play track status**,
choose a number above the highest reported code, and pass it explicitly.

If upload succeeds but promotion fails, run **Promote Android tester release**
with that version code. It promotes the existing internal bundle and does not
rebuild it.

After a release:

1. Run **Play track status** and confirm the version code is on `alpha`.
2. Open the opt-in page on a physical Android phone using a tester account.
3. Install/update, then confirm **Settings -> About & build** shows the same
   version code and `Play closed testing (alpha)`.

The status workflow is read-only: it opens a Play edit, lists tracks, and deletes
the uncommitted edit. API success still cannot prove that a tester's phone has
received the update, so the physical-phone check remains part of the first
release setup.

## Track safety

The Console and API use confusing names:

| Console surface | API track |
| --- | --- |
| Internal testing | `internal` |
| Closed testing - Alpha | `alpha` |
| Open testing | `beta` |
| Production | `production` |

The workflow exposes only `alpha` or `none`; it does not offer `beta`, because
that would make a private tester build joinable as open testing.
