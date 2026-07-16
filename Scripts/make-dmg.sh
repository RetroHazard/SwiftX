#!/bin/bash
# SwiftX - screenshot capture and sharing for macOS
# Copyright (c) 2026 RetroHazard
# Licensed under GPL v3 - see /LICENSE.txt
#
# Packages an already-built build/SwiftX.app into a compressed, drag-to-install
# DMG for the Homebrew cask. This ONLY packages — run Scripts/make-app.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP="build/SwiftX.app"
DMG="build/SwiftX-$VERSION.dmg"

[ -d "$APP" ] || { echo "error: $APP not found — run Scripts/make-app.sh first" >&2; exit 1; }

# Stage the app next to an /Applications symlink so the mounted DMG shows the
# familiar drag-to-install layout. hdiutil (stdlib) handles this; no create-dmg.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "SwiftX" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "Built $DMG"
# sha256 goes straight into Casks/swiftx.rb
shasum -a 256 "$DMG"
