# Critical Patterns — Required Reading

Patterns that MUST be followed when working on this repository. Read before writing code.

---

## 1. Test and launch TCC-gated macOS features via the app bundle (ALWAYS REQUIRED)

### ❌ WRONG (fails with "user declined TCCs", or permission prompt blames the terminal)
```bash
swift build && ./.build/debug/swiftx --capture-selftest
# or
./build/SwiftX.app/Contents/MacOS/SwiftX
```

### ✅ CORRECT
```bash
./Scripts/make-app.sh          # bundles AND signs with a certificate identity
open build/SwiftX.app          # LaunchServices makes the app its own TCC identity
# after granting a permission: quit and relaunch once — TCC applies at process start
# if capture fails with the toggle ON after a rebuild (stale identity):
tccutil reset ScreenCapture com.retrohazard.swiftx   # then relaunch + re-grant
```

**Why:** macOS TCC attributes permission requests to the *responsible process* — for a shell-spawned binary that's the terminal app, so SwiftX never gets (or shows) its own prompt. Grants are keyed to bundle ID + the signature's *designated requirement*: with a certificate identity (Apple Development / Developer ID) that requirement is stable across rebuilds, but an **ad-hoc signature pins to the binary's CDHash**, so every rebuild invalidates the grant — System Settings still shows the toggle ON while capture silently fails. `make-app.sh` auto-selects a certificate identity and only falls back to ad-hoc.

**Placement/Context:** Any SwiftX feature touching Screen Recording (ScreenCaptureKit), Accessibility (AXUIElement), or Input Monitoring — capture, recording, window snapping, scrolling capture, pixel color, window inspection. Unit tests are unaffected; only live/manual verification is.

**Documented in:** `docs/solutions/runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md`

---
