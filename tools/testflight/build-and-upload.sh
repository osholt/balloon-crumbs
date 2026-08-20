#!/usr/bin/env bash
# Build a signed App Store IPA and, if you have an API key, send it to TestFlight.
#
# This is the local path, which is how the sibling app got its first builds up:
# your Mac is already signed into Xcode with the team's Apple ID, so automatic
# signing can mint the App Store profile and no certificate, profile or
# credential has to be exported, stored or handed to CI.
#
#   tools/testflight/build-and-upload.sh              # next build number
#   tools/testflight/build-and-upload.sh 24           # a specific build number
#   tools/testflight/build-and-upload.sh 24 --no-upload
#
# Internal testers need no beta review: once the build finishes processing it
# appears for anyone in an internal group. External testing is what needs
# review, and tools/testflight/submit_external.py handles that separately.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mobile_dir="$repo_root/apps/mobile"
bundle_id="dev.osholt.ballooncrumbs"

build_number="${1:-}"
upload=true
for argument in "$@"; do
  [ "$argument" = "--no-upload" ] && upload=false
done
[ "$build_number" = "--no-upload" ] && build_number=""

if [ -z "$build_number" ]; then
  # The build number only has to be unique and increasing within the app record.
  build_number="$(awk -F'+' '/^version:/ {print $2 + 1}' "$mobile_dir/pubspec.yaml")"
  echo "No build number given; using $build_number (pubspec + 1)."
fi

case "$build_number" in
  ''|*[!0-9]*) echo "build-and-upload: build number must be digits, got '$build_number'" >&2; exit 1 ;;
esac

# Fail before a twenty-minute archive rather than after it.
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "build-and-upload: xcodebuild is unavailable. Open Xcode once, accept the licence, and check xcode-select -p." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
  echo "build-and-upload: no Apple Distribution certificate in the keychain." >&2
  echo "  Xcode > Settings > Accounts > your team > Manage Certificates > + > Apple Distribution." >&2
  echo "  Automatic signing needs the certificate locally; it cannot archive for the App Store without one." >&2
  exit 1
fi

# shellcheck disable=SC2046
export $(cd "$repo_root" && ./tools/build-identity.sh apps/mobile/pubspec.yaml testflight "$build_number" | xargs)

# Absent rather than wrong: with no relay URL the app says "Set
# BALLOON_CRUMBS_API_BASE_URL - no server traffic" on its own status card and
# syncs over nearby transport only. That is a usable internal build, so this
# warns instead of refusing, but it must never be mistaken for a relay build.
if [ -z "${BALLOON_CRUMBS_API_BASE_URL:-}" ]; then
  echo "warning: BALLOON_CRUMBS_API_BASE_URL is unset - this build cannot reach a relay." >&2
  echo "         Nearby transport still works. Export it to point at a deployed relay." >&2
fi

cd "$mobile_dir"
flutter pub get
flutter build ipa \
  --release \
  --build-name="$BALLOON_CRUMBS_APP_VERSION" \
  --build-number="$BALLOON_CRUMBS_APP_BUILD" \
  --export-options-plist=ios/ExportOptions-TestFlight.plist \
  --dart-define=BALLOON_CRUMBS_APP_VERSION="$BALLOON_CRUMBS_APP_VERSION" \
  --dart-define=BALLOON_CRUMBS_APP_BUILD="$BALLOON_CRUMBS_APP_BUILD" \
  --dart-define=BALLOON_CRUMBS_DISTRIBUTION_TRACK="$BALLOON_CRUMBS_DISTRIBUTION_TRACK" \
  --dart-define=BALLOON_CRUMBS_BUILD_TIMESTAMP="$BALLOON_CRUMBS_BUILD_TIMESTAMP" \
  --dart-define=BALLOON_CRUMBS_API_BASE_URL="${BALLOON_CRUMBS_API_BASE_URL:-}" \
  --dart-define=BALLOON_CRUMBS_PUSH_ENABLED=false \
  --dart-define=BALLOON_CRUMBS_RIDE_DIAGNOSTICS=true

ipa="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1)"
if [ -z "$ipa" ]; then
  echo "build-and-upload: no IPA was produced. The archive step's own error is above." >&2
  exit 1
fi
echo "Built $ipa (version $BALLOON_CRUMBS_APP_VERSION build $BALLOON_CRUMBS_APP_BUILD)."

if [ "$upload" = false ]; then
  echo "Skipping upload as asked."
  exit 0
fi

# One key, read from the standard location. Nothing here prints or copies it.
key_id="${APPSTORE_CONNECT_API_KEY_ID:-}"
issuer_id="${APPSTORE_CONNECT_API_ISSUER_ID:-}"
if [ -z "$key_id" ] || [ -z "$issuer_id" ]; then
  cat >&2 <<'NOKEY'

Built, not uploaded: no App Store Connect API key is configured.

Two ways on from here, both yours to do because they need your Apple account:

  Xcode, no key needed
    Open Xcode > Window > Organizer, select the archive, Distribute App >
    TestFlight Internal Only. Xcode uses the Apple ID it is already signed in
    with.

  This script, once a key exists
    App Store Connect > Users and Access > Integrations > App Store Connect API,
    create a Developer-role key, download the .p8 once and put it at
    ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 with mode 600, then:
      export APPSTORE_CONNECT_API_KEY_ID=<KEY_ID>
      export APPSTORE_CONNECT_API_ISSUER_ID=<ISSUER_ID>
NOKEY
  exit 0
fi

echo "Uploading to App Store Connect..."
xcrun altool --upload-app -f "$ipa" -t ios \
  --apiKey "$key_id" --apiIssuer "$issuer_id"

cat <<DONE

Uploaded. Apple processes the build before it appears under TestFlight, usually
a few minutes. It then shows for every internal tester with no beta review.

If this is the first build, add yourself: App Store Connect > your app >
TestFlight > Internal Testing > add an internal group, add your Apple ID.
DONE
