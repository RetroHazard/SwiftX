# ShareX Parity Gap Analysis — July 2026

A code-level audit of SwiftX against upstream ShareX (`ShareX/ShareX`,
reviewed at **v21.0.0**, released 2026-07-03). Companion to
[`PARITY.md`](PARITY.md) (per-phase status) and [`ROADMAP.md`](ROADMAP.md)
(plan). Everything here is a gap **not already tracked** in those documents —
items they already cover (FTP/SFTP, Pastebin/Gist/SMTP, OAuth credentials,
chunked uploads, Safari extension, signing, login item, localization, …) are
intentionally omitted.

Method: SwiftX sources were compared against the upstream settings surface
(`ShareX/TaskSettings.cs`, `ShareX/ApplicationConfig.cs` on `develop`) and the
v19→v21 changelogs. C# setting names are given so future work stays
JSON-import-compatible.

**Status: integrated.** Every item below is now tracked as roadmap/parity
**Phases 12–15**: §1–2 → Phase 12 (workflow engine & destination routing),
§3/§4/§8 → Phase 13 (capture, recording & output options), §5–7 → Phase 14
(upload robustness & shell UX), §9–11 → Phase 15 (upstream v21 additions &
supportability). This document remains the detailed rationale behind those
rows; §10 stays append-only as the upstream-delta log. The "SwiftX today"
descriptions below are a snapshot of the codebase at audit time (2026-07) —
many have since shipped; [`PARITY.md`](PARITY.md) is the live status.

---

## 1. Per-hotkey task settings — "workflows" (largest gap)

**Upstream:** every hotkey in `HotkeysConfig.json` is a *workflow*: a
`HotkeySettings` entry embeds a **complete `TaskSettings` override** with a
`Description` (user-visible name), `Job`, and `UseDefault*` flags per section
(`UseDefaultAfterCaptureJob`, `UseDefaultDestinations`,
`UseDefaultImageSettings`, `OverrideScreenshotsFolder`, per-hotkey
`ExternalPrograms`, watch folders, …). This is the identity feature of ShareX:
one hotkey saves locally, another uploads to S3 and shortens, a third runs a
different name pattern into a different folder.

**SwiftX:** `HotkeyConfig` is `{TaskType, Key, Modifiers}` only
(`Sources/SharedKit/Settings.swift:479`). There is one global `TaskSettings`.
The CLI `-workflow` verb matches hotkeys **by job-type name**
(`Sources/SwiftXApp/CLI.swift:86`), so workflows cannot be named, and two
hotkeys bound to the same verb are indistinguishable and cannot behave
differently.

PARITY.md's "CLI verbs, workflows" row overstated this at audit time (it has
since been corrected to Partial): the verb dispatch is ported, the
per-workflow settings model is not.

**Impact:** high. Multi-destination / multi-behavior setups — the reason many
people run ShareX — are impossible.

**Approach:** extend `HotkeyConfig` with optional `Description` and an
embedded `TaskSettings` + `UseDefault*` flags using the C# key names, so a
Windows `HotkeysConfig.json` imports cleanly. The plumbing already exists:
`UploadCoordinator`/the after-capture pipeline accept a `settings:` override
(used by quick tasks and the before-upload window) — per-hotkey settings just
need to resolve and pass through it. Effort: medium; UI (per-hotkey override
sheet in Hotkeys settings) is most of the work.

## 2. Destination typing — text/file destinations and routing

**Upstream:** five destination slots per task: `ImageDestination`,
`TextDestination` (Pastebin-class paste services), `FileDestination`,
plus `ImageFileDestination`/`TextFileDestination` (which *file host* to use
when an image/text goes out as a file), and `UploaderFilters` (route by file
extension to a specific uploader).

**SwiftX:** a single `imageDestination` routes **all** uploads
(`Sources/SwiftXApp/UploadCoordinator.swift:90`); text uploads are wrapped
into a `.txt` file upload (`uploadText`, `:43`). Both spots carry `ponytail:`
TODO comments in code, but the parity doc only tracks the *hosts* (Phase 9
"remaining text hosts"), not the routing model.

