#!/usr/bin/env bash
#
# build.sh — compile MacTweak and wrap the SPM binary in a proper,
# menu-bar-only macOS .app bundle (correct Info.plist, AppIcon, entitlements,
# and the Finder hide-extension flag). Ad-hoc signed, not sandboxed.
#
# Adapted from the Queried/SQLAgent build script so the same build mental
# model carries across both projects — minus the brand/Pro/Lite flavor
# machinery MacTweak doesn't have.
#
# Usage:
#   Scripts/build.sh               # release build, then auto-launch
#   Scripts/build.sh --debug       # debug build, then auto-launch
#   Scripts/build.sh --no-launch   # release build, do NOT launch
#   Scripts/build.sh run           # alias for the default (build + launch)
#   Scripts/build.sh --help        # show this header
#
# Flags can combine; order does not matter.
#
# Output:
#   build/MacTweak.app                 # open with `open build/MacTweak.app`
#                                      # drag to /Applications to install
#
set -euo pipefail

# Run from the repo root so `swift build` finds Package.swift regardless of
# where the user invoked us from.
cd "$(dirname "$0")/.."

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
APP_NAME="MacTweak"
PRODUCT_NAME="MacTweak"           # SPM target/product name (see Package.swift)
BUNDLE_ID="com.tanguy.MacTweak"
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
# commit flow straight into the bundle. LSUIElement makes it menu-bar-only
# (no Dock icon), which is the whole point of MacTweak.
cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key><string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundleExecutable</key><string>${APP_NAME}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${VERSION}+${COMMIT_HASH}</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# ----- icon: compile iconset → .icns ---------------------------------------
# Source of truth is the 10-PNG iconset (regenerate the PNGs with
# `swift Scripts/make_icon.swift`). Compiling on every build means the icon
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

# ----- 4. ad-hoc sign with entitlements -------------------------------------
# Ad-hoc signature ("-") + entitlements. Enough for local launch; real
# distribution would need a Developer ID cert + notarisation.
echo "==> ad-hoc codesign with entitlements"
if [[ -f "MacTweak.entitlements" ]]; then
    codesign --force --sign - --entitlements "MacTweak.entitlements" --timestamp=none "${APP_BUNDLE}" >/dev/null 2>&1 || {
        echo "WARNING: codesign with entitlements failed; retrying without."
        codesign --force --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
    }
else
    codesign --force --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
fi

# ----- 5. mark the .app extension as hidden ---------------------------------
# So Finder shows "MacTweak" instead of "MacTweak.app" even with
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
SIZE=$(du -sh "${APP_BUNDLE}" | awk '{print $1}')
echo
echo "==> built ${APP_BUNDLE} (${SIZE}, v${VERSION}+${COMMIT_HASH})"
echo
echo "Install:        cp -R ${APP_BUNDLE} /Applications/"
echo "Verify bundle:  plutil -lint ${APP_BUNDLE}/Contents/Info.plist"
echo
