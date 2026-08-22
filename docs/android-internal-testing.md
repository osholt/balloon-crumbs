# Android internal testing

Balloon Crumbs follows Tail End Charlie's release path: one manual
**Android internal testing** workflow builds a signed App Bundle and uploads it
to Google Play's `internal` track. Promotion to the closed `alpha` track remains
available as an explicit future choice, but the safe default is internal only.

This is deliberately not triggered by every merge. A release is a maintainer
decision, just like the TestFlight workflow.

## One-time account setup

These are the only steps that cannot be committed to the repository:

1. In Google Play Console, create **Balloon Crumbs** with package name
   `dev.osholt.ballooncrumbs`. The package name cannot be changed after the
   first upload. Enrol it in Play App Signing.
2. Complete Play Console's required app-content and testing declarations. A
   bundle can upload before every store-listing field is finished, but Play may
   block a testing-track rollout until its required declarations are complete.
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
6. Add the intended tester list to **Internal testing**, and keep managed
   publishing off unless every release will also be published manually in the
   Console.

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
| `BALLOON_CRUMBS_OPENAIP_API_KEY` | OpenAIP third-party application key for the advisory airspace layer |

On macOS, `base64 -i balloon-crumbs-upload.jks | pbcopy` copies the first value
without writing another file. Never commit the keystore, passwords, or JSON.
The OpenAIP key is compiled into the tester app because OpenAIP's tile API is
designed for map clients; keep it in Actions secrets so it is absent from the
repository and can be rotated independently.

Repository variables:

| Variable | Purpose |
| --- | --- |
| `BALLOON_CRUMBS_API_BASE_URL` | Required tester relay base: `https://balloon-crumbs.pages.dev/api` |
| `BALLOON_CRUMBS_FIREBASE_API_KEY` | Android Firebase configuration |
| `BALLOON_CRUMBS_FIREBASE_PROJECT_ID` | Android Firebase configuration |
| `BALLOON_CRUMBS_FIREBASE_MESSAGING_SENDER_ID` | Android Firebase configuration |
| `BALLOON_CRUMBS_FIREBASE_ANDROID_APP_ID` | Android Firebase configuration |

Push is enabled only when all four Firebase variables are present. Tester email
configuration is also optional and is documented in the workflow's variable
names; the default release mode is `dry-run`, so no mail can be sent during the
first setup run.

Android App Links are verified against the Play app-signing certificate in
`apps/planner/.well-known/assetlinks.json`. Use Play Console's generated Digital
Asset Links statement when the app-signing key changes; the upload-key
fingerprint is not sufficient for Play-installed builds.

## Releasing

Run **Android internal testing** from the Actions tab, normally with:

- `promote_to: none`
- `notification_mode: dry-run` until the rendered mail is approved
- an explicit `build_number` if any App Bundle has ever been uploaded outside
  this workflow

With no explicit build number, the workflow adds its GitHub run number to the
build in `pubspec.yaml`; the first run therefore starts above the inherited
`+22` baseline. Google Play version codes must be unique and greater than every
version already served to a user. If Play is ahead, run **Play track status**,
choose a number above the highest reported code, and pass it explicitly.

After a release:

1. Run **Play track status** and confirm the version code is on `internal`.
2. Open the opt-in page on a physical Android phone using a tester account.
3. Install/update, then confirm **Settings -> About & build** shows the same
   version code and `Play internal testing`.

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

The workflow defaults to `none`, which means internal only. Its future-facing
`alpha` choice is always explicit; it does not offer `beta`, because that would
make a private tester build joinable as open testing.
