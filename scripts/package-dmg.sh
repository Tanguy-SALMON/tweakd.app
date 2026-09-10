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
#
# Output:
#   dist/Tweakd-<version>.dmg
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
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
  app/build.sh --no-launch >/dev/null
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

SIZE="$(/usr/bin/du -h "$DMG" | awk '{print $1}')"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo
echo "==> ${DMG} (${SIZE})"
echo "    sha256: ${SHA}"
echo
echo "Publish:  scripts/release-download.sh"
echo
