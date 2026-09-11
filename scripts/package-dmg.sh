#!/usr/bin/env bash
#
# package-dmg.sh — wrap app/build/tweakd.app in a distributable .dmg.
#
# The build script stops at the .app bundle, which is fine for local use
# (`open app/build/tweakd.app`) but not for the website: a bare .app arrives as
# a folder, loses the hide-extension flag, and gives people nowhere to drag it.
# A disk image with an /Applications symlink is the format macOS users expect.
#
# Usage:
#   scripts/package-dmg.sh          # build the app first if needed, then package
#   scripts/package-dmg.sh --skip-build
#   scripts/package-dmg.sh --no-notarize   # skip the Apple round-trip (local test only)
#
# Notarisation
# ------------
# A .dmg that is merely signed still trips Gatekeeper on a Mac that has never
# seen it: "cannot be opened because the developer cannot be verified". The fix
# is Apple's notary service, and the sequence matters —
#
#   1. the .app is signed with Developer ID + Hardened Runtime   (scripts/build.sh)
#   2. the .dmg is built, then signed with the same identity
#   3. the .dmg is submitted to notarytool and we wait for the verdict
#   4. `stapler staple` writes the resulting ticket *into* the .dmg
#
# Step 4 is what makes the download work offline and behind captive portals:
# without a stapled ticket the receiving Mac has to reach Apple to check, and
# a first launch with no network fails. Stapling the .dmg also covers the .app
# inside it, so there is no second staple to remember.
#
# One-time setup (the credentials live in the keychain, not in this repo):
#
#   xcrun notarytool store-credentials "Tweakd" \
#     --apple-id "<your Apple ID>" \
#     --team-id "BXH6425K7L" \
#     --password "<app-specific password from appleid.apple.com>"
#
# Output:
#   dist/Tweakd-<version>.dmg   (signed, notarised, stapled)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_BUILD=false
NOTARIZE=true
# The keychain profile created by `notarytool store-credentials`. The name is
# CASE-SENSITIVE: storing "Tweakd" and asking for "tweakd" is a second, empty
# profile and a 401 that reads exactly like a wrong password. Overridable so a
# second machine or a CI box can use its own.
NOTARY_PROFILE="${TWEAKD_NOTARY_PROFILE:-Tweakd}"

for arg in "$@"; do
  case "$arg" in
    --skip-build)  SKIP_BUILD=true ;;
    --no-notarize) NOTARIZE=false ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $arg (use --help)"; exit 1 ;;
  esac
done

VERSION="$(cat app/VERSION)"
APP="app/build/tweakd.app"
DIST="dist"
DMG="${DIST}/Tweakd-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [ "$SKIP_BUILD" = false ] || [ ! -d "$APP" ]; then
  echo "==> building v${VERSION}"
  scripts/build.sh --no-launch >/dev/null
fi

[ -d "$APP" ] || { echo "ERROR: $APP not found"; exit 1; }

# Sanity: refuse to ship a bundle whose version doesn't match app/VERSION.
# Getting this wrong means the site advertises one version and hands out
# another, which is exactly the kind of drift nobody notices for weeks.
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
if [ "$BUNDLE_VERSION" != "$VERSION" ]; then
  echo "ERROR: app/VERSION says ${VERSION}, but the built bundle says ${BUNDLE_VERSION}."
  echo "       Rebuild without --skip-build."
  exit 1
fi

echo "==> staging"
mkdir -p "$DIST"
cp -R "$APP" "$STAGE/"
# The drag-to-install target. Without it the window is just a lone icon and
# people copy the app to their Downloads folder and wonder why it vanishes.
ln -s /Applications "$STAGE/Applications"

echo "==> creating ${DMG}"
rm -f "$DMG"
hdiutil create \
  -volname "Tweakd ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

# ----- sign, notarise, staple ------------------------------------------------
# Resolve the identity the same way scripts/build.sh does, so the .app inside and
# the .dmg around it are never signed by two different certificates.
SIGN_IDENTITY="${TWEAKD_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi

if [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; then
  echo
  echo "WARNING: no Developer ID Application certificate in the keychain."
  echo "         This .dmg is unsigned and un-notarised. Gatekeeper will refuse"
  echo "         it on every Mac except this one. Do NOT publish it."
  NOTARIZE=false
else
  # Refuse to notarise a .dmg wrapped around an ad-hoc .app. The notary service
  # would reject it anyway, but it does so after a two-minute upload and with a
  # log URL instead of a sentence.
  #
  # Read the signature into a variable rather than piping into `grep -q`.
  # Under `set -o pipefail` that pipeline is unreliable: grep -q exits the
  # instant it matches, codesign dies of SIGPIPE, and pipefail reports the
  # rightmost failure — so the pipeline returns 141 *because* the pattern
  # matched. The guard read a successful match as "not ad-hoc" and packaged
  # the unsigned bundle anyway.
  APP_SIG="$(codesign -dv "$APP" 2>&1 || true)"
  case "$APP_SIG" in
    *"Signature=adhoc"*|*"not signed"*|*"code object is not signed"*)
      echo "ERROR: ${APP} is not Developer ID signed (ad-hoc or unsigned)."
      echo "       Rebuild without --skip-build so scripts/build.sh signs it properly."
      exit 1
      ;;
  esac
  if ! codesign --verify --strict "$APP" 2>/dev/null; then
    echo "ERROR: ${APP} fails signature verification."
    exit 1
  fi
  echo "==> signing ${DMG}"
  echo "    identity: ${SIGN_IDENTITY}"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  codesign --verify --strict --verbose=1 "$DMG" 2>&1 | sed 's/^/    /'
fi

if [ "$NOTARIZE" = true ]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo
    echo "ERROR: no notarytool keychain profile named '${NOTARY_PROFILE}'."
    echo "       Create it once with:"
    echo
    echo "         xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
    echo "           --apple-id \"<your Apple ID>\" \\"
    echo "           --team-id \"BXH6425K7L\" \\"
    echo "           --password \"<app-specific password>\""
    echo
    echo "       Or re-run with --no-notarize (local testing only — the result"
    echo "       must not be published)."
    exit 1
  fi

  echo "==> submitting to Apple's notary service (this takes a few minutes)"
  # --wait blocks until Apple returns a verdict. Without it the script "succeeds"
  # while the submission is still queued, and we would staple nothing.
  if ! xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --timeout 30m; then
    echo
    echo "ERROR: notarisation failed. Read the actual reason with:"
    echo "         xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}"
    exit 1
  fi

  echo "==> stapling the ticket"
  xcrun stapler staple "$DMG"

  # The real check. `spctl --assess` is Gatekeeper itself, asked the same
  # question a stranger's Mac will ask on first open — a clean notarytool run
  # with a botched staple still fails here, which is the whole point.
  echo "==> Gatekeeper assessment"
  spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/    /'
  xcrun stapler validate "$DMG" 2>&1 | sed 's/^/    /'
else
  echo "==> notarisation SKIPPED"
fi

SIZE="$(/usr/bin/du -h "$DMG" | awk '{print $1}')"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo
echo "==> ${DMG} (${SIZE})"
echo "    sha256: ${SHA}"
if [ "$NOTARIZE" = true ]; then
  echo "    signed, notarised, stapled"
else
  echo "    NOT notarised — local testing only"
fi
echo
echo "Publish:  scripts/release-download.sh"
echo
