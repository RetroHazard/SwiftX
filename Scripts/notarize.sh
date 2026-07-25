#!/bin/bash
# SwiftX - screenshot capture and sharing for macOS
# Copyright (c) 2026 RetroHazard
# Licensed under GPL v3 - see /LICENSE.txt
#
# Notarize + staple a DMG so Gatekeeper clears it with no warning and the cask
# needs no quarantine workaround.
#
# Notarization REQUIRES the app inside the DMG to be signed with a "Developer ID
# Application" certificate, with the hardened runtime (--options runtime —
# already set in make-app.sh) and a secure timestamp. Ad-hoc or "Apple
# Development" signed apps are rejected.
#
# Credentials, two ways:
#   CI (the release workflow): set APPLE_ID, APPLE_TEAM_ID, and
#   APPLE_APP_PASSWORD (an app-specific password) in the environment.
#
#   Local: store them once in the keychain so nothing lives on disk —
#     xcrun notarytool store-credentials swiftx-notary \
#         --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-pw>
#
# Then, per release:  Scripts/notarize.sh build/SwiftX-<version>.dmg
set -euo pipefail

DMG="${1:?usage: notarize.sh <path-to-dmg> [keychain-profile]}"
PROFILE="${2:-swiftx-notary}"

echo "Submitting $DMG to Apple's notary service (can take a few minutes)…"
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$DMG" --wait \
        --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
else
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
fi

# Staple the ticket into the DMG so it validates offline, then confirm.
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarized + stapled: $DMG"
