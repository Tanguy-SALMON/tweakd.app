#!/usr/bin/env bash
#
# build.sh — compile tweakd and wrap the SPM binary in a proper,
# menu-bar-only macOS .app bundle (correct Info.plist, AppIcon, entitlements,
# and the Finder hide-extension flag). Not sandboxed. Signed with the
# Developer ID cert when one is in the keychain, ad-hoc otherwise.
#
# Adapted from the Queried/SQLAgent build script so the same build mental
# model carries across both projects — minus the brand/Pro/Lite flavor
# machinery tweakd doesn't have.
#
# Usage:
#   scripts/build.sh               # release build, then auto-launch
#   scripts/build.sh --debug       # debug build, then auto-launch
#   scripts/build.sh --no-launch   # release build, do NOT launch
#   scripts/build.sh run           # alias for the default (build + launch)
#   scripts/build.sh --help        # show this header
#
# Flags can combine; order does not matter.
#
# Output:
#   app/build/tweakd.app             # open with `open app/build/tweakd.app`
#                                      # drag to /Applications to install
#
set -euo pipefail

# Run from app/ — NOT this script's own directory — so `swift build` finds
# Package.swift, and Resources/, VERSION and tweakd.entitlements resolve,
# regardless of where the user invoked us from. The script itself lives in
# scripts/ alongside release.sh, so everything that acts on the project is
# reachable from one place; the `cd` is what keeps that free.
cd "$(dirname "$0")/../app"

# ----- flags -----------------------------------------------------------------
CONFIG="release"
NO_LAUNCH=false

for arg in "$@"; do
    case "$arg" in
        --debug)     CONFIG="debug" ;;
        --no-launch) NO_LAUNCH=true ;;
        run)         NO_LAUNCH=false ;;   # backwards-compat alias — launch is already the default
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown argument: $arg (use --help)"; exit 1 ;;
    esac
done

# ----- config ----------------------------------------------------------------
APP_NAME="tweakd"                # bundle + executable filename; stays lowercase
                                 # so the .app path and on-disk artifacts don't move
DISPLAY_NAME="Tweakd"            # what the user reads: menu bar, Finder, About
PRODUCT_NAME="Tweakd"            # SPM target/product name (see Package.swift)
BUNDLE_ID="app.tweakd"          # reverse-DNS of tweakd.app
APP_BUNDLE="build/${APP_NAME}.app"
ICON_ICONSET="Resources/AppIcon.iconset"
ICON_FALLBACK="Resources/AppIcon.icns"
VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.1.0)"
COMMIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

# ----- kill any running instance BEFORE building ----------------------------
# So we're never running stale code mid-build, and the re-sign at the end
# can't hit "Operation not permitted" on a live bundle.
echo "==> ensuring no old ${APP_NAME} is running..."
pkill -9 "${APP_NAME}" 2>/dev/null || true
sleep 0.2

# ----- 1. compile via SPM ----------------------------------------------------
echo "==> swift build -c ${CONFIG} (v${VERSION}, commit: ${COMMIT_HASH})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${PRODUCT_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "ERROR: expected binary at ${BIN_PATH} but it isn't there."
    echo "Did the build fail? Check the output above."
    exit 1
fi

# ----- 2. wipe any previous bundle ------------------------------------------
if [[ -d "${APP_BUNDLE}" ]]; then
    echo "==> removing old ${APP_BUNDLE}"
    rm -rf "${APP_BUNDLE}"
fi

# ----- 3. assemble the .app structure ---------------------------------------
echo "==> assembling ${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Info.plist is generated (not a checked-in file) so VERSION and the git
# commit flow straight into the bundle. LSUIElement is false so the app
# also shows a Dock icon while running, alongside the menu-bar item.
cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>${DISPLAY_NAME}</string>
	<key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundleExecutable</key><string>${APP_NAME}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${VERSION}+${COMMIT_HASH}</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<key>LSUIElement</key><false/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<!-- Shown in the TCC prompt the first time Disk Cleanup asks Finder to
	     empty the trash. Required alongside the apple-events entitlement:
	     the entitlement permits the event, this string is what macOS puts in
	     the consent dialog. Omit it and the prompt never appears — the app
	     just gets denied. -->
	<key>NSAppleEventsUsageDescription</key><string>Tweakd asks Finder to empty the Trash when you run Disk Cleanup.</string>
</dict>
</plist>
PLIST

