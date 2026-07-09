---
module: ShareX.macOS
date: 2026-07-08
problem_type: best_practice
component: tooling
symptoms:
  - "`which ffmpeg` / PATH lookup finds nothing when the app is launched from Finder, even though ffmpeg is installed"
  - Scripting Terminal to run an installer triggers an unexpected Automation (Apple events) TCC prompt
  - WebM/VP9 output from piped realtime frames plays back too fast on static screen content
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
tags: [ffmpeg, homebrew, path, finder-launch, tcc-automation, terminal, command-file, scstream, webm, vp9, transcode]
---

# Best Practice: Detecting/installing external CLI tools and transcoding SCStream recordings

## Problem
Three reusable patterns collected while adding WebM/VP9 recording support (ffmpeg integration) to the ShareX macOS port.

## Environment
- Module: ShareX.macOS (CaptureKit `FFmpeg.swift`, `RecordingCoordinator.swift`, Settings UI)
- Date: 2026-07-08

## Solution

### 1. Finder-launched apps get a minimal PATH — detect tools at absolute paths
`.app` bundles launched from Finder/Dock inherit launchd's environment (`/usr/bin:/bin:/usr/sbin:/sbin`), not the user's shell profile. `which ffmpeg` or `Process` with a bare executable name fails even when Homebrew has it installed. Probe known absolute locations instead:

```swift
public static let defaultSearchPaths = [
    "/opt/homebrew/bin/ffmpeg",   // Homebrew, Apple Silicon
    "/usr/local/bin/ffmpeg",      // Homebrew, Intel
    "/opt/local/bin/ffmpeg"       // MacPorts
]
public static var installedPath: String? {
    defaultSearchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
}
```

Use `isExecutableFile`, not `fileExists` — a non-executable file at that path is not an install.

### 2. Run installs in Terminal via a `.command` file — no Automation TCC prompt
`osascript -e 'tell app "Terminal" to do script ...'` requires the Automation (Apple events) permission and pops a scary prompt. Writing an executable `.command` file and `NSWorkspace.shared.open(...)`-ing it makes Terminal run it with visible progress and no TCC involvement:

```swift
let script = "#!/bin/zsh\n\(brewPath) install ffmpeg\n"
let url = FileManager.default.temporaryDirectory.appendingPathComponent("sharex-install-ffmpeg.command")
try script.write(to: url, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
NSWorkspace.shared.open(url)
```

Pair with a 2-second poll of `installedPath` in the UI so the status row flips green when the install completes (same pattern as the TCC permission rows).

### 3. Transcode after stop instead of piping realtime frames to ffmpeg
SCStream delivers frames only when screen content changes (variable frame rate). ffmpeg's rawvideo stdin pipe assumes constant `-framerate`, so static-screen stretches play back too fast. Recording H.264 MP4 first via `AVAssetWriter` (which preserves real presentation timestamps) and transcoding on stop keeps timing exact and reuses the proven writer:

```swift
// ffmpeg -y -i in.mp4 -c:v libvpx-vp9 -b:v 0 -crf 32 -row-mt 1 -an out.webm
// crf+b:v 0 = constant-quality VP9; row-mt uses all cores
```

Failure handling: if the transcode fails, keep the MP4 and say so in the notification — never delete the only copy of a recording before its replacement exists.

## Prevention
- Any feature invoking external binaries from a GUI app: resolve absolute paths, never rely on PATH.
- Any "run this in Terminal for the user" flow: prefer a `.command` file over Apple events.
- Any SCStream → non-AVFoundation encoder pipeline: go through an intermediate timestamped container rather than a raw frame pipe.

## Related Issues
- See also: [tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md](../runtime-errors/tcc-screen-recording-responsible-process-ShareXmacOS-20260708.md) — the other TCC pitfall in this port (grants keyed to code signature)
