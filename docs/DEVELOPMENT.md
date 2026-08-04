# SwiftX (macOS)

The Swift Package Manager project for SwiftX — see the [repo root README](../README.md) for what
SwiftX is and its feature set. This document covers the local development workflow.

There is no Xcode project; everything is driven through `swift build`/`swift test` and the scripts
in [`Scripts/`](../Scripts).

## Requirements

- macOS 14+ (Sonoma) — `Package.swift` targets `.macOS(.v14)` as the ScreenCaptureKit API floor
- Swift 5.10+
- A full **Xcode** install (not just the Command Line Tools) to run `swift test` — bare Command
  Line Tools don't ship XCTest/Swift Testing. Point `DEVELOPER_DIR` at it if it's not the active
  toolchain:
  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app swift test
  ```
- Optional: [Homebrew](https://brew.sh) `ffmpeg`, for WebM (VP9/VP8), animated WebP, and APNG
  recording output. SwiftX looks for it at the standard Homebrew (Apple Silicon/Intel) and MacPorts
  locations and falls back to H.264 if it's missing.

## Build, test, package

```sh
swift build                          # debug build
swift build -c release               # release build

DEVELOPER_DIR=/Applications/Xcode.app swift test

./Scripts/make-app.sh [version]      # bundles build/SwiftX.app (version defaults to the VERSION file)
open /Applications/SwiftX.app
```

`Scripts/make-app.sh` assembles the `.app` bundle by hand (copies the built executables, icon,
license text, and an inline-generated `Info.plist`), code-signs it with a local Developer ID or
Apple Development identity if one is available (falling back to ad-hoc), and installs it to
`/Applications` so TCC permission grants persist across rebuilds.

**Always run the installed `/Applications/SwiftX.app`, never the raw binary**
(`./.build/debug/swiftx`) **and never `build/SwiftX.app` directly.** Screen Recording and
Accessibility permissions are granted per bundle path — launching the bare executable from a
terminal makes the terminal the "responsible process" and SwiftX never gets its own prompt. A dev
machine that changes the bundle ID and rebuilds `build/SwiftX.app` in place at the same path can
also find that path pinned to the dead old identity, with capture requests resolving to nothing
visible in System Settings — a fresh clone's first build has no such history and won't hit this,
but installing to a stable path sidesteps it either way. If permissions get stuck, see
[`docs/solutions/runtime-errors/tcc-screen-recording-responsible-process-SwiftX-20260708.md`](solutions/runtime-errors/tcc-screen-recording-responsible-process-SwiftX-20260708.md).

If SwiftX is already running, `make-app.sh` will warn you — a running instance won't pick up a new
build; quit it first (`pkill -x SwiftX && open /Applications/SwiftX.app`).

If `/Applications` isn't writable (or `CI` is set), `make-app.sh` skips the install step and prints
the `build/SwiftX.app` fallback path to run from instead — that path works for everything except
fresh TCC grants.

`make-app.sh` builds in release configuration by default. Set `SWIFTX_CONFIG=debug` to bundle from
the debug products instead — CI does this so the package compiles once per run rather than twice,
and it's useful locally when you already have a warm `.build/debug` from `swift build`. Set
`SWIFTX_UNIVERSAL=1` for an arm64 + x86_64 build (what the release pipeline ships).

## CI

`.github/workflows/ci.yml` is the only workflow that gates a pull request. It runs on
`pull_request` plus a weekly schedule, and has **no top-level `paths:` filter** — a workflow
skipped by a path filter never reports a conclusion, which would leave a PR blocked on
`Expected — ci-ok` forever. Instead a cheap `changes` job diffs the pull request against its base
and gates the heavy jobs:

| Job | Runs when | Does |
| --- | --- | --- |
| `changes` | always | resolves the diff range and sets the `swift` / `site` / `version` flags |
| `swift` | `Sources/`, `Tests/`, `Package.swift`, `Scripts/`, `Resources/` | `swift build --build-tests`, `swift test`, bundle from debug products, assert the bundle |
| `site` | `site/`, the shared build action | `.github/actions/build-site` with eslint on |
| `version` | `VERSION`, cask, site version strings, `Scripts/version.sh` | `version.sh check` plus the hand-edit guard |
| `release-build` | weekly schedule only | universal release build — covers the release-mode compile and macos-15 image drift |
| `ci-ok` | always | **the single required status check**; passes on skipped jobs, fails on any failure |

There is no `push:` trigger, so nothing re-runs after a merge. That is safe because the
`pull_request` event builds `refs/pull/N/merge` — GitHub tests the **merge result**, not the
branch tip — and `master` requires branches to be up to date before merging, so that result is
still current when the merge lands. The trade is that merging one PR obliges any other open PR to
update and re-run; a merge queue would automate that, but merge queues need an organization-owned
repository and SwiftX is user-owned. The `merge_group` trigger is present but inert, so moving the
repo under an organization would make enabling the queue a settings-only change.

When adding a job to `ci.yml`, **add it to `ci-ok`'s `needs:` list**, or it is silently ungated.

`.github/workflows/pages.yml` (deploy) and `release.yml` / `auto-release.yml` (release) are
separate because they are not checks.

## Versioning & releases

SwiftX uses CalVer: `YYYY.M.N` — release year, release month (unpadded), and a counter that
increments per release within that month (`2026.7.1`, `2026.7.2`, `2027.1.1`). Versions are
computed at release time from the calendar and the existing `v*` tags; **nothing is bumped in
PRs**, and the `version` job in `.github/workflows/ci.yml` fails a PR that hand-edits the version
locations. `Scripts/version.sh` is the single implementation:

```sh
Scripts/version.sh next     # the version the next release would get
Scripts/version.sh check    # verify VERSION, cask, and site versions agree
```

The root `VERSION` file, `Casks/swiftx.rb`, and the site's version strings always hold the
**last released** version — the cask and site embed download URLs, so they must never point at
an unpublished release. `release.yml` rewrites all of them (plus the DMG sha256) after each
successful publish.

Cutting a release, in order of preference:

1. **Label a PR `release`** — when it merges to master, `auto-release.yml` dispatches the
   release pipeline, which computes the next CalVer, builds, signs, notarizes, publishes the
   GitHub release, and bumps the version files. Back-to-back releases are serialized by the
   pipeline's concurrency group, so numbers can't collide.
2. **Manual dispatch** — Actions → Release → Run workflow; leave the version empty for the next
   CalVer (or override it). `dry-run: true` builds and notarizes a DMG artifact without
   publishing anything.
3. **Tag push** — `git tag v2026.7.1 && git push origin v2026.7.1` still works and skips the
   version computation.

### The release format is a compatibility contract

Shipped copies of SwiftX read `releases/latest` from the GitHub API to find and install updates
(`Sources/UpdateKit/`), so three properties of a published release are consumed by software already
on users' machines, not just by this repository:

- **Asset names.** `UpdateKit` looks up `SwiftX-<version>.dmg` and `SwiftX-<version>.dmg.sha256`
  by exact name. Renaming either asset leaves installed copies unable to find the download; they
  fall back to opening the release page, but the in-place update is gone.
- **The `.dmg.sha256` asset holds the bare digest** (`shasum -a 256 | awk '{print $1}'`). The
  updater refuses to install anything it cannot verify against it, so dropping the asset disables
  self-update rather than weakening it.
- **Tag shape.** Tags are parsed as CalVer with an optional `v` prefix. A tag that doesn't parse
  (`nightly`, `2026.8`) is treated as "no update available".

Drafts and prereleases are never offered — `releases/latest` excludes them, and `UpdateKit` skips
them again on its own side. Changing any of the above is a breaking change for every installed
copy, including ones too old to be told about it, so treat the format as append-only.

## Regenerating the app icon

`Scripts/make-icon.swift` is a standalone CoreGraphics script (no dependencies) that regenerates
`Resources/SwiftX.icns` and the `Assets/icons/swiftx-*.png` ladder used by the icon, packaging, and
documentation:

```sh
swift Scripts/make-icon.swift
```

## OAuth credentials for optional upload destinations

Google Drive, YouTube, and OneDrive use OAuth2 and need app credentials to be
usable. Copy [`Resources/OAuthApps.example.plist`](../Resources/OAuthApps.example.plist) to
`Resources/OAuthApps.plist` and fill in your own registered app's client ID/secret (the redirect
URI to register is the loopback address `http://127.0.0.1`). `OAuthApps.plist` is git-ignored, so
real credentials never enter the tree; `make-app.sh` bundles it automatically when present. Without
it, those destinations show as unavailable — every other destination (S3, custom uploaders,
keyless shorteners, etc.) works without any setup.

