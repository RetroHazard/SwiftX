#!/bin/bash
# SwiftX - screenshot capture and sharing for macOS
# Copyright (c) 2026 RetroHazard
# Licensed under GPL v3 - see /LICENSE
#
# Builds SwiftX.app from the SPM executable. No Xcode project required.
set -euo pipefail
cd "$(dirname "$0")/.."

# default: the last released version (VERSION is maintained by release.yml)
VERSION="${1:-$(cat VERSION)}"

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

# Share extension. macOS populates the system-wide "Share…" menu (and System
# Settings > ... > Extensions > Sharing) from com.apple.share-services app
# extensions only — NSServices below puts SwiftX in the right-click Services
# menu, but never in the share sheet. An .appex is an ordinary bundle wrapping
# an executable whose entry point is NSExtensionMain, so SwiftPM can build it;
# only the wrapper has to be assembled here.
APPEX="$APP/Contents/PlugIns/SwiftXShare.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp "$BIN/swiftx-share" "$APPEX/Contents/MacOS/SwiftXShare"
# icon shown next to "SwiftX" in the share sheet
cp Resources/SwiftX.icns "$APPEX/Contents/Resources/"
# the extension links SharedKit, whose Bundle.module lookup resolves against
# the appex bundle rather than the app's
if [ -d "$BIN/SwiftX_SharedKit.bundle" ]; then
    cp -R "$BIN/SwiftX_SharedKit.bundle" "$APPEX/Contents/Resources/"
fi

cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SwiftXShare</string>
    <key>CFBundleIconFile</key>
    <string>SwiftX</string>
    <!-- the label the Share menu shows -->
    <key>CFBundleDisplayName</key>
    <string>SwiftX</string>
    <key>CFBundleName</key>
    <string>SwiftX</string>
    <!-- must be prefixed by the host app's identifier, and must match
         ShareInbox.extensionBundleID: the app locates the extension's sandbox
         container by this name -->
    <key>CFBundleIdentifier</key>
    <string>com.retrohazard.swiftx.share</string>
    <!-- app extensions are XPC bundles, not applications -->
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 RetroHazard. Licensed under GPL v3.</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.share-services</string>
        <!-- @objc(ShareViewController) keeps this name stable through Swift's
             module-qualified mangling -->
        <key>NSExtensionPrincipalClass</key>
        <string>ShareViewController</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <!-- What SwiftX offers to share. Counts are generous rather than
                 unlimited: TRUEPREDICATE would also volunteer SwiftX for
                 content it cannot upload. -->
            <key>NSExtensionActivationRule</key>
            <dict>
                <key>NSExtensionActivationSupportsFileWithMaxCount</key>
                <integer>100</integer>
                <key>NSExtensionActivationSupportsImageWithMaxCount</key>
                <integer>100</integer>
                <key>NSExtensionActivationSupportsMovieWithMaxCount</key>
                <integer>100</integer>
                <key>NSExtensionActivationSupportsText</key>
                <true/>
                <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
                <integer>1</integer>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
PLIST

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
    <!-- "Upload with SwiftX" in the system-wide Services context menu (Finder
         file selections and selected text). Handled by ServicesProvider; the
         first use may need enabling in System Settings > Keyboard >
         Keyboard Shortcuts > Services on older macOS versions. This is separate
         from the "Share…" menu, which SwiftXShare.appex handles. -->
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Upload with SwiftX</string>
            </dict>
            <key>NSMessage</key>
            <string>uploadFiles</string>
            <key>NSPortName</key>
            <string>SwiftX</string>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.item</string>
            </array>
            <key>NSSendTypes</key>
            <array>
                <string>public.utf8-plain-text</string>
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

# nested code must be signed before the bundle seal
codesign "${SIGN_FLAGS[@]}" --sign "${IDENTITY:--}" "$APP/Contents/MacOS/SwiftXHost"
# The appex is the one part of SwiftX that IS sandboxed — macOS requires app
# extensions to be, and this one has nothing the sandbox gets in the way of.
codesign "${SIGN_FLAGS[@]}" --entitlements Resources/ShareExtension.entitlements \
    --sign "${IDENTITY:--}" "$APPEX"
codesign "${SIGN_FLAGS[@]}" --sign "${IDENTITY:--}" "$APP"
echo "Signed as: ${IDENTITY:-ad-hoc}"

echo "Built $APP"

# Install into /Applications and run from there. TCC keys its identity cache on
# the bundle PATH, not just the signature: a dev machine that changes the
# bundle ID and rebuilds build/SwiftX.app in place at the same path can find
# that path pinned to the dead old identity, with capture requests resolving
# to nothing visible in System Settings. A fresh clone's first build has no
# such history and won't hit this, but a stable install path sidesteps it
# either way. Skips the copy if unwritable or on CI — the build/ bundle still
# works for everything except that.
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

# pluginkit discovers extensions when LaunchServices registers the bundle, which
# happens on the first launch from a stable location. Nudge it so the Share menu
# entry appears without waiting for a login cycle; -a is idempotent.
pluginkit -a "$LAUNCH/Contents/PlugIns/SwiftXShare.appex" 2>/dev/null || true
if pluginkit -m -p com.apple.share-services 2>/dev/null | grep -q com.retrohazard.swiftx.share; then
    echo "Share extension registered (Share… menu, System Settings > General > Login Items & Extensions > Sharing)"
else
    echo "note: the Share extension is not registered yet; it appears after the first launch from $LAUNCH"
fi

if pgrep -xq SwiftX; then
    echo "warning: a SwiftX instance is still running and will NOT pick up this build."
    echo "         restart it with: pkill -x SwiftX && open $LAUNCH"
fi