**Impact:** medium-high. Recordings/arbitrary files can't target a different
host than screenshots; dedicated paste services can't be first-class; this is
also a prerequisite for the Phase 3 "Pastebin, GitHub Gist" items to land in a
C#-shaped way.

**Approach:** add `TextDestination`/`FileDestination` keys to `TaskSettings`
(C# names) and switch `route(_:)` on the task's data type. Small-medium.

## 3. Capture options

| Gap | Upstream | SwiftX today |
|---|---|---|
| Screenshot delay | `ScreenshotDelay` (seconds, decimal) + tray "capture with delay" 1–5 s submenu | No delay anywhere; captures fire immediately |
| Cursor in capture | `ShowCursor` user toggle | Hardcoded: display capture `true`, region capture `false` (`Sources/CaptureKit/ScreenCapture.swift:24,38`) |
| Annotate inside the region overlay | Region capture and annotation share one surface; number keys switch to drawing tools before the capture is committed (`RegionCaptureOptions`, `RegionCaptureDisableAnnotation`) | Overlay is select-only; annotation happens post-capture via the editor flag. ROADMAP Phase 5 ("reuse Phase 1 overlay annotation model") was ultimately built as a separate editor; PARITY has no row for in-overlay annotation |
| Overlay cosmetics | Dimming toggle, custom overlay colors, info-text options | Fixed behavior (dimming always on, stock colors) — cosmetic only |

Delay + cursor toggle are small, high-visibility wins; both are plain
`SCStreamConfiguration`/`Task.sleep` work plus two `TaskSettings` keys.

## 4. Screen recording UX

Recording works end-to-end, but the session ergonomics around it are thinner
than upstream:

- **No on-screen recording indicator**: ShareX draws a frame around the
  recorded region with a floating control strip (elapsed time, pause, stop).
  SwiftX control lives only in the status-bar menu — there is no visual cue of
  what is being recorded or for how long.
- **No start countdown** (`ScreenRecordAutoStart`, `ScreenRecordStartDelay`).
- **No fixed-duration recording** (`ScreenRecordFixedDuration`,
  `ScreenRecordDuration`).
- **No abort confirmation** (`ScreenRecordAskConfirmationOnAbort`).
- **No recording cursor toggle** (`ScreenRecordShowCursor` — SwiftX hardcodes
  `showsCursor: true`, `Sources/CaptureKit/ScreenRecorder.swift:250`).
- **Two-pass encoding** (`ScreenRecordTwoPassEncoding`, ffmpeg path): absent.

A border `NSWindow` at `.screenSaver` level around the capture rect plus a
small control panel would close most of this. Medium effort.

## 5. Upload pipeline robustness & URL post-processing

Settings upstream exposes that have no SwiftX equivalent:

- **Concurrency & size guards:** `UploadLimit` (max simultaneous uploads —
  SwiftX runs unbounded parallel tasks), `BufferSizePower`,
  `ShowMultiUploadWarning`, `ShowLargeFileSizeWarning`, master `DisableUpload`
  switch.
- **Retry depth:** `MaxUploadFailRetry` is configurable upstream; SwiftX has a
  fixed retry-once toggle (`RetryUpload`, `Sources/SwiftXApp/Views.swift:668`).
- **URL post-processing:** `URLRegexReplace`(+pattern/replacement),
  `ResultForceHTTPS`, `AutoShortenURLLength`, `EarlyCopyURL` (copy URL while
  upload is still running — a beloved power feature),
  `ClipboardContentFormat`/`OpenURLFormat`/`BalloonTipContentFormat`
  (`$result`-template control over what lands on the clipboard, e.g. Markdown
  `![]($result)`).
- **Clipboard-upload intelligence:** `ClipboardUploadURLContents` (download
  the URL on the clipboard and upload the file), `ClipboardUploadShortenURL`,
  `ClipboardUploadShareURL`, `ClipboardUploadAutoIndexFolder`.
- **Upload naming:** `FileUploadUseNamePattern`,
  `FileUploadReplaceProblematicCharacters`, `UseCustomTimeZone`/
  `CustomTimeZone` (note: `NameParser.customTimeZone` already exists in
  `Sources/SharedKit/NameParser.swift:30` but nothing wires it to a setting).
- **Clipboard hygiene:** `AutoClearClipboard`.

Individually small; `ClipboardContentFormat` and `EarlyCopyURL` deliver the
most user value per line of code.

## 6. Notifications & sounds

SwiftX uses `UNUserNotificationCenter` with the default sound and a single
click heuristic (open URL, else reveal file — `Sources/SwiftXApp/Notifier.swift`).
Upstream `TaskSettingsGeneral` offers:

- A **notification off-switch** (`ShowToastNotificationAfterTaskCompleted`) —
  SwiftX has no in-app toggle at all (only System Settings).
- `DisableNotificationsOnFullscreen`.
- **Custom sounds** per event (capture / task complete / action / error paths)
  and `PlaySoundAfterAction` — feasible via `UNNotificationSound(named:)`.
- **Configurable click actions and action buttons** (`ToastWindowLeftClick…`,
  `ToastWindowButtons`) — partially feasible via `UNNotificationAction`
  categories (e.g. "Copy URL", "Delete", "Annotate" buttons on the banner).
- Toast geometry (duration/placement/size/fade) — N/A under Notification
  Center; document as such rather than port.

## 7. Tray & main-window UX

- **Recent tasks / recent links** (`RecentTasksShowInTrayMenu`,
  `RecentTasksMaxCount`, `RecentTasksSave`, main-window recent strip): absent.
  A "Recent" submenu with the last N URLs/files (click = copy/open) is a small,
  high-touch feature.
- **Upload actions missing from the tray menu**: upload-file / folder /
  clipboard / text / URL verbs exist but are reachable only via hotkeys, CLI,
  or the drop window (`AppDelegate.buildMenu` has capture, record, tools,
  windows — no Upload section).
- **Configurable tray click actions** (`TrayLeftClickAction`,
  `TrayLeftDoubleClickAction`, `TrayMiddleClickAction`): SwiftX clicks always
  open the menu.
- **Progress in the tray icon** (`TrayIconProgressEnabled`): the template
  icon is static during uploads.
- **Hotkey guards:** `DisableHotkeysOnFullscreen`, `HotkeyRepeatLimit`
  (SwiftX has the plain `DisableHotkeys` toggle only).
- **Actions toolbar** is a fixed 8-button strip
  (`Sources/SwiftXApp/HotkeyActions.swift:224` — noted `ponytail` in code):
  upstream's list is user-configurable with position lock / run-at-startup.

## 8. Image output options

- **`FileExistAction`** (Ask / Overwrite / UniqueName / Cancel): SwiftX always
  auto-numbers (`Sources/SharedKit/SavePath.swift:43`). The Ask dialog matters
  to users with fixed name patterns.
- `ImagePNGBitDepth`, `ImageGIFQuality`, `ImageAutoJPEGQuality`: absent.
- Effects-pipeline switches: `ShowImageEffectsWindowAfterCapture`,
  `ImageEffectOnlyRegionCapture`, `UseRandomImageEffect` — SwiftX always
  applies the single selected preset (`ImageEffectsStore.selectedPreset`).

## 9. Editor refinements (upstream moved)

The PARITY Phase 5 rows were accurate against the inventory-era editor, but
upstream's 20.x/21.x Avalonia editor added user-visible options SwiftX lacks:

- **Font family** for text and speech-balloon tools — SwiftX text is fixed
  system font semibold (`Sources/EditorKit/EditorCanvasView.swift:294`), only
  size varies.
- **Arrow style** (Classic / Modern).
- **Middle-click canvas panning** (SwiftX pans via scrollbars only).
- Sticker packs remain un-ported (folded into the emoji N/A note; the image
  stamp covers local files but there is no sticker browser).

## 10. New upstream features since the roadmap inventory

Upstream's cadence changed (three major versions in six months, now .NET 9);
the roadmap's fixed inventory is aging. Deltas as of v21.0.0:

| Upstream feature (version) | Status in SwiftX | Note |
|---|---|---|
| **Background remover** (v21.0, local AI via user-downloaded ONNX model) | Missing, untracked | Natural macOS analog is Vision's `VNGenerateForegroundInstanceMaskRequest` (macOS 14+) — *no model download needed*, likely better UX than upstream. Strong Phase 8 addition |
| **Image comparer** tool (v21.0) | Missing, untracked | Small tool window (side-by-side / slider diff of two images) |
| **History: import folder** (v21.0) | Missing | SwiftX imports History.json/xml only; upstream can ingest a folder of images into history |
| **History moved to SQLite** (v21.0, History.json → History.db migration) | Convergence — SwiftX chose SQLite in Phase 4 | Action item: re-verify SwiftX's `History.db` schema against the **new upstream writer** (column names/types were designed against the older HistoryLib; upstream's own migration is now the reference) |
| Editor: font family, arrow style, editor selector (v20.1–21.0) | See §9 | Editor-selector dialog is N/A (one editor) |
| FFmpeg 7 baseline (v21.0) | N/A | SwiftX uses Homebrew ffmpeg; no pinned version expectations documented |

