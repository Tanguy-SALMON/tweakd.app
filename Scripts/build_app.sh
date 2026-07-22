#!/bin/bash
#
# build_app.sh — compile MacTweak and assemble a runnable, menu-bar-only .app.
# Produces build/MacTweak.app, ad-hoc signed (no sandbox).
#
# Usage:
#   Scripts/build_app.sh          # build + bundle
#   Scripts/build_app.sh run      # build + bundle + launch
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo 0.1.0)"
BUNDLE_ID="com.tanguy.MacTweak"
APP="build/MacTweak.app"

echo "▸ Compiling release binary…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacTweak"

echo "▸ Assembling $APP (v$VERSION)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacTweak"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>MacTweak</string>
	<key>CFBundleDisplayName</key><string>MacTweak</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundleExecutable</key><string>MacTweak</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${VERSION}</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing…"
codesign --force --sign - --entitlements MacTweak.entitlements --timestamp=none "$APP" 2>/dev/null || \
codesign --force --sign - "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "run" ]]; then
  echo "▸ Launching…"
  open "$APP"
fi
