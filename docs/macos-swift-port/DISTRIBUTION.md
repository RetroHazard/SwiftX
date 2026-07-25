# SwiftX Distribution (Phase 11)

Releases are fully automated by **`.github/workflows/release.yml`**: push a
`v<version>` tag (or run the workflow manually with a version input) and the
pipeline builds a universal (arm64 + x86_64) app, signs it with the Developer
ID certificate, bakes in the OAuth app credentials, packages a DMG,
notarizes + staples it, publishes a GitHub Release, and bumps
`Casks/swiftx.rb` and the site version on `master`.

**This repo doubles as the Homebrew tap** — no separate `homebrew-swiftx`
repo. `Casks/swiftx.rb` at the repo root is what `brew` reads, so the cask
bump on `master` *is* the Homebrew release. Because the repo name lacks the
`homebrew-` prefix, the shorthand auto-tap doesn't apply; users tap by URL
once, then install:

```
brew tap retrohazard/swiftx https://github.com/RetroHazard/SwiftX
brew install --cask swiftx
```

Known tradeoff, accepted for now: `brew tap` full-clones the repo, so
Homebrew users pull the whole source tree for one cask file. This goes away
when SwiftX lands in the official `homebrew/cask` repo (see below).

## Cutting a release

```bash
git tag v0.2.0
git push origin v0.2.0
```

That's the whole runbook. Alternatively: Actions → Release → "Run workflow"
with the version (no `v` prefix) — that path creates the tag for you.

The pipeline is all-or-nothing on signing: if the Developer ID certificate or
notary credentials are missing or wrong, the workflow **fails** rather than
shipping an unsigned artifact. OAuth credentials are optional — missing ones
only produce warnings (those destinations are disabled in that build).

## Repository secrets

Set under **Settings → Secrets and variables → Actions**.

### Required — signing & notarization

| Secret | Contents |
|---|---|
| `APPLE_CERTIFICATE_P12` | base64 of the **Developer ID Application** certificate + private key, exported as `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `APPLE_CERTIFICATE_PASSWORD` | the password chosen when exporting the `.p12` |
| `APPLE_ID` | the Apple ID email of the developer account |
| `APPLE_TEAM_ID` | the 10-character Team ID (Apple Developer → Membership) |
| `APPLE_APP_PASSWORD` | an **app-specific password** from appleid.apple.com → Sign-In and Security (notarytool cannot use the account password) |

Prerequisite: paid Apple Developer Program membership ($99/yr). Create the
certificate at developer.apple.com → Certificates → **Developer ID
Application**, install it in a local Keychain, then export cert + key together
as a `.p12`.

### Optional — baked-in OAuth app credentials

These identify SwiftX itself to each host so end users just click "Connect".
`Scripts/write-oauth-plist.sh` turns them into the bundled (git-ignored)
`Resources/OAuthApps.plist`.

| Secret | Contents |
|---|---|
| `OAUTH_GOOGLE_CLIENT_ID` | Google Cloud OAuth **Desktop app** client ID — used for both Google Drive and YouTube |
| `OAUTH_GOOGLE_CLIENT_SECRET` | its client secret (Google desktop clients ship a semi-public secret; PKCE is the real protection) |
| `OAUTH_ONEDRIVE_CLIENT_ID` | Azure app registration **Application (client) ID** — public client, PKCE, deliberately no secret |

One-time provider registration:

- **Google (Drive + YouTube)** — console.cloud.google.com: create a project,
  enable the **Google Drive API** and **YouTube Data API v3**, configure the
  OAuth consent screen (External; publish it, or add testers while unverified),
  then create an OAuth client of type **Desktop app**. Desktop clients allow
  loopback redirects (`http://127.0.0.1:<port>/`) implicitly — nothing to
  register there.
- **OneDrive** — portal.azure.com → App registrations → New: supported account
  types "Personal Microsoft accounts + org accounts", add a **Mobile and
  desktop applications** platform with redirect URI `http://127.0.0.1`, and
  under Authentication → Advanced set **Allow public client flows: Yes**. Do
  not create a client secret.

## What the pipeline does, step by step

1. Resolves + validates the version from the tag (or dispatch input).
2. Fails fast with a clear error if any required secret is missing.
3. Runs `swift test` on the macOS 15 runner.
4. Imports the Developer ID cert into a throwaway keychain (deleted at the end).
5. `Scripts/write-oauth-plist.sh` → `Resources/OAuthApps.plist` from secrets.
6. `Scripts/make-app.sh` with `SWIFTX_UNIVERSAL=1` (arm64 + x86_64 fat binary)
   and `SWIFTX_REQUIRE_IDENTITY=1` — hardened runtime, secure timestamp.
7. Verifies the signature chain is Developer ID, then `Scripts/make-dmg.sh`
   and signs the DMG.
8. `Scripts/notarize.sh` — notarytool submit + staple + validate, then a final
   `spctl` Gatekeeper assessment.
9. `gh release create v<version>` with the DMG + a `.sha256` file and
   generated notes.
10. Commits the version + sha256 bump to `Casks/swiftx.rb` and
    `site/src/lib/content.ts` on `master` — which, since this repo is the
    tap, is what ships the update to `brew upgrade` users.

Everything the workflow runs is also runnable locally (`make-app.sh`,
`make-dmg.sh`, `notarize.sh` with a `swiftx-notary` keychain profile), so a
release can be produced by hand if Actions is ever unavailable.

## Official homebrew/cask

Now that releases are notarized and the cask carries no quarantine
workaround, the remaining blocker for the official repo is the `brew audit
--new` notability check (GitHub stars/forks/watchers on a young repo). Path:
accumulate some traction → submit a new-cask PR and let `brew audit --new`
pass clean. Landing there upgrades the UX to a plain `brew install --cask
swiftx` (no tap-by-URL step) and ends the full-clone tradeoff above.

## Updates

`brew upgrade --cask swiftx` is the update mechanism. No Sparkle integration
is needed for Homebrew users; add it only if a non-Homebrew (direct-download)
channel is introduced later.