**Process recommendation:** treat this section as append-only — on each
upstream release, skim the changelog and log deltas here, so PARITY.md stays a
checklist against a *stated* baseline instead of silently drifting.

## 11. Supportability & app plumbing

- **Debug log:** upstream keeps a rotating log file plus an in-app log viewer;
  SwiftX only `NSLog`s. A `os.Logger` subsystem plus a "Show Log…" item (or a
  documented `log show` predicate) would make field debugging of upload
  failures viable. Auto-cleanup knobs (`AutoCleanupLogFiles`,
  `AutoCleanupBackupFiles`) come along naturally.
- **Settings export/import:** upstream exports/imports a full settings backup
  (.sxb zip). PARITY tracks *importing a Windows backup* (Planned 11), but a
  native SwiftX export/restore (migrating Macs, sharing configs) is untracked.
  Note Keychain-held secrets need an explicit story (export with consent, or
  documented re-entry).
- **Proxy:** upstream has manual proxy config (`ProxySettings`). `URLSession`
  follows the system proxy automatically, so this is *mostly N/A* — worth a
  PARITY row saying exactly that, with manual per-app proxy only if demanded.
- **N/A candidates worth recording** so they stop resurfacing in future
  audits: themes (`ShareXTheme` — macOS appearance is native), tray icon
  variants (`UseWhiteShareXIcon` — template image), `SilentRun` (menu bar app
  is always "silent"), `BrowserPath` (macOS default-browser convention),
  machine-specific/custom config paths, taskbar progress.

