#!/bin/bash
# SwiftX - screenshot capture and sharing for macOS
# Copyright (c) 2026 RetroHazard
# Licensed under GPL v3 - see /LICENSE
#
# Builds SwiftX.app from the SPM executable. No Xcode project required.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"

# SWIFTX_UNIVERSAL=1 (release pipeline) builds arm64 + x86_64 into one binary;
# the default single-arch build keeps local iteration fast. SPM puts
# multi-arch products under .build/apple/Products/Release instead of
# .build/release.
if [ "${SWIFTX_UNIVERSAL:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release"
else
    swift build -c release
    BIN=".build/release"
fi

APP="build/SwiftX.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/swiftx" "$APP/Contents/MacOS/SwiftX"
# browser native messaging host, launched by Chrome/Edge/Firefox
cp "$BIN/swiftx-host" "$APP/Contents/MacOS/SwiftXHost"

# SPM resource bundle (word lists) must sit in Contents/Resources for Bundle.module lookup
if [ -d "$BIN/SwiftX_SharedKit.bundle" ]; then
    cp -R "$BIN/SwiftX_SharedKit.bundle" "$APP/Contents/Resources/"
fi

# SwiftX aperture icon — regenerate with Scripts/make-icon.swift
cp Resources/SwiftX.icns "$APP/Contents/Resources/"

# GPL v3 requires conveying the license text with the program; the About
# panel's "GNU GPL v3" link opens this copy
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Baked-in OAuth app credentials, if this build has them (git-ignored). Absent
# in the open-source tree -> OAuth hosts stay unavailable until a build ships it.
if [ -f Resources/OAuthApps.plist ]; then
    cp Resources/OAuthApps.plist "$APP/Contents/Resources/OAuthApps.plist"
    echo "Bundled OAuth app credentials"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SwiftX</string>
    <key>CFBundleIconFile</key>
    <string>SwiftX</string>
    <key>CFBundleIdentifier</key>
    <string>com.retrohazard.swiftx</string>
    <key>CFBundleName</key>
    <string>SwiftX</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <!-- Must match Package.swift's platforms: [.macOS(.v14)] — SwiftX calls
         SCScreenshotManager, which does not exist before macOS 14. -->
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <!-- full ShareX attribution lives in the About pane (GPL v3 §5d notice) -->
    <string>Copyright © 2026 RetroHazard. Licensed under GPL v3.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>SwiftX records the microphone when "Record microphone" is enabled in Recording settings.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>SwiftX URL Scheme</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>swiftx</string>
                <!-- legacy scheme from before the SwiftX rename -->
                <string>sharex</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Hardened runtime (--options runtime), no App Sandbox: SwiftX runs external
# binaries (ffmpeg, the zsh that runs user Actions), writes browser native-
# messaging manifests into other apps' support dirs, and uploads user-selected
# files — all incompatible with the sandbox. The web/CLI attack surface that the
# sandbox would otherwise contain is closed in code by the untrusted-input
# boundary (see docs/macos-swift-port/SECURITY-MODEL.md). We ship NO entitlements
# exceptions, so every hardened-runtime protection (JIT, unsigned exec memory,
# library validation, debugger attach) stays at its most-restrictive default.
#
# Sign with a real identity when available: TCC anchors grants to the cert chain,
# so permissions survive rebuilds. Ad-hoc fallback pins to the binary's CDHash,
# which invalidates grants on EVERY rebuild (tccutil reset + re-grant needed).
#
# Identity resolution: SWIFTX_SIGN_IDENTITY env override, else the first
# "Developer ID Application" cert (distribution — required for notarization),
# else the first "Apple Development" cert (local dev), else ad-hoc. The release
# pipeline sets SWIFTX_REQUIRE_IDENTITY=1 so a missing cert fails the build
# instead of silently producing an un-notarizable artifact.
IDENTITY="${SWIFTX_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ] && [ "${SWIFTX_REQUIRE_IDENTITY:-0}" = "1" ]; then
    echo "error: SWIFTX_REQUIRE_IDENTITY=1 but no codesigning identity is available" >&2
    exit 1
fi

# notarization requires a secure timestamp; ad-hoc signatures can't carry one
SIGN_FLAGS=(--force --options runtime)
[ -n "$IDENTITY" ] && SIGN_FLAGS+=(--timestamp)

# nested executables must be signed before the bundle seal
codesign "${SIGN_FLAGS[@]}" --sign "${IDENTITY:--}" "$APP/Contents/MacOS/SwiftXHost"
codesign "${SIGN_FLAGS[@]}" --sign "${IDENTITY:--}" "$APP"
echo "Signed as: ${IDENTITY:-ad-hoc}"

echo "Built $APP"

# Install into /Applications and run from there. TCC keys its identity cache on
# the bundle PATH: the dev build/ path got permanently associated with the old
# com.getsharex.swiftx bundle ID during the rename, so capture requests from it
# resolve to a dead ID that never shows in System Settings. A stable install
# path resolves the current signature cleanly. Skips the copy if unwritable
# or on CI — the build/ bundle still works for everything except fresh TCC.
if [ -n "${CI:-}" ]; then
    echo "CI detected; skipping /Applications install"
    exit 0
fi
INSTALLED="/Applications/SwiftX.app"
if rm -rf "$INSTALLED" 2>/dev/null && cp -R "$APP" "$INSTALLED" 2>/dev/null; then
    echo "Installed $INSTALLED"
    LAUNCH="$INSTALLED"
else
    echo "note: could not write /Applications; run from $APP"
    LAUNCH="$APP"
fi

if pgrep -xq SwiftX; then
    echo "warning: a SwiftX instance is still running and will NOT pick up this build."
    echo "         restart it with: pkill -x SwiftX && open $LAUNCH"
fi
