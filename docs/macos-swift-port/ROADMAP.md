# ShareX for macOS — Swift Port Roadmap

Feature-parity roadmap for a ground-up native macOS client written in Swift.
Grounded in an inventory of the current codebase (1,202 C# files, 13 projects).
Executed phase-by-phase across sessions; each phase ends runnable and testable.

**Targets:** macOS 13+ (ScreenCaptureKit baseline), Swift 5.10+, SwiftUI + AppKit
where SwiftUI falls short (region overlay, editor canvas). Distribution outside
the Mac App Store (Developer ID + notarization) — sandboxing is incompatible
with global hotkeys, screen recording of arbitrary apps, and watch folders.

**Repo layout:** new top-level `ShareX.macOS/` directory — Xcode project with
SPM local packages mirroring the C# project boundaries:

| Swift package        | Ports                                        |
|----------------------|----------------------------------------------|
| `SharedKit`          | ShareX.HelpersLib (name parser, settings, helpers) |
| `CaptureKit`         | ShareX.ScreenCaptureLib                      |
| `UploadKit`          | ShareX.UploadersLib                          |
| `EditorKit`          | ShareX.ImageEditor (use its platform-clean Core/ as the spec) |
| `EffectsKit`         | ShareX.ImageEffectsLib                       |
| `MediaKit`           | ShareX.MediaLib                              |
| `HistoryKit`         | ShareX.HistoryLib                            |
| `IndexerKit`         | ShareX.IndexerLib                            |
| `ShareX` (app)       | ShareX main app                              |
| `sharex-nmh` (tool)  | ShareX.NativeMessagingHost                   |

---

## Core Windows→macOS API map

| Windows (current)                        | macOS (port)                                       |
|------------------------------------------|-----------------------------------------------------|
| GDI+ BitBlt screen capture               | ScreenCaptureKit `SCScreenshotManager`             |
| DWM transparent/shadow window capture    | `SCWindow` capture (shadows native; feature folds in) |
| Win32 window enumeration                 | `CGWindowListCopyWindowInfo` + `AXUIElement` (control detection) |
| Desktop Duplication / gdigrab recording  | `SCStream` → `AVAssetWriter` (VideoToolbox H.264/HEVC) |
| DirectShow device enumeration            | `AVCaptureDevice` (video), CoreAudio (audio)       |
| RegisterHotKey global hotkeys            | Carbon `RegisterEventHotKey` (still the supported API) |
| System tray `NotifyIcon`                 | `NSStatusItem` menu bar item                       |
| WinForms/Avalonia UI                     | SwiftUI; AppKit `NSWindow`/`CALayer` for overlays & editor canvas |
| Clipboard (Win32)                        | `NSPasteboard`                                     |
| Toast notifications                      | `UserNotifications` framework                      |
| Registry / JSON settings                 | Codable JSON in `~/Library/Application Support/ShareX/` (keeps .sxcu/.sxie portability) |
| Windows OCR                              | Vision `VNRecognizeTextRequest`                    |
| QR encode/decode (ZXing)                 | CoreImage `CIQRCodeGenerator` / Vision `VNDetectBarcodesRequest` |
| Hash functions                           | CryptoKit                                          |
| GDI+ image effects                       | Core Image `CIFilter` chains                       |
| HttpWebRequest upload stack              | `URLSession` (upload tasks, multipart, progress)   |
| OAuth loopback/browser flow              | `ASWebAuthenticationSession` + loopback HTTP listener |
| SQLite history (Microsoft.Data.Sqlite)   | SQLite3 (GRDB if raw C API gets painful)           |
| FileSystemWatcher watch folders          | FSEvents / `DispatchSource.makeFileSystemObjectSource` |
| GitHub-based auto-updater                | Sparkle 2                                          |
| FFmpeg download & invoke                 | Same approach: download ffmpeg on demand, `Process` invoke |
| Native messaging host (stdin/stdout JSON)| Identical protocol; manifests in `~/Library/Application Support/<browser>/NativeMessagingHosts/` |

**Permissions reality (new work, no Windows equivalent):** Screen Recording
TCC prompt (capture + recording), Accessibility (window control/inspect),
Input Monitoring not required for Carbon hotkeys. Phase 0 builds the
permission-onboarding flow because every capture feature depends on it.

---

## Phases

### Phase 0 — Foundation & app shell
The skeleton everything hangs off. Ends with: menu bar app that persists settings and passes CI.
- Xcode project + SPM packages, GitHub Actions macOS CI (build + test)
- `NSStatusItem` menu bar app (LSUIElement), main window shell, Settings window shell
- Settings engine: Codable `ApplicationConfig` / `TaskSettings` / `HotkeySettings` / `UploadersConfig` mirroring the C# JSON shapes
- **Name parser** (`%y%mo%d`, `%rn`, `%width`… macro engine from HelpersLib) — used by filenames, uploaders, recording paths; port early, port completely
- TCC permission onboarding (Screen Recording, Accessibility) with status UI
- Single-instance enforcement + URL scheme (`sharex://`) for CLI/NMH handoff

### Phase 1 — Screen capture core
The 80% loop: capture → clipboard/file. Ends with: hotkey-less capture from the menu bar.
- Fullscreen / active monitor / active window / window-picker capture via `SCScreenshotManager`
- **Region select overlay**: full-screen borderless `NSWindow` per display at `.screenSaver` level — rectangle/ellipse/freehand regions, magnifier, crosshair, dimming, window & control snapping (`CGWindowList` + AX), fixed-size mode, snap sizes (240p–1080p), last-region memory, ruler mode, screen color picker mode
- Multi-display and mixed-DPI (Retina) correctness
- Save to file (name parser patterns, subfolders), copy to clipboard, PNG/JPEG/WebP/TIFF encoders, JPEG quality settings

### Phase 2 — Task pipeline, hotkeys, notifications
The ShareX "workflow" identity. Ends with: press hotkey → capture → after-capture chain runs.
- `WorkerTask` pipeline port: all **21 after-capture tasks** (quick task menu, beautify, effects, annotate, clipboard, pin-to-screen, print, save/save-as, thumbnail, actions, OCR, QR scan, upload, delete…) and **6 after-upload tasks** (shortener, share, copy URL, open URL, QR)
- Global hotkey engine (Carbon `RegisterEventHotKey`), hotkey settings UI, all **65+ HotkeyType actions** registered (stubs allowed for not-yet-ported features; each later phase fills its stubs)
- Toast notifications with click actions, sounds
- "Actions" (run external command on file) — direct `Process` port

### Phase 3 — Upload engine & core destinations
Ends with: capture → upload → URL on clipboard.
- `URLSession`-based uploader core: multipart, URL-encoded, JSON/XML/binary bodies, chunked/resumable range uploads, progress reporting, cancellation, retry, secondary-uploader fallback
- OAuth1 (HMAC-SHA1 signing) + OAuth2 (loopback + refresh) infrastructure via `ASWebAuthenticationSession`
- **Custom uploader engine (.sxcu)** — full syntax parser (`{json:…}`, `{regex:…}`, `{xml:…}`, `{filename}`, `{base64:…}`, nested functions, legacy `$var$` migration). Priority: this one engine unlocks hundreds of community destinations before any hand-ported service.
- Hand-ported tier-1 destinations: Imgur, Dropbox, Google Drive, OneDrive, Amazon S3, FTP/FTPS/SFTP, Pastebin, GitHub Gist, custom, email (SMTP)
- URL shortener core + is.gd/v.gd/tinyurl/bit.ly; clipboard upload, file upload, drag-drop upload, URL download-upload jobs

### Phase 4 — History & main window
Ends with: full task list UI + searchable history.
- SQLite history backend (schema-compatible where sensible), JSON/XML import from Windows ShareX for migrators
- Main window: task list + thumbnail grid views, progress, context actions
- History viewer + image history (filter by search/date/tags/favorites); stats

### Phase 5 — Annotation editor
Ends with: after-capture "Annotate" at parity with the Avalonia editor.
- Port `ShareX.ImageEditor/Core` (platform-clean C#) to Swift `EditorKit`: shapes (rect, ellipse, line, arrow, freehand, smart eraser, image, emoji, cursor), text (plain, background, speech balloon), steps, effect regions (blur, pixelate, highlight, magnify, spotlight), crop/cut-out tools
- Canvas: AppKit `CALayer`/CoreGraphics rendering, undo/redo memento history, style options (border/fill/corner/shadow/arrow styles), canvas expand, zoom/pan
- Reuse Phase 1 overlay annotation model so region-capture annotations and editor share one implementation

### Phase 6 — Image effects & beautifier
Ends with: `.sxie` presets round-trip with Windows ShareX.
- All **51 effects** as Core Image chains (15 adjustments, 18 filters, 10 manipulations, 8 drawings incl. watermark text/image)
- `.sxie` preset import/export compatibility; effects browser UI; CLI `ImageEffect` import
- Image beautifier (padding, rounded corners, shadow, gradient/wallpaper backgrounds) — mostly composition of the above

### Phase 7 — Screen recording
Ends with: hotkey → region/window/screen recording → MP4 or GIF.
- `SCStream` → `AVAssetWriter`: H.264/HEVC hardware encode, fps/region/duration options, mic + system-audio capture (SCStream audio), pause/resume/abort, fixed-region and active-window modes
- GIF pipeline: frame capture → palette quantization (port octree quantizer or use ffmpeg palettegen)
- Optional FFmpeg path (`avfoundation` input) for VP8/VP9/WebP/APNG parity and custom-args users; ffmpeg downloader from MediaLib

### Phase 8 — Tools suite
Each is small and independent; batch them.
- Color picker + screen color picker (overlay mode from Phase 1)
- Ruler, Pin to screen (floating `NSWindow`s from screen/clipboard/file)
- OCR (Vision, language selection), QR generate/decode/scan-region
- Hash checker (CryptoKit: CRC32/MD5/SHA family), metadata viewer/stripper (ImageIO)
- Image viewer, combiner, splitter, thumbnailer; video converter + video thumbnailer (AVFoundation, ffmpeg fallback)
- Folder indexer (HTML/XML/JSON/text), clipboard viewer, monitor test
- Window inspector (CGWindowList/AX). **Dropped as Windows-only:** borderless window, window-topmost toggle, DWM-specific options — documented in parity checklist as N/A
- AI integration (OpenRouter provider — plain HTTPS, ports directly)

### Phase 9 — Destination long tail
Ends with: every remaining C# destination either hand-ported, shipped as a bundled .sxcu, or documented as dead.
- Remaining file/image/text hosts (Box, B2, Azure, GCS, YouTube, Streamable, Nextcloud/ownCloud, Seafile, MediaFire, Puush, Pushbullet, transfer.sh, Pomf variants…), remaining shorteners (Polr, Kutt, YOURLS, Firebase…), URL sharing services (mostly URL-scheme opens — trivial)
- Audit pass: several C# destinations are dead services (Copy, StumbleUpon, Delicious, DropIO…) — verify and mark N/A rather than port corpses
- Shared-folder (SMB) destination via mounted-volume paths

### Phase 10 — Automation & integration
- Watch folders (FSEvents), auto capture (timer), scrolling capture (programmatic scroll via CGEvent/AX + stitch — highest-risk item in this phase)
- CLI: `sharex` command-line entry (hotkey-type verbs, file args, `-CustomUploader`, `-ImageEffect`, task/workflow GUIDs) via URL-scheme handoff to the running app
- Native messaging host binary + browser manifests (Chrome/Edge/Firefox); Safari requires a Safari Web Extension wrapper — evaluate, likely defer
- Workflows/quick-task menu completion

### Phase 11 — Distribution & polish
- Developer ID signing, notarization, DMG; Homebrew cask; Sparkle 2 auto-update (Release/PreRelease channels)
- Login item (SMAppService), Finder "Share via ShareX" extension (optional), localization scaffolding (23 languages exist upstream — infrastructure now, translations later)
- Settings import from Windows ShareX backup (JSON shapes intentionally kept compatible since Phase 0)

---

## Risks & non-portable notes
- **Scrolling capture** and **control-level snapping** depend on the Accessibility API's per-app cooperation — expect degraded behavior in some apps; ship best-effort.
- **System audio recording** requires macOS 13+ SCStream audio (fine) but per-app audio mixing is macOS 14.4+.
- **GIF quality parity** with ShareX's ffmpeg palettegen path needs the ffmpeg fallback; native-only GIF is a v1 compromise.
- **API keys**: C# embeds service keys via `APIKeys.cs` (private). New keys must be registered per service for the Mac client.
- **Steam build, Windows setup, DevBuilds channel**: N/A on macOS by definition.

## Parity tracking
Each phase PR updates `docs/macos-swift-port/PARITY.md` (created in Phase 0):
one row per feature from the inventory above — `Ported / Partial / N/A-Windows / Dead-service` — so "fully ported" is a checklist, not a feeling.