# ----- icon: compile iconset → .icns ---------------------------------------
# Source of truth is the 10-PNG iconset (regenerate the PNGs with
# `swift scripts/make_icon.swift` from the repo root). Compiling on every build means the icon
# is a derived artifact — editing the PNGs auto-propagates. `iconutil` ships
# with macOS. Fall back to the committed .icns if the iconset is missing.
if [[ -d "${ICON_ICONSET}" ]]; then
    echo "==> compiling AppIcon.icns from ${ICON_ICONSET}"
    iconutil -c icns "${ICON_ICONSET}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" \
        || { echo "WARNING: iconutil failed — using committed .icns"; cp "${ICON_FALLBACK}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" 2>/dev/null || true; }
elif [[ -f "${ICON_FALLBACK}" ]]; then
    echo "NOTE: ${ICON_ICONSET} not found — using committed ${ICON_FALLBACK}"
    cp "${ICON_FALLBACK}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
    echo "NOTE: no icon source found — app will use the generic icon."
fi

# ----- 4. codesign ----------------------------------------------------------
# Two lanes, chosen by what's in the keychain:
#
#   Developer ID Application present  ->  real signature + Hardened Runtime +
#                                         a trusted timestamp. This is the only
#                                         thing `notarytool` will accept, and
#                                         the only thing that opens on a Mac
#                                         that isn't this one.
#   nothing                           ->  ad-hoc ("-"), fine for local launch,
#                                         rejected by Gatekeeper everywhere else.
#
# --options runtime is the load-bearing flag: notarisation *requires* the
# Hardened Runtime, and it can only be turned on at signing time. See
# app/tweakd.entitlements for why the apple-events exception is the only one.
#
# Override the identity with TWEAKD_SIGN_IDENTITY=... (e.g. to force ad-hoc
# with TWEAKD_SIGN_IDENTITY=-).
SIGN_IDENTITY="${TWEAKD_SIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi

if [[ -n "${SIGN_IDENTITY}" && "${SIGN_IDENTITY}" != "-" ]]; then
    echo "==> codesign (Developer ID, hardened runtime)"
    echo "    identity: ${SIGN_IDENTITY}"
    # --timestamp contacts Apple's timestamp server, so this step needs the
    # network. A signature without one is accepted today and starts failing the
    # day the certificate expires, which is precisely the failure you cannot
    # debug two years from now — so treat a timestamp failure as fatal rather
    # than silently downgrading.
    codesign --force --sign "${SIGN_IDENTITY}" \
        --entitlements "tweakd.entitlements" \
        --options runtime \
        --timestamp \
        "${APP_BUNDLE}"
    SIGNED_MODE="developer-id"
else
    echo "==> ad-hoc codesign (no Developer ID cert found — local use only)"
    codesign --force --sign - --entitlements "tweakd.entitlements" --timestamp=none "${APP_BUNDLE}" >/dev/null 2>&1 || {
        echo "WARNING: codesign with entitlements failed; retrying without."
        codesign --force --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
    }
    SIGNED_MODE="ad-hoc"
fi

# Verify what we actually produced rather than trusting codesign's exit code:
# --strict --deep walks the whole bundle, and this is the cheapest place to
# catch a signature that will only fail later, inside notarytool.
codesign --verify --strict --deep --verbose=1 "${APP_BUNDLE}" 2>&1 | sed 's/^/    /'

# ----- 5. mark the .app extension as hidden ---------------------------------
# So Finder shows "tweakd" instead of "tweakd.app" even with
# "Show all filename extensions" enabled — matches Apple-shipped apps.
echo "==> hide .app extension in Finder"
osascript -e "tell application \"Finder\" to set extension hidden of (POSIX file \"${PWD}/${APP_BUNDLE}\" as alias) to true" >/dev/null 2>&1 || {
    echo "NOTE: couldn't set hide-extension flag (Finder may not be running)."
}

# ----- 6. launch (skipped under --no-launch) -------------------------------
if [[ "${NO_LAUNCH}" != "true" ]]; then
    echo "==> launching ${APP_BUNDLE}"
    sleep 0.3
    open "${APP_BUNDLE}"
fi

# ----- 7. report -----------------------------------------------------------
# We run with cwd=app/, but the reader is almost certainly sitting at the repo
# root — so print copy-pasteable root-relative paths, not our own cwd-relative ones.
APP_FROM_ROOT="app/${APP_BUNDLE}"
SIZE=$(du -sh "${APP_BUNDLE}" | awk '{print $1}')
echo
echo "==> built ${APP_FROM_ROOT} (${SIZE}, v${VERSION}+${COMMIT_HASH}, ${SIGNED_MODE})"
if [[ "${SIGNED_MODE}" == "ad-hoc" ]]; then
    echo "    NOTE: ad-hoc signed — Gatekeeper will refuse this on any other Mac."
fi
echo
echo "Install:        cp -R ${APP_FROM_ROOT} /Applications/"
echo "Verify bundle:  plutil -lint ${APP_FROM_ROOT}/Contents/Info.plist"
echo
