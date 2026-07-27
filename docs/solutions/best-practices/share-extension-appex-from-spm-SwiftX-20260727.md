---
module: SwiftX
date: 2026-07-27
problem_type: best_practice
component: tooling
symptoms:
  - SwiftX is missing from the macOS "Share…" menu / share sheet
  - SwiftX is absent from System Settings > General > Login Items & Extensions > Sharing
  - NSServices puts an app in the right-click Services menu but never in the share sheet
  - SwiftPM has no app-extension product type and cannot set the -e _NSExtensionMain entry point
root_cause: missing_feature
resolution_type: implementation
severity: medium
tags: [appex, share-extension, nsextension, nsservices, app-sandbox, spm, codesign, macos-14]
---

# Best Practice: shipping a Share extension (.appex) from a SwiftPM-only project

## Problem
An app can declare `NSServices` in its `Info.plist` and get an entry in the
system-wide **right-click → Services** menu, and it is easy to assume that is
the same thing as being in the **Share…** menu. It is not. The share sheet is
populated exclusively from `com.apple.share-services` app extensions, and an
app that ships none is absent from both the Share menu and the Sharing list in
System Settings — with no error anywhere to explain it.

SwiftPM has no app-extension product type, which is what had kept the feature
off the list here.

## Environment
- Module: SwiftX (tools-version 5.10, language mode 5), macOS 14+
- Date: 2026-07-27

## Solution

### 1. An .appex is just a bundle around an ordinary executable
The only thing that makes an extension binary special is its entry point:
Xcode's extension targets link with `-e _NSExtensionMain` instead of `_main`.
SwiftPM cannot set that without `unsafeFlags` (which poisons the package for
downstream consumers), but the entry point is not actually required — calling
the same Foundation function from a normal `main.swift` is equivalent, and has
the Swift runtime already initialized when it runs:

```swift
// Sources/ShareExtension/main.swift
import Foundation

@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

exit(NSExtensionMain())
```

Everything else is bundle assembly in `Scripts/make-app.sh`:

```
SwiftX.app/Contents/PlugIns/SwiftXShare.appex/
  Contents/Info.plist            CFBundlePackageType = XPC!  (not APPL)
  Contents/MacOS/SwiftXShare     the swiftx-share product
  Contents/Resources/SwiftX.icns
```

Three things in that `Info.plist` are easy to get wrong:
- `CFBundleIdentifier` **must** be prefixed by the host app's identifier
  (`com.retrohazard.swiftx.share`), or the extension is rejected.
- `CFBundlePackageType` is `XPC!`. `APPL` silently fails to register.
- `NSExtensionPrincipalClass` is resolved through the Objective-C runtime, so a
  Swift class needs `@objc(ShareViewController)` — the mangled
  `ShareExtension.ShareViewController` will not be found.

### 2. Sign the appex separately, before the app
Nested code is signed inside-out, and the extension needs its own entitlements:

```sh
codesign --force --options runtime --timestamp \
    --entitlements Resources/ShareExtension.entitlements --sign "$IDENTITY" "$APPEX"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
```

macOS requires app extensions to adopt the **App Sandbox**, even when the host
app deliberately does not (SwiftX runs unsandboxed — see
`macos-swift-port/SECURITY-MODEL.md`). The extension only needs
`com.apple.security.app-sandbox` plus
`com.apple.security.files.user-selected.read-only`.

### 3. Hand off to the app instead of duplicating it
The sandbox makes it tempting to give the extension its own upload stack.
Don't: destinations, Keychain credentials, history and the after-upload chain
all live in the app. Because the *app* is not sandboxed, a one-way handoff is
trivial — the extension stages copies inside its own container
(`NSHomeDirectory()` there is `~/Library/Containers/<appex-id>/Data`) and the
app reads straight into that path, with no app group and therefore no
provisioning profile. See `SharedKit/ShareInbox.swift` for the contract and
`SwiftXApp/ShareRequests.swift` for the consuming side.

Waking the app from a sandboxed extension: `NSWorkspace.shared.open(url)` with
the app's own URL scheme works and launches the app if it is not running.

### 4. Registration
`pluginkit` discovers extensions when LaunchServices registers the containing
bundle, which happens on first launch from a stable location — which is why
`make-app.sh` installs to `/Applications`. To check and to force it:

```sh
pluginkit -m -p com.apple.share-services -vvv | grep swiftx
pluginkit -a /Applications/SwiftX.app/Contents/PlugIns/SwiftXShare.appex
```

A newly registered share extension may still need enabling in **System Settings
→ General → Login Items & Extensions → Sharing** before it appears in the menu.

## Verification
- `codesign --verify --deep --strict --verbose=2 build/SwiftX.app` (the release
  pipeline already runs this; `--deep` covers the nested appex)
- `pluginkit -m -p com.apple.share-services | grep com.retrohazard.swiftx.share`
- Finder → select a file → Share… → SwiftX → the upload appears in the app's
  task list and history

## References
- `Sources/ShareExtension/`, `Sources/SharedKit/ShareInbox.swift`
- `Scripts/make-app.sh`, `Resources/ShareExtension.entitlements`
- `docs/macos-swift-port/SECURITY-MODEL.md` § Share extension handoff
