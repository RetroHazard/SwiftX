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

## Versioning & releases

SwiftX uses CalVer: `YYYY.M.N` — release year, release month (unpadded), and a counter that
increments per release within that month (`2026.7.1`, `2026.7.2`, `2027.1.1`). Versions are
computed at release time from the calendar and the existing `v*` tags; **nothing is bumped in
PRs**, and `.github/workflows/version-check.yml` fails a PR that hand-edits the version
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
  NativeMessagingHost/  swiftx-host, the browser native messaging binary
Tests/                  one test target per *Kit module above
Scripts/                make-app.sh, make-dmg.sh, make-icon.swift, notarize.sh
Casks/                  swiftx.rb Homebrew cask
Resources/              SwiftX.icns, OAuthApps.example.plist
Assets/icons/           exported PNG icon ladder
site/                   the landing site (own README)
```

## Documentation

- [`macos-swift-port/PARITY.md`](macos-swift-port/PARITY.md) — feature parity
  status against upstream ShareX
- [`solutions/`](solutions/) — patterns and gotchas found while building this
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — coding conventions, including the copyright header
  used on ported vs. original files
