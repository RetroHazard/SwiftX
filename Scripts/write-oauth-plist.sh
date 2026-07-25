#!/bin/bash
# SwiftX - screenshot capture and sharing for macOS
# Copyright (c) 2026 RetroHazard
# Licensed under GPL v3 - see /LICENSE.txt
#
# Writes Resources/OAuthApps.plist (git-ignored) from environment variables so
# release builds ship with working OAuth destinations baked in. Run by the
# release workflow before make-app.sh; harmless to run locally.
#
# Variables (all optional — a provider with no client ID is simply omitted,
# which leaves that destination disabled in the app):
#   OAUTH_GOOGLE_CLIENT_ID / OAUTH_GOOGLE_CLIENT_SECRET
#       One Google Cloud "Desktop app" OAuth client, used for BOTH the
#       GoogleDrive and YouTube provider entries (enable the Drive API and the
#       YouTube Data API on the same project). Google desktop clients ship a
#       semi-public secret — same model as upstream ShareX.
#   OAUTH_ONEDRIVE_CLIENT_ID
#       Azure app registration (public client, PKCE). No secret — OneDrive
#       deliberately gets an empty ClientSecret.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Resources/OAuthApps.plist"
PB=/usr/libexec/PlistBuddy
rm -f "$OUT"

add_provider() { # <ProviderID> <client-id> <client-secret>
    "$PB" -c "Add :$1 dict" \
          -c "Add :$1:ClientID string $2" \
          -c "Add :$1:ClientSecret string $3" "$OUT" >/dev/null
}

COUNT=0
if [ -n "${OAUTH_GOOGLE_CLIENT_ID:-}" ]; then
    add_provider GoogleDrive "$OAUTH_GOOGLE_CLIENT_ID" "${OAUTH_GOOGLE_CLIENT_SECRET:-}"
    add_provider YouTube "$OAUTH_GOOGLE_CLIENT_ID" "${OAUTH_GOOGLE_CLIENT_SECRET:-}"
    COUNT=$((COUNT + 2))
fi
if [ -n "${OAUTH_ONEDRIVE_CLIENT_ID:-}" ]; then
    add_provider OneDrive "$OAUTH_ONEDRIVE_CLIENT_ID" ""
    COUNT=$((COUNT + 1))
fi

if [ "$COUNT" -eq 0 ]; then
    echo "note: no OAuth client IDs in the environment — $OUT not written," >&2
    echo "      OAuth destinations will be disabled in this build" >&2
    exit 0
fi

plutil -lint "$OUT" >/dev/null
echo "Wrote $OUT ($COUNT provider entries)"
