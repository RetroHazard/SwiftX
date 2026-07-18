---
module: SwiftX
date: 2026-07-08
problem_type: developer_experience
component: testing_framework
symptoms:
  - "error: no such module 'XCTest' when running swift test"
  - "error: no such module 'Testing' after converting tests to Swift Testing"
  - "You have not agreed to the Xcode license agreements" when using DEVELOPER_DIR
root_cause: incomplete_setup
resolution_type: environment_setup
severity: high
tags: [swift, spm, xctest, swift-testing, command-line-tools, xcode, developer-dir]
---

# Troubleshooting: `swift test` fails — no test framework in Command Line Tools

## Problem
`swift build` succeeds but `swift test` cannot compile any test target: macOS Command Line Tools ship **neither XCTest nor Swift Testing**, even on Swift 6.x toolchains.

## Environment
- Module: SwiftX (SPM package, Swift 6.2.4 / tools-version 5.10)
- Affected Component: all `swift test` runs
- OS: macOS 26, `xcode-select` pointing at `/Library/Developer/CommandLineTools`
- Date: 2026-07-08

## Symptoms
- `swift test` → `error: no such module 'XCTest'`
- Converting tests to `import Testing` (Swift Testing) → `error: no such module 'Testing'`
- `xcodebuild -version` → "tool 'xcodebuild' requires Xcode, but active developer directory is a command line tools instance"

## What Didn't Work

**Attempted Solution 1:** Rewrite the test suite from XCTest to Swift Testing (`#expect` macros), assuming Swift Testing is bundled with the Swift 6 toolchain.
- **Why it failed:** Apple bundles both test frameworks with **Xcode**, not with Command Line Tools. The CLT toolchain has no testing runtime at all.

## Solution

Full Xcode was already installed at `/Applications/Xcode.app` — only the *active developer directory* pointed at CLT. Redirect per-command instead of switching system-wide (which needs sudo):

```bash
# One-time (user must run; needs sudo):
sudo xcodebuild -license accept

# Every build/test command (no sudo, no global state change):
DEVELOPER_DIR=/Applications/Xcode.app swift test
```

Note: the license error surfaces the first time `DEVELOPER_DIR` is used — accept it before anything works.

## Why This Works
`DEVELOPER_DIR` overrides `xcode-select` for a single process, making the Xcode-bundled toolchain (with XCTest/Testing platform libraries) visible to SwiftPM without touching machine state. GitHub Actions macOS runners always use full Xcode, so CI is unaffected either way.

## Prevention
- Any SPM project with tests on a fresh Mac: check `xcode-select -p` first; if it says CommandLineTools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app`.
- Swift Testing (`#expect`) is still the better target than XCTest — it's the maintained framework; just know it comes from Xcode, not the standalone toolchain.
- If Swift Testing is used, suites that mutate global state need `@Suite(.serialized)` — it parallelizes by default, unlike XCTest.

## Related Issues
- See also: [tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md](../runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md)
- See also: [spm-only-macos-app-bundle-pattern-ShareXmacOS-20260708.md](../best-practices/spm-only-macos-app-bundle-pattern-ShareXmacOS-20260708.md)
