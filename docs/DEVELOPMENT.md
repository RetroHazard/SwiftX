# SwiftX (macOS)

The Swift Package Manager project for SwiftX — see the [repo root README](../README.md) for what
SwiftX is and its feature set. This document covers the local development workflow.

There is no Xcode project; everything is driven through `swift build`/`swift test` and the scripts
in [`Scripts/`](Scripts).

## Requirements

- macOS 14+ (Sonoma) — `Package.swift` targets `.macOS(.v14)` as the ScreenCaptureKit API floor
- Swift 5.10+
- A full **Xcode** install (not just the Command Line Tools) to run `swift test` — bare Command
  Line Tools don't ship XCTest/Swift Testing. Point `DEVELOPER_DIR` at it if it's not the active
  toolchain:
  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app swift test
  ```
- Optional: [Homebrew](https://brew.sh) `ffmpeg`, for WebM/VP9/VP8/APNG recording output. SwiftX
  looks for it at the standard Homebrew (Apple Silicon/Intel) and MacPorts locations and falls back
  to H.264 if it's missing.

## Build, test, package

```sh
swift build                          # debug build
swift build -c release               # release build

DEVELOPER_DIR=/Applications/Xcode.app swift test

./Scripts/make-app.sh [version]      # bundles build/SwiftX.app (version defaults to 0.1.0)
open build/SwiftX.app
```

`Scripts/make-app.sh` assembles the `.app` bundle by hand (copies the built executables, icon,
license text, and an inline-generated `Info.plist`), code-signs it with a local Developer ID or
Apple Development identity if one is available (falling back to ad-hoc), and installs it to
`/Applications` so TCC permission grants persist across rebuilds.

**Always run the built `.app`, never the raw binary** (`./.build/debug/swiftx`). Screen Recording
and Accessibility permissions are granted per bundle path — launching the bare executable from a
terminal makes the terminal the "responsible process" and SwiftX never gets its own prompt. If
permissions get stuck, see
[`docs/solutions/runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md`](../docs/solutions/runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md).

If SwiftX is already running, `make-app.sh` will warn you — a running instance won't pick up a new
build; quit it first (`pkill -x SwiftX && open build/SwiftX.app`).

## Regenerating the app icon

`Scripts/make-icon.swift` is a standalone CoreGraphics script (no dependencies) that regenerates
`Resources/SwiftX.icns` and the `Assets/icons/swiftx-*.png` ladder used by the icon, packaging, and
documentation:

```sh
swift Scripts/make-icon.swift
```

## OAuth credentials for optional upload destinations

Google Drive, YouTube, Dropbox, OneDrive, Box, and Imgur use OAuth2 and need app credentials to be
usable. Copy [`Resources/OAuthApps.example.plist`](Resources/OAuthApps.example.plist) to
`Resources/OAuthApps.plist` and fill in your own registered app's client ID/secret (the redirect
URI to register is the loopback address `http://127.0.0.1`). `OAuthApps.plist` is git-ignored, so
real credentials never enter the tree; `make-app.sh` bundles it automatically when present. Without
it, those destinations show as unavailable — every other destination (S3, custom uploaders,
keyless shorteners, etc.) works without any setup.

## Layout

```
Sources/
  SwiftXApp/            the app: menu bar shell, settings, CLI, hotkeys, pipeline
  SharedKit/             settings engine, name parser, shared helpers
  CaptureKit/             screen/window/region capture, recording
  UploadKit/              upload core, custom uploader engine, OAuth2
  EditorKit/              annotation editor
  EffectsKit/             image effects and beautifier
  HistoryKit/             SQLite history store
  ToolsKit/               color picker, ruler, OCR/QR, hash checker, converters, indexer
  NativeMessagingHost/    swiftx-host, the browser native messaging binary
Tests/                    one test target per package above
Scripts/                  make-app.sh, make-icon.swift
Resources/                SwiftX.icns, OAuthApps.example.plist
Assets/icons/              exported PNG icon ladder
```

## Documentation

- [`../docs/macos-swift-port/ROADMAP.md`](../docs/macos-swift-port/ROADMAP.md) — phase plan and
  Windows→macOS API mapping
- [`../docs/macos-swift-port/PARITY.md`](../docs/macos-swift-port/PARITY.md) — feature parity
  status against upstream ShareX
- [`../docs/solutions/`](../docs/solutions/) — patterns and gotchas found while building this
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — coding conventions, including the copyright header
  used on ported vs. original files
