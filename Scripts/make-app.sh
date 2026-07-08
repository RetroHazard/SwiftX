#!/bin/bash
# ShareX - A program that allows you to take screenshots and share any file type
# Copyright (c) 2007-2026 ShareX Team
# Licensed under GPL v3 - see /LICENSE.txt
#
# Builds ShareX.app from the SPM executable. No Xcode project required.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"

swift build -c release

APP="build/ShareX.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/sharex "$APP/Contents/MacOS/ShareX"

# SPM resource bundle (word lists) must sit in Contents/Resources for Bundle.module lookup
if [ -d .build/release/ShareX_SharedKit.bundle ]; then
    cp -R .build/release/ShareX_SharedKit.bundle "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ShareX</string>
    <key>CFBundleIdentifier</key>
    <string>com.getsharex.sharex-macos</string>
    <key>CFBundleName</key>
    <string>ShareX</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>ShareX URL Scheme</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>sharex</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Sign with a real identity when available: TCC anchors grants to the cert chain,
# so permissions survive rebuilds. Ad-hoc fallback pins to the binary's CDHash,
# which invalidates grants on EVERY rebuild (tccutil reset + re-grant needed).
# Developer ID signing + notarization lands in Phase 11.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Signed as: ${IDENTITY:-ad-hoc}"

echo "Built $APP"

if pgrep -xq ShareX; then
    echo "warning: a ShareX instance is still running and will NOT pick up this build."
    echo "         restart it with: pkill -x ShareX && open $APP"
fi
