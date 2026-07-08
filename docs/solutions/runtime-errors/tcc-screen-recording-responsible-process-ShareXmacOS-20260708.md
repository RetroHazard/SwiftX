---
module: ShareX.macOS
date: 2026-07-08
problem_type: runtime_error
component: tooling
symptoms:
  - "selftest failed: The user declined TCCs for application, window, display capture"
  - SCShareableContent/SCScreenshotManager throws immediately with no permission prompt shown for the app
  - Screen Recording permission re-prompts after every rebuild
root_cause: config_error
resolution_type: environment_setup
severity: high
tags: [tcc, screen-recording, screencapturekit, codesign, permissions, macos]
---

# Troubleshooting: ScreenCaptureKit "user declined TCCs" when launched from a terminal

## Problem
A capture binary spawned from a terminal session fails ScreenCaptureKit calls with "The user declined TCCs for application, window, display capture" — macOS attributed the permission request to the **terminal host app**, not to the app being developed.

## Environment
- Module: ShareX.macOS — CaptureKit (ScreenCaptureKit)
- Affected Component: `SCScreenshotManager.captureImage`, `SCShareableContent`
- OS: macOS 26 (applies to 13+)
- Date: 2026-07-08

## Symptoms
- `./build/ShareX.app/Contents/MacOS/ShareX --capture-selftest` (run as child of a terminal) → declined-TCC error, no prompt visible for the app itself.

## What Didn't Work

**Direct solution:** The problem was identified on the first failure — but only because the mechanism (responsible-process attribution) was already suspected.

## Solution

Two parts:

1. **Launch the app as a bundle via LaunchServices** so TCC attributes the request to the app itself:
```bash
open /path/to/ShareX.app   # prompt now says "ShareX", grant sticks to the app
```
Running `ShareX.app/Contents/MacOS/ShareX` directly from a shell inherits the terminal's TCC identity ("responsible process").

2. **Ad-hoc codesign the bundle in the build script** so the grant survives rebuilds:
```bash
codesign --force --sign - "$APP"
```
TCC keys grants to the code signature; an unsigned or differently-hashed binary re-prompts (or silently fails) after every build.

Also note: a freshly granted Screen Recording permission only takes effect at **process start** — quit and relaunch the app once after granting.

## Why This Works
TCC (Transparency, Consent, and Control) resolves the "responsible process" for a permission request: for a process exec'd from a shell, that's the terminal application. LaunchServices (`open`, Finder, Dock) makes the app its own responsible process. Grants are stored against the bundle ID + code signing identity, so a stable (even ad-hoc) signature keeps the grant valid across rebuilds.

## Prevention
- Never judge TCC-gated features from terminal-spawned runs; always test via `open` on the bundle.
- Keep `codesign --force --sign -` in the app bundling script from day one.
- Build a permission-status UI early (`CGPreflightScreenCaptureAccess()`, `AXIsProcessTrusted()`) — silent TCC failures are otherwise indistinguishable from bugs.

## Related Issues
- See also: [swift-test-no-xctest-command-line-tools-ShareXmacOS-20260708.md](../developer-experience/swift-test-no-xctest-command-line-tools-ShareXmacOS-20260708.md)
- See also: [spm-only-macos-app-bundle-pattern-ShareXmacOS-20260708.md](../best-practices/spm-only-macos-app-bundle-pattern-ShareXmacOS-20260708.md)
