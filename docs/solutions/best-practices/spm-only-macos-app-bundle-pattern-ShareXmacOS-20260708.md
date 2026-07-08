---
module: ShareX.macOS
date: 2026-07-08
problem_type: best_practice
component: tooling
symptoms:
  - Building a distributable menu bar .app without an Xcode project
  - "call to main actor-isolated initializer 'init()' in a synchronous nonisolated context" in main.swift
  - Bundle.module resource lookup fails when binary is moved into an .app
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
tags: [spm, app-bundle, info-plist, lsuielement, mainactor, screencapturekit, macos-14]
---

# Best Practice: SPM-only macOS app bundle (no Xcode project)

## Problem
Patterns worth reusing when shipping a macOS app straight from a SwiftPM executable target — collected while scaffolding the ShareX macOS port.

## Environment
- Module: ShareX.macOS (Swift 6.2.4, tools-version 5.10, language mode 5)
- Date: 2026-07-08

## Solution

**1. Bundle by script, not Xcode.** `swift build -c release`, then assemble `ShareX.app/Contents/{MacOS,Resources}` + `Info.plist` by hand. Key plist entries for a menu bar app:
- `LSUIElement = true` (no Dock icon; pair with `NSApp.setActivationPolicy(.accessory)`)
- `CFBundleURLTypes` for a custom URL scheme
- `codesign --force --sign -` at the end (see TCC doc)

**2. SPM resource bundles must be copied into the .app.** SPM emits `<Package>_<Target>.bundle` next to the binary; `Bundle.module`'s generated accessor also searches `Bundle.main.resourceURL`, so:
```bash
cp -R .build/release/ShareX_SharedKit.bundle "$APP/Contents/Resources/"
```
Without this, `Bundle.module` traps at runtime inside the app bundle.

**3. `main.swift` top-level code is NOT MainActor-isolated in Swift 5.x language mode.** AppKit boot needs:
```swift
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()          // @MainActor class
    app.delegate = delegate               // delegate is unowned(unsafe)!
    withExtendedLifetime(delegate) { app.run() }
}
```
Also annotate the `NSApplicationDelegate` class itself with `@MainActor` — selector methods calling main-actor APIs won't compile otherwise.

**4. API floor check:** `SCScreenshotManager` requires **macOS 14**, even though most of ScreenCaptureKit is 12.3+. Set `platforms: [.macOS(.v14)]` rather than maintaining a deprecated `CGWindowList` fallback.

## Why This Works
SwiftPM produces a plain Mach-O + resource bundles; an `.app` is just a directory convention that LaunchServices, TCC, and `Bundle.main` understand. Reproducing that convention in a 40-line script avoids maintaining a second build system (xcodeproj) until signing/notarization genuinely needs one.

## Prevention
- Start any SPM-only mac app with the bundling script in place; retrofitting Bundle.module paths later is confusing.
- When choosing the deployment target, check the *specific* APIs used, not the framework's headline availability.

## Related Issues
- See also: [swift-test-no-xctest-command-line-tools-ShareXmacOS-20260708.md](../developer-experience/swift-test-no-xctest-command-line-tools-ShareXmacOS-20260708.md)
- See also: [tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md](../runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md)
