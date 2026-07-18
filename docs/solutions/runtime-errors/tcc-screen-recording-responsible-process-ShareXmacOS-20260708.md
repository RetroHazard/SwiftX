---
module: SwiftX
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
- Module: SwiftX — CaptureKit (ScreenCaptureKit)
- Affected Component: `SCScreenshotManager.captureImage`, `SCShareableContent`
- OS: macOS 26 (applies to 13+)
- Date: 2026-07-08

## Symptoms
- `./build/SwiftX.app/Contents/MacOS/SwiftX --capture-selftest` (run as child of a terminal) → declined-TCC error, no prompt visible for the app itself.

## What Didn't Work

**Direct solution:** The problem was identified on the first failure — but only because the mechanism (responsible-process attribution) was already suspected.

## Solution

Two parts:

1. **Launch the app as a bundle via LaunchServices** so TCC attributes the request to the app itself:
```bash
open /path/to/SwiftX.app   # prompt now says "SwiftX", grant sticks to the app
```
Running `SwiftX.app/Contents/MacOS/SwiftX` directly from a shell inherits the terminal's TCC identity ("responsible process").

2. **Codesign the bundle with a certificate identity** (Apple Development or Developer ID) so the grant survives rebuilds:
```bash
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
```
**Ad-hoc signing (`--sign -`) is NOT enough:** TCC then pins the grant to the binary's CDHash, which changes on every rebuild — System Settings shows the toggle ON while capture silently fails. Recovery from that state:
```bash
tccutil reset ScreenCapture com.retrohazard.swiftx   # then relaunch and re-grant
```

Also note: a freshly granted Screen Recording permission only takes effect at **process start** — quit and relaunch the app once after granting.

## Why This Works
TCC (Transparency, Consent, and Control) resolves the "responsible process" for a permission request: for a process exec'd from a shell, that's the terminal application. LaunchServices (`open`, Finder, Dock) makes the app its own responsible process. Grants are stored against the bundle ID + the signature's *designated requirement*: certificate-based signatures produce a requirement anchored to the cert chain (stable across rebuilds), while ad-hoc signatures produce one anchored to the specific binary hash (invalidated by any rebuild).

## Prevention
- Never judge TCC-gated features from terminal-spawned runs; always test via `open` on the bundle.
- Keep `codesign --force --sign -` in the app bundling script from day one.
- Build a permission-status UI early (`CGPreflightScreenCaptureAccess()`, `AXIsProcessTrusted()`) — silent TCC failures are otherwise indistinguishable from bugs.

## Related Issues
- Promoted to Required Reading: [critical-patterns.md](../patterns/critical-patterns.md) (Pattern 1)
- See also: [swift-test-no-xctest-command-line-tools-ShareXmacOS-20260708.md](../developer-experience/swift-test-no-xctest-command-line-tools-ShareXmacOS-20260708.md)
- See also: [spm-only-macos-app-bundle-pattern-ShareXmacOS-20260708.md](../best-practices/spm-only-macos-app-bundle-pattern-ShareXmacOS-20260708.md)
- See also: [external-tool-detection-webm-transcode-ShareXmacOS-20260708.md](../best-practices/external-tool-detection-webm-transcode-ShareXmacOS-20260708.md) — .command-file pattern avoids the Automation TCC prompt
