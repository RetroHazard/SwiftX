#!/bin/bash
# SwiftX - screenshot capture and sharing for macOS
# Copyright (c) 2026 RetroHazard
# Licensed under GPL v3 - see /LICENSE
#
# CalVer helper. SwiftX versions are YYYY.M.N: release year, release month
# (unpadded), and a counter that increments per release within that month —
# 2026.7.1, 2026.7.2, 2026.12.1, 2027.1.1. The next version is derived from
# the calendar and the existing v* release tags, so nothing needs bumping in
# PRs; the VERSION file and the cask/site always hold the LAST RELEASED
# version and are rewritten by release.yml after each publish.
#
# Usage:
#   Scripts/version.sh next            print the version the next release gets
#   Scripts/version.sh apply <x.y.z>   write <x.y.z> to the VERSION file
#   Scripts/version.sh check           verify all version locations agree
set -euo pipefail
cd "$(dirname "$0")/.."

next_version() {
    # Tags must be present; a shallow CI checkout computes N wrong.
    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
        echo "error: shallow clone — checkout with fetch-depth: 0 so release tags are visible" >&2
        exit 1
    fi
    local year month count
    year=$(date -u +%Y)
    month=$(date -u +%m | sed 's/^0//')   # unpadded, portable (BSD date lacks %-m)
    count=$(git tag -l "v$year.$month.*" | wc -l | tr -d '[:space:]')
    echo "$year.$month.$((count + 1))"
}

apply_version() {
    local version="$1"
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "error: '$version' is not a valid x.y.z version" >&2
        exit 1
    fi
    printf '%s\n' "$version" > VERSION
    echo "VERSION set to $version"
}

check_versions() {
    local file cask site pkg
    file=$(tr -d '[:space:]' < VERSION)
    cask=$(sed -nE 's/^  version "([^"]+)".*/\1/p' Casks/swiftx.rb | head -1)
    site=$(sed -nE 's/^const version = "([^"]+)";.*/\1/p' site/src/lib/content.ts | head -1)
    pkg=$(sed -nE 's/^  "version": "([^"]+)",.*/\1/p' site/package.json | head -1)

    if ! [[ "$file" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "error: VERSION file holds '$file', not a valid x.y.z version" >&2
        exit 1
    fi
    if [ -z "$cask" ] || [ -z "$site" ] || [ -z "$pkg" ]; then
        echo "error: could not read a version from the cask, site content.ts or site package.json" >&2
        exit 1
    fi
    if [ "$file" != "$cask" ] || [ "$file" != "$site" ] || [ "$file" != "$pkg" ]; then
        echo "error: version locations disagree: VERSION=$file cask=$cask site=$site package.json=$pkg" >&2
        echo "       release.yml owns all of them; they must move together" >&2
        exit 1
    fi
    echo "All version locations agree: $file"
}

case "${1:-}" in
    next)  next_version ;;
    apply) apply_version "${2:?usage: version.sh apply <x.y.z>}" ;;
    check) check_versions ;;
    *)
        echo "usage: Scripts/version.sh next | apply <x.y.z> | check" >&2
        exit 2
        ;;
esac
