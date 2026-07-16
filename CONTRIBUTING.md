# Contributing to SwiftX

SwiftX is a from-scratch Swift rewrite of [ShareX](https://github.com/ShareX/ShareX) for macOS,
built entirely in Swift on top of ScreenCaptureKit, SwiftUI, and AppKit.

## Development setup

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for build, test, and packaging commands.
The short version:

```sh
swift build
DEVELOPER_DIR=/Applications/Xcode.app swift test
./Scripts/make-app.sh
open build/SwiftX.app
```

Always exercise SwiftX through the built `.app` bundle, never the raw binary from
`.build/debug/swiftx` — Screen Recording and Accessibility permission grants are tied to the
bundle path, and a terminal launch never gets prompted. If a TCC-gated feature (screen capture,
recording, window inspection) misbehaves, check
[`docs/solutions/runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md`](docs/solutions/runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md)
before debugging further.

## Where things live

- [`docs/macos-swift-port/ROADMAP.md`](docs/macos-swift-port/ROADMAP.md) — the phase plan and the
  Windows→macOS API mapping each package is built against
- [`docs/macos-swift-port/PARITY.md`](docs/macos-swift-port/PARITY.md) — per-feature status
  (Ported/Partial/Planned/N/A/Dead); update the relevant row when you land a feature
- [`docs/solutions/`](docs/solutions/) — a knowledge base of non-obvious patterns and gotchas found
  while porting (SPM app-bundle packaging, `swift test` requiring full Xcode, TCC quirks, etc.).
  Add an entry here when you hit something similarly non-obvious.

## Coding conventions

- Every source file under `Sources/` starts with a header identifying the project,
  copyright, and license. Use whichever pattern applies:

  **Original code** (no upstream equivalent — new macOS-native capture/recording code, the OAuth
  layer, SwiftUI views, build scripts, tests):
  ```swift
  // SwiftX - screenshot capture and sharing for macOS
  // Copyright (c) 2026 RetroHazard
  // Licensed under GPL v3 - see /LICENSE.txt
  ```

  **Ported or translated from the C# ShareX codebase** — preserve the upstream notice per GPLv3
  §5(d):
  ```swift
  // SwiftX - screenshot capture and sharing for macOS
  // Copyright (c) 2026 RetroHazard
  // Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
  // Licensed under GPL v3 - see /LICENSE.txt
  ```

  When in doubt, check whether the logic traces back to a specific C# file (a name-parser code, an
  effect kernel, an uploader syntax) — if it does, use the "derived from" header.

- Where a C# behavior has a well-defined shape (settings JSON keys, `.sxcu`/`.sxie` file formats,
  hotkey verb names, history schema), match it exactly so files and configs stay portable between
  Windows ShareX and SwiftX. Deviating from that shape needs a good reason, called out in the PR
  description.
- Keep `docs/macos-swift-port/PARITY.md` truthful — mark a row `Ported` only once it's wired end to
  end, not just scaffolded.

## Legal

SwiftX is licensed under [GPL v3](./LICENSE.txt). By contributing, you agree your contribution is
licensed under the same terms. Please don't submit code you don't have the rights to license this
way (including code copied from other GPL-incompatible projects).

## Reporting bugs / requesting features

Open an issue at [github.com/RetroHazard/SwiftX/issues](https://github.com/RetroHazard/SwiftX/issues).
For security vulnerabilities, follow [`SECURITY.md`](.github/SECURITY.md) instead of filing a
public issue.
