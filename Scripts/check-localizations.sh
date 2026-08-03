#!/bin/bash
# SwiftX - screenshot capture and sharing for macOS
# Copyright (c) 2026 RetroHazard
# Licensed under GPL v3 - see /LICENSE
#
# Validates the localization tables:
#   1. every <lang>.lproj/Localizable.strings parses
#   2. every non-English table carries exactly the key set of en.lproj
#   3. every L10n.t("...") key referenced in Sources/ exists in en.lproj
# Run before sending a translation PR; CI runs it on every push.
# Uses plutil for parsing when available (macOS) and a pure-python .strings
# parser otherwise, so the check also runs on Linux.
set -euo pipefail
cd "$(dirname "$0")/.."

# comm(1) needs both inputs in the SAME collation order. python's sorted() is
# bytewise; macOS's UTF-8 locale sort is not (it reordered dotted keys around
# underscores, making comm report a key as missing AND unused at once). Force
# bytewise everywhere.
export LC_ALL=C

DIR="Sources/SharedKit/Resources"
BASE="$DIR/en.lproj/Localizable.strings"
[ -f "$BASE" ] || { echo "error: $BASE not found"; exit 1; }

keys_of() {
    python3 - "$1" <<'PY'
import re, sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

keys, i, n = [], 0, len(text)
while i < n:
    ch = text[i]
    if ch in " \t\r\n":
        i += 1
    elif text.startswith("/*", i):
        end = text.find("*/", i + 2)
        if end == -1:
            sys.exit(f"{path}: unterminated /* comment")
        i = end + 2
    elif text.startswith("//", i):
        i = text.find("\n", i)
        i = n if i == -1 else i
    elif ch == '"':
        # "key" = "value";
        def read_string(j):
            assert text[j] == '"'
            j += 1
            out = []
            while j < n:
                c = text[j]
                if c == "\\":
                    if j + 1 >= n:
                        sys.exit(f"{path}: dangling escape")
                    out.append(text[j:j + 2])
                    j += 2
                elif c == '"':
                    return "".join(out), j + 1
                else:
                    out.append(c)
                    j += 1
            sys.exit(f"{path}: unterminated string")
        key, i = read_string(i)
        m = re.match(r"\s*=\s*", text[i:])
        if not m or i + m.end() >= n or text[i + m.end()] != '"':
            sys.exit(f'{path}: expected = "value" after key "{key}"')
        i += m.end()
        _, i = read_string(i)
        m = re.match(r"\s*;", text[i:])
        if not m:
            sys.exit(f'{path}: missing ; after key "{key}"')
        i += m.end()
        keys.append(key)
    else:
        line = text.count("\n", 0, i) + 1
        sys.exit(f"{path}:{line}: unexpected character {ch!r}")

dupes = sorted({k for k in keys if keys.count(k) > 1})
if dupes:
    sys.exit(f"{path}: duplicate keys: {', '.join(dupes)}")
print("\n".join(sorted(keys)))
PY
}

STATUS=0

for f in "$DIR"/*.lproj/Localizable.strings; do
    if command -v plutil >/dev/null 2>&1; then
        plutil -lint -s "$f" >/dev/null || { echo "error: $f failed plutil -lint"; STATUS=1; }
    fi
    keys_of "$f" > /dev/null # parse + duplicate check (also runs where plutil is absent)
done

BASE_KEYS="$(keys_of "$BASE")"

for f in "$DIR"/*.lproj/Localizable.strings; do
    [ "$f" = "$BASE" ] && continue
    if ! diff <(printf '%s\n' "$BASE_KEYS") <(keys_of "$f") > /tmp/l10n-key-diff 2>&1; then
        echo "error: $f key set differs from en.lproj (< only in en, > only in $f):"
        grep '^[<>]' /tmp/l10n-key-diff
        STATUS=1
    fi
done

# Keys referenced in code but absent from the English table. Only literal
# keys are checkable; L10n.t(variable) call sites are skipped by nature.
MISSING="$(grep -rhoE 'L10n\.(t|has)\("[^"]+"' Sources \
    | sed -E 's/.*"([^"]+)"?$/\1/' | sort -u \
    | comm -23 - <(printf '%s\n' "$BASE_KEYS"))" || true
if [ -n "$MISSING" ]; then
    echo "error: keys used in code but missing from en.lproj:"
    printf '%s\n' "$MISSING"
    STATUS=1
fi

# Unused keys are reported but do not fail the build: keys may be referenced
# dynamically (e.g. "hotkey.\(rawValue)").
UNUSED="$(printf '%s\n' "$BASE_KEYS" \
    | comm -23 - <(grep -rhoE 'L10n\.(t|has)\("[^"]+"' Sources \
        | sed -E 's/.*"([^"]+)"?$/\1/' | sort -u))" || true
if [ -n "$UNUSED" ]; then
    echo "note: keys in en.lproj with no literal L10n.t reference (may be dynamic):"
    printf '%s\n' "$UNUSED" | sed 's/^/  /'
fi

if [ "$STATUS" -eq 0 ]; then
    echo "Localizations OK ($(printf '%s\n' "$BASE_KEYS" | wc -l | tr -d ' ') keys, $(ls -d "$DIR"/*.lproj | wc -l | tr -d ' ') languages)."
fi
exit "$STATUS"