## 12. Suggested priorities

| # | Item | User value | Effort | Where it fits |
|---|---|---|---|---|
| 1 | Per-hotkey workflows (§1) | Very high — ShareX's identity feature | Medium | New phase / Phase 10 follow-up |
| 2 | Text + file destination routing (§2) | High — unblocks Phase 3 leftovers | Small-medium | With Phase 3 completion |
| 3 | Screenshot delay + cursor toggle (§3) | High visibility | Small | Anytime |
| 4 | Recording indicator + delay/duration (§4) | Medium-high | Medium | Phase 7 follow-up |
| 5 | `ClipboardContentFormat`, `EarlyCopyURL`, URL regex/HTTPS (§5) | Medium-high | Small | Anytime |
| 6 | Background remover via Vision (§10) | Medium — differentiator, beats upstream UX | Small-medium | Phase 8 follow-up |
| 7 | Recent-links tray submenu (§7) | Medium | Small | Anytime |
| 8 | Upload limit / retry count / warnings (§5) | Medium | Small | Anytime |
| 9 | `FileExistAction` (§8) | Medium | Small | Anytime |
| 10 | History.db schema re-verify vs upstream v21 (§10) | Correctness | Small | Soon — import path already ships |
| 11 | Notification toggle, custom sounds, action buttons (§6) | Medium | Medium | Anytime |
| 12 | Editor font family + arrow styles (§9) | Low-medium | Small | Phase 5 follow-up |
| 13 | Image comparer tool (§10) | Low | Small | Phase 8 follow-up |
| 14 | In-overlay annotation (§3) | Low (editor covers the job) | Large | Only if demanded |
| 15 | Log viewer / os.Logger (§11) | Low (dev-facing) | Small | Anytime |