`Scripts/write-oauth-plist.sh` writes the same file from `OAUTH_GOOGLE_CLIENT_ID` /
`OAUTH_GOOGLE_CLIENT_SECRET` / `OAUTH_ONEDRIVE_CLIENT_ID` if you'd rather not hand-edit it; the
release workflow runs it from repository secrets. The plist is copied into the bundle by
`make-app.sh` *before* signing, so re-run that script after changing credentials — editing the
copy inside a signed `.app` breaks its signature, and a bare `swift run` never sees the file at
all (`OAuthAppRegistry` resolves it through `Bundle.main`).

Registering the apps, once each:

- **Google** — one Cloud project, one OAuth client of type *Desktop app*, covering both providers;
  enable the Drive API and the YouTube Data API v3 on it. Scopes: `drive.file`, `youtube.upload`.
  While the consent screen's publishing status is **Testing**, Google expires refresh tokens after
  7 days, so connections drop weekly until the app is published — that presents as a destination
  spontaneously needing a reconnect, not as a bug.
- **OneDrive** — an Azure app registration as a public client (PKCE, no secret). The Azure portal's
  redirect-URI box [rejects http-scheme URIs with `127.0.0.1`](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url),
  so add it through the app **manifest** instead — `publicClient.redirectUris` in the Microsoft
  Graph manifest, or `replyUrlsWithType` with `"type": "InstalledClient"` in the older one. Adding
  it under the Authentication blade's *Web* platform silently produces an `invalid_request:
  redirect_uri` failure mid-flow. The port never needs registering: both hosts ignore it for
  loopback matching, which is what lets SwiftX bind an ephemeral port per connect.

### Verification status

Both of the apps behind the official releases are **unverified and pending review**. They are fully
functional; the only symptom is the "unverified app" warning on the provider's sign-in screen, which
[`.github/release-notice.md`](../.github/release-notice.md) explains in every release. Delete that
file once the notice no longer applies.

- **Google** — submitted for verification, awaiting review. `youtube.upload` is a sensitive scope,
  so review covers a demo video and a privacy-policy URL. Two things to watch while it is pending:
  an unverified app requesting sensitive scopes is capped at roughly 100 users who can ever grant
  consent, and if the consent screen is ever moved back to **Testing**, the 7-day refresh-token
  expiry above applies again and every user silently disconnects each week.
- **Microsoft** — not submitted. Publisher verification needs a Microsoft Partner Center account
  with a verified MPN ID whose email domain matches the app's publisher domain, so it is gated on
  registering a business entity rather than on anything in this repo. The consent screen keeps
  saying "unverified" until that is done; nothing else is affected.

Neither warning blocks a user from connecting, and neither is a security finding — the client ID and
Google's desktop client secret are public by construction in any native app (see
`Resources/OAuthApps.example.plist`), which is why the flow uses PKCE.

## Layout

```
Sources/
  SwiftXApp/            the app: menu bar shell, settings, CLI, hotkeys, pipeline
  SharedKit/            settings engine, name parser, shared helpers
  CaptureKit/           screen/window/region capture, recording
  UploadKit/            upload core, custom uploader engine, OAuth2
  EditorKit/            annotation editor
  EffectsKit/           image effects and beautifier
  HistoryKit/           SQLite history store
  ToolsKit/             color picker, ruler, OCR/QR, hash checker, converters, indexer
  UpdateKit/            release check, download verification, bundle swap
  NativeMessagingHost/  swiftx-host, the browser native messaging binary
  ShareExtension/       SwiftXShare.appex, the macOS Share… menu entry
Tests/                  one test target per *Kit module above
Scripts/                make-app.sh, make-dmg.sh, make-icon.swift, notarize.sh
Casks/                  swiftx.rb Homebrew cask
Resources/              SwiftX.icns, OAuthApps.example.plist, ShareExtension.entitlements
Assets/icons/           exported PNG icon ladder
site/                   the landing site (own README)
```

## Documentation

- [`macos-swift-port/PARITY.md`](macos-swift-port/PARITY.md) — feature parity
  status against upstream ShareX
- [`solutions/`](solutions/) — patterns and gotchas found while building this
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — coding conventions, including the copyright header
  used on ported vs. original files
