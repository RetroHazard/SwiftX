# macOS Swift Port — Feature Parity Tracker

Statuses: **Ported** · **Partial** (works, known gaps) · **Planned** (phase noted) · **N/A** (Windows-only) · **Dead** (service defunct upstream)

Baseline: **upstream v21.0.0** (2026-07). The gaps found by the July 2026
audit are tracked below as Phases 12–15.

## Phase 0 — Foundation

| Feature | Status | Notes |
|---|---|---|
| Menu bar app shell (tray icon equivalent) | Ported | `NSStatusItem`, accessory activation policy |
| Settings engine (JSON, Windows-compatible keys) | Ported | Fields grow per phase; unknown keys tolerated |
| Name parser macro engine | Ported | All codes; `%remoji` uses the full C# emoji list; invalid `%rf` paths raise a notification (C# fails the task) |
| TCC permission onboarding | Ported | Screen Recording + Accessibility status/request UI |
| Single instance enforcement | Ported | flock-based; second instance forwards argv over distributed notifications and exits |
| `sharex://` URL scheme | Ported | `swiftx://Verb/parameter` dispatches through the CLI verb handler (hotkey verbs, workflows, imports) |
| CI (build + test) | Ported | GitHub Actions, macOS runner |
| Main window | Ported | Landed in Phase 4 — searchable history, grid view, live upload rows |

## Phase 1 — Screen capture

| Feature | Status |
|---|---|
| Fullscreen (display under cursor) / active window capture | Ported — ActiveMonitor hotkey maps here too |
| Monitor picker / window picker capture | Ported — status-menu submenus populate on open |
| Region select overlay — rectangle, dimming, crosshair, size label, multi-display, Esc cancel | Ported |
| Region overlay — window snapping (hover highlight, click captures), last region (menu + hotkey) | Ported |
| Region overlay extras — ellipse/freehand, magnifier, fixed size, snap sizes | Ported — Tab cycles shape, M toggles magnifier, F toggles fixed size, drags auto-snap to presets; ruler and screen color picker shipped as standalone tools (Phase 8) |
| Save to file + subfolder patterns (name parser), clipboard copy | Ported — FileExistAction honored (Ask/Overwrite/UniqueName/Cancel); default stays UniqueName auto-numbering (C# defaults to Ask) |
| JPEG/GIF/BMP/TIFF encoders + quality, auto-JPEG for large captures | Ported — C# EImageFormat set; WebP is not a C# image format either; PNG bit depth, GIF palette and auto-JPEG quality knobs shipped (13) |
| Screenshot delay, cursor-capture toggle | Ported (13) — ScreenshotDelay before every capture verb (incl. region picker) + tray Screenshot Delay submenu; ShowCursor toggle threaded into all capture paths |
| Cross-display region selection (stitching) | Ported — per-display captures composited at the highest backing scale |
| Transparent/shadow window capture | N/A — ScreenCaptureKit window capture includes native shadows |

## Phase 2 — Task pipeline, hotkeys

| Feature | Status |
|---|---|
| After-capture pipeline (C#-compatible flag serialization) | Ported — all 22 flags: beautify, effects, annotate, image/file/paths to clipboard, pin, print, save, save-dialog, thumbnail, actions, show in Finder, analyze (AI), scan QR, OCR, upload, delete (Trash), quick task menu, after-capture window, before-upload window |
| Pin to screen (from capture, clipboard, file, screen region, close all) | Ported — drag to move, double-click to close, scroll/± to scale, ⌘-scroll/⌘± for opacity (C# 10% steps), right-click menu (copy, save, close all) |
| After-upload tasks (6) | Ported — shorten, copy URL, open URL, share URL, QR code window, after-upload window (link formats + copy buttons) |
| Global hotkey engine (Carbon), defaults ⌃⇧3/4/5, DisableHotkeys toggle | Ported — recorder UI in Settings, live re-registration |
| HotkeyType vocabulary (C#-compatible raw values) | Ported — every verb dispatches: upload sources (file/folder/clipboard/text/URL/drag-drop), custom region/window, stop uploads, standalone image editor, actions toolbar, tray menu toggle |
| Capture notifications | Ported — banner + optional sound (C# PlaySound keys); app-level off-switch, fullscreen suppression, custom per-event sounds and action buttons shipped (14); toast geometry is N/A under Notification Center |
| Actions (external commands) | Ported — C# ExternalProgram JSON, $input/$output placeholders, output-extension chaining, Settings → External Programs pane |

## Phase 3 — Upload engine & core destinations

| Feature | Status |
|---|---|
| Upload core — multipart, form-urlencoded, JSON/XML body, binary | Ported |
| Upload core — progress UI, retry | Ported — live rows in main window (bar, retry state, URL/error); configurable retry count (RetryUpload × MaxUploadFailRetry), UploadLimit concurrency cap, DisableUpload switch and batch/size warnings shipped (14) |
| Upload core — chunked/resumable, secondary fallback | Planned — chunked only serves the benched OAuth hosts; fallback needs multi-destination config |
| Custom uploader engine (.sxcu) — syntax parser (json/xml/regex/base64/random/select/filename/header/response), import, destination picker | Ported — legacy pre-13.7.1 `$var$` files migrate at load; interactive select takes first option |
| Custom uploader editor (create/edit/duplicate/delete/export in settings) | Ported — Settings → Custom Uploaders pane; edits write Windows-compatible .sxcu files; export copies the stored file verbatim |
| OAuth2 infrastructure (authorize-code + PKCE, refresh, Keychain tokens, loopback redirect) | Ported — reusable OAuth2Flow/OAuthSession/OAuthTokenStore + loopback listener. App credentials are baked in from a git-ignored OAuthApps.plist (developer registers once); end-user setup is one-click Connect → browser sign-in → approve, with nothing to fill in. Hosts without baked-in keys show "unavailable" |
| OAuth1 infrastructure | Deferred — no kept host needs it (Photobucket dropped, Flickr deferred); add an OAuth1Flow layer only if Flickr is wanted |
| Amazon S3 (+ S3-compatible via custom endpoint) — SigV4, prefix patterns | Ported |
| Google Drive, OneDrive, YouTube (OAuth2) | Scaffolded — full upload + public-link flow wired through the OAuth2 core, disabled pending app credentials; uploader bodies untested until real keys exist (no chunked/resumable/progress yet) |
| Imgur, Box, Dropbox (OAuth2) | Dropped — see Phase 9 |
| FTP/FTPS/SFTP, Pastebin, GitHub Gist, Email (SMTP) | Planned (3) — many work today via community .sxcu files |
| URL shorteners: is.gd, v.gd, TinyURL (keyless) | Ported — wired to UseURLShortener flag |
| URL shorteners requiring keys: bit.ly, Polr, Kutt, YOURLS | Ported (9) — see Phase 9 |
| After-upload: copy URL to clipboard, open URL | Ported |

## Phase 4 — History & main window

| Feature | Status |
|---|---|
| SQLite history (Windows-compatible History.db schema) | Ported — verified against upstream v21's HistoryManagerSQLite (2026-07): identical table/columns/insert order, Tags JSON and ISO-8601 dates all covered by the readers; adopted its `busy_timeout` pragma; schema drift now guarded by a test |
| JSON/XML history import from Windows | Ported — Import History… in the main window reads History.json (bracketless object stream) and History.xml (root-level fragments) into the SQLite store |
| Main window: searchable history list, thumbnails, context actions | Ported — search by name/URL/host/tags |
| Thumbnail grid view (persisted TaskViewMode), time-range filter, favorites (Windows-compatible "Favorite" tag) | Ported |
| Tag filters (window title/process), stats | Ported — captures record WindowTitle/ProcessName tags, search matches tag values (C# SearchInTags), Statistics… shows the C# stats report (types, years, extensions, hosts, process names) |
| Live task queue with upload progress rows | Ported — upload rows above the history list (progress bar, retry state, URL/error) |

## Phase 5 — Annotation editor

| Feature | Status |
|---|---|
| Shapes: rectangle, ellipse, line, arrow, freehand | Ported |
| Text (inline entry), step numbers (auto-increment) | Ported — font-family picker for text/balloon tools shipped (15); step circles stay system font |
| Effect regions: blur, pixelate, highlight | Ported |
| Undo/redo, color/width controls, AnnotateImage pipeline flag (Cancel aborts task) | Ported |
| Shape selection, move, resize handles, Delete, double-click text re-edit, recolor selection | Ported — Screenshot.app-style manipulation |
| Speech balloon (draggable tail, inline text) | Ported |
| Crop (undoable, shapes translate, canvas resizes) | Ported |
| Smart eraser, magnify, spotlight, cut-out, image stamp | Ported — eraser samples the canvas color like C#; magnify is a 2× ellipse zoom; spotlight is a movable shape (same visual as C#'s destructive dim); cut-out joins halves with a straight edge (torn-edge effects not ported) |
| Emoji / cursor stamps | N/A — emoji via text tool + macOS emoji palette (⌃⌘Space); captures already include the cursor |
| Canvas expand, zoom/pan, fill/shadow style options | Ported — per-edge expand with fill color, ⌘+/⌘- zoom (pan via scrollbars), fill color + drop shadow apply to selection like recolor |

## Phase 6 — Image effects

| Feature | Status |
|---|---|
| 15 adjustments, 18 filters, 10 manipulations, 8 drawings | Ported — C#-exact matrices/kernels on straight-alpha buffers; editor window generates one reflection-based parameter form for all 51 effects, with live preview |
| .sxie preset import/export | Ported — C#-compatible Config.json ($type bare class names, PascalCase keys, TypeConverter scalar strings); BeautifyImage/AddImageEffects run in the after-capture pipeline before annotate |
| Image beautifier | Ported — smart padding, rounded corners, shadow angle/distance, gradient/color/image/transparent backgrounds; tool window with live preview + Copy/Save |

## Phase 7 — Screen recording

| Feature | Status |
|---|---|
| H.264/HEVC recording (region/window/screen, audio, pause) | Ported — SCStream → AVAssetWriter MP4; system audio + microphone as AAC tracks (mic needs macOS 15); pause/resume via menu or PauseScreenRecording hotkey drops the gap from the timeline |
| Recording session UX (on-screen frame + controls, countdown, fixed duration, abort confirm, cursor toggle) | Ported (13) — dashed border + floating strip (elapsed, pause, stop, abort) excluded from the stream; start countdown, fixed-duration auto-stop, abort confirmation, ScreenRecordShowCursor |
| GIF recording | Ported — ImageIO encoder, real per-frame delays, region/window/screen |
| Recording through task pipeline (save, history, notify, path copy, upload) | Ported — uploads reuse the image destination |
| WebM/VP9 via ffmpeg | Ported — detects Homebrew/MacPorts ffmpeg, records H.264 then transcodes; Settings shows install status + one-click Homebrew install; falls back to H.264 when ffmpeg is missing |
| VP8/WebP/APNG, custom ffmpeg args | Ported — post-stop ffmpeg transcode like VP9; WebM keeps recorded audio as Opus; custom args replace the preset (C# UseCustomCommands) |
| gdigrab/ddagrab/screen-capture-recorder sources | N/A — replaced by ScreenCaptureKit / avfoundation |

## Phase 8 — Tools

| Feature | Status |
|---|---|
| Color picker, screen color picker, ruler, pin to screen | Ported — hex/RGB/HSB/CMYK/decimal copy formats; screen picker uses the native loupe (NSColorSampler); ruler reuses the region overlay and reports W×H/diagonal/angle; pin gained scale/opacity/menu (see Phase 2) |
| OCR (Vision), QR generate/decode/scan | Ported — Vision auto-detects language (no language picker needed); QR via Core Image + Vision; both also run as after-capture flags (DoOCR, ScanQRCode) |
| Hash checker, metadata viewer/stripper | Ported — CRC-32/MD5/SHA-1/256/384/512 with compare field; metadata via Image I/O instead of exiftool (strip may recompress lossy formats) |
| Image viewer/combiner/splitter/thumbnailer, video converter/thumbnailer | Ported — combiner has orientation/alignment/spacing/wrap; converter offers x264/x265/VideoToolbox/VP8/VP9/GIF/WebP/APNG via ffmpeg (VideoToolbox stands in for nvenc/amf/qsv); thumbnailer builds timestamped contact sheets |
| Folder indexer, clipboard viewer, monitor test, window inspector | Ported — indexer emits text + HTML (C# also has XML/JSON); inspector is read-only (macOS can't set other apps' topmost/opacity) |
| AI integration (OpenRouter) | Ported — one OpenAI-compatible client (base URL + key + model) covers OpenAI, OpenRouter and Gemini's compat endpoint; AnalyzeImage after-capture flag wired |
| Borderless window, window top-most, DNS changer | N/A — Windows-only |

## Phase 9 — Destination long tail

| Feature | Status |
|---|---|
| Uguu, Pomf clones (configurable URL), vgy.me, s-ul, LobFile, Puush, Chevereto, Streamable | Ported — shared multipart engine; Streamable returns the page URL without transcode polling |
| Backblaze B2 (native API, stale-URL retry), Azure Storage (SharedKey), ownCloud/Nextcloud (WebDAV + OCS share), Seafile (upload-link + share-link), Pushbullet (pushes to all devices) | Ported |
| YouTube | Scaffolded — see Phase 3; wired through the OAuth2 core, disabled until app credentials are supplied |
| Imgur | Dropped — no longer issues app client IDs, so the OAuth2 flow can never be configured |
| Box | Dropped — developer API gated behind a paid subscription |
| Dropbox | Dropped — by choice |
| GCS | Benched — needs OAuth2/service-account app credentials; revisit if per-user client keys become acceptable |
| Flickr | Deferred — alive but niche and OAuth1-only; needs an OAuth1 signing layer no kept host requires |
| Photobucket | Dropped — defunct developer program / disrepute (2017 hotlink-ransom history) |
| MediaFire (session signing), Plik (session protocol), ImageShack (login flow), Lambda (canonical domain down), remaining text hosts | Planned (9 follow-up) |
| transfer.sh | Dead — public instance offline, verified 2026-07 |
| Shorteners: bit.ly (personal access token), Polr, Kutt, YOURLS, Zero Width, vurl.com | Ported — settings UI per service; bit.ly uses a user token instead of C#'s app-key OAuth flow |
| URL sharing services (Email/mailto, Facebook, Reddit, Pinterest, Tumblr, LinkedIn, VK, Google Lens, Bing VS) | Ported — ShareURL flag opens the share page in the browser; Pushbullet + custom sharing land with their destinations |
| Firebase Dynamic Links (Google shutdown 2025), qr.net, 2.gp, turl.ca, nl.cm | Dead — API endpoints verified gone 2026-07 |
| Copy, StumbleUpon, Delicious, DropIO, Slexy | Dead — verify & drop |

## Phase 10 — Automation & integration

| Feature | Status |
|---|---|
| Watch folders | Ported — FSEvents watcher with glob filter, subdirectories, move-to-screenshots, C# size-stability gate; Settings → Watch Folders pane |
| Auto capture | Ported — region/full-screen repeat timer, wait-for-uploads, C# AutoCapture* keys; annotate/menus stripped per shot like C# |
| Scrolling capture | Ported — synthetic scroll-wheel events + C# CombineImages row-matching stitcher (side margins, auto bottom-edge trim, best-guess fallback); Windows-message scroll methods N/A |
| Quick task menu (ShowQuickTaskMenu) + editor | Ported — C# QuickTaskPresets JSON incl. separators; menu at cursor |
| After-capture / before-upload windows | Ported — filename + task toggles; destination override before upload (all sources) |
| CLI verbs, workflows | Partial — -HotkeyTypeName [file], -workflow, -CustomUploader .sxcu, -ImageEffect .sxie, -NativeMessagingInput .json, bare path/URL upload; second instance forwards to primary. Verb dispatch is ported, but hotkeys carry no per-workflow TaskSettings overrides (names, destinations, after-capture chains) — Planned (12) |
| Native messaging host (Chrome/Edge/Firefox) | Ported — SwiftXHost binary in bundle speaks the Chrome stdio protocol; manifest install toggle in General settings |
| Safari extension | Deferred — needs an Xcode app-extension target + separate distribution; revisit after Phase 11 signing |

## Phase 11 — Distribution

| Feature | Status |
|---|---|
| DMG packaging + Homebrew cask | Ported — `Scripts/make-dmg.sh` builds a drag-to-install DMG (hdiutil); `Casks/swiftx.rb` (this repo doubles as the tap — `brew tap retrohazard/swiftx <repo url>` — `brew style` clean) with a real sha256, bumped automatically by the release pipeline. The pipeline also publishes a `SwiftX-<version>.dmg.sha256` asset, which the in-app updater verifies downloads against; cask-installed copies are detected and left to `brew upgrade --cask swiftx`. Official `homebrew/cask` is a follow-up (needs traction) |
| Developer ID signing, notarization | Ported — the release pipeline (`.github/workflows/release.yml`) signs with a Developer ID Application cert, notarizes and staples the DMG, and runs a Gatekeeper assessment before publishing; v0.1.0 shipped this way |
| Auto-update (Release channel) | Ported — custom in-app updater, no Sparkle: checks the GitHub `releases/latest` API (manual "Check for Updates…" plus a Daily/Weekly/Monthly/Off background cadence), verifies the published sha256 and that the new bundle's Developer ID Team ID matches the running app, then atomically swaps the bundle and relaunches; opt-in auto-install. Homebrew installs are detected via the Caskroom and deferred to `brew upgrade --cask swiftx`. Keys are macOS-only (no C# counterpart to `UpdateChannel`/`AutoCheckUpdate`): `UpdateCheckFrequency`, `UpdateAutoInstall`, `UpdateSkippedVersion`, `UpdateLastCheckTime`. PreRelease/DevBuilds channels remain N/A |
| Settings import from Windows backup (.sxb) | Ported — Import Settings… detects a Windows ShareX .sxb (zip with DefaultTaskSettings-nested config), merges the keys with macOS equivalents, imports custom uploaders from CustomUploadersList (with legacy-syntax migration), maps C# Keys hotkey strings to mac combos (unmappable keys like PrintScreen are skipped and counted), and offers to import History.db (same SQLite schema as the native store) |
| Login item | Planned (11) |
| Localization infra | Ported — one `Localizable.strings` per language in SharedKit, `L10n` lookup with English fallback, in-app language picker (Settings → General, `InterfaceLanguage` key, relaunch to apply), `Scripts/check-localizations.sh` + CI key-set validation; see `docs/LOCALIZATION.md`. English is the only shipped language so far; `InfoPlist.strings` and `.stringsdict` plurals are deferred to the first translation |
| Steam build, Windows installer, DevBuilds channel | N/A |

## Phase 12 — Workflow engine & destination routing

| Feature | Status |
|---|---|
| Per-hotkey TaskSettings overrides (named workflows, C# UseDefault* flags) | Planned (12) — hotkeys are verb + key combo only today (which the .sxb import maps from Windows HotkeysConfig.json); the `settings:` override plumbing (quick tasks, before-upload window) is the intended path |
| Named workflows in tray + `-workflow <name>` by Description | Planned (12) — CLI currently matches by verb name |
| Text / File destination slots (TextDestination, FileDestination), routing by task data type | Ported — per-type pickers in Settings → Destinations (image / text / file & video) with per-type active custom uploaders (ActiveTextCustomUploader / ActiveFileCustomUploader, falling back to the image uploader); uploads classify by extension like C# EDataType; text uploads still wrap as .txt files. Image-file/text-file secondary fallbacks remain unported. Each picker also filters to the hosts that accept that kind (`DestinationCatalog`, mirroring C#'s EImageUploaderType/ETextUploaderType/EFileUploaderType) — YouTube can't be picked for a text upload, image hosts can't take an archive; a stored destination that predates the filter still shows, labelled not valid for the slot |
| UploaderFilters (per-extension destination routing) | Planned (12) |

## Phase 13 — Capture, recording & output options

| Feature | Status |
|---|---|
| Screenshot delay (ScreenshotDelay) + tray capture-with-delay submenu | Ported — decimal seconds before every capture verb (incl. the region picker, like C#); tray Screenshot Delay submenu (Off/1–5 s); active-window capture resamples the frontmost app after the delay |
| Cursor-capture toggles (ShowCursor, ScreenRecordShowCursor) | Ported — threaded into display/region/window screenshots and SCStream recordings; C# default (on) applies |
| Recording frame + control strip (elapsed time, pause, stop) | Ported — dashed border around the recorded rect + floating strip (elapsed, pause/resume, stop, abort); both sharingType .none and SCStream-filter-excluded so they never appear in the file; window recordings show the strip only (the stream follows the window) |
| Recording start countdown, fixed-duration mode, abort confirmation | Ported — countdown shown in the strip (cancellable; start verbs cancel too), ScreenRecordDuration auto-stop, ScreenRecordAskConfirmationOnAbort dialog on abort (menu, hotkey, strip) |
| Two-pass encoding (ffmpeg) | Ported — VP9/VP8 preset transcodes run pass 1 (-f null) + pass 2 with a shared passlogfile; custom-args and WebP/APNG stay single-pass |
| FileExistAction (Ask / Overwrite / UniqueName / Cancel) | Ported — resolved against the final name (after after-capture-window renames); default stays UniqueName to preserve existing behavior (C# defaults to Ask) |
| PNG bit depth, GIF quality, auto-JPEG quality | Ported — Bit24 flattens onto white, Bit32 forces an alpha channel; GIF Grayscale converts, Bit8 = ImageIO's native 256-color palette, Bit4 falls back to it (ImageIO has no palette-size control); ImageAutoJPEGQuality applies only when the size rule forces JPEG |
| Effects-pipeline switches (effects window after capture, region-capture-only, random preset) | Ported — effects window opens seeded with the capture (Apply / Continue Without Effects); ImageEffectOnlyRegionCapture gates on region-sourced captures; UseRandomImageEffect draws a preset per capture |
| In-overlay annotation, overlay cosmetic options | Deferred — post-capture editor covers the job; revisit only if demanded |

## Phase 14 — Upload robustness, URL post-processing & shell UX

| Feature | Status |
|---|---|
| Upload concurrency cap (UploadLimit), configurable retry count, DisableUpload, multi-upload/large-file warnings | Ported — FIFO gate bounds simultaneous uploads; RetryUpload × MaxUploadFailRetry attempts; DisableUpload togglable from the tray Upload section; confirm dialogs for >10-file batches and >100 MB files |
| ClipboardContentFormat / OpenURLFormat $result templates, EarlyCopyURL | Ported — BalloonTipContentFormat too; EarlyCopyURL copies the raw URL at upload completion, before shortening/formatting (no pre-completion URL prediction — no ported host has deterministic URLs) |
| URLRegexReplace, ResultForceHTTPS, AutoShortenURLLength | Ported — C# order (regex → HTTPS → shorten); invalid user regex passes the URL through instead of failing the task |
| Clipboard-upload intelligence (URL contents, shorten-instead, auto-index folder), AutoClearClipboard | Ported — C# precedence for URLs (contents → shorten → share); copied folders upload an HTML index; AutoClearClipboard clears after dispatch |
| Upload naming (FileUploadUseNamePattern, problematic-character replacement, custom time zone) | Ported — upload name follows the pattern (file on disk untouched); UseCustomTimeZone + CustomTimeZoneIdentifier (macOS key — C# serializes TimeZoneInfo) wired into every name parse via NameParser.forTask |
| Notification granularity (off-switch, fullscreen suppression, custom per-event sounds, action buttons) | Ported — ShowToastNotificationAfterTaskCompleted, DisableNotificationsOnFullscreen (CGWindowList fullscreen heuristic); custom capture/completion/error sounds play via NSSound (banner goes silent to avoid doubling); banner buttons: Copy URL/Open for uploads, Show in Finder/Annotate/Delete for files |
| Toast geometry (duration, placement, size, fade) | N/A — Notification Center owns presentation |
| Recent-links tray submenu + main-window recent strip (RecentTasks*) | Ported — Recent submenu reads the last N history entries (click copies the URL, or reveals the file); the main window's live task rows + searchable history already serve as the recent strip |
| Tray Upload section, configurable left-click action, status-icon upload progress | Ported — Upload submenu (file/folder/clipboard/text/URL/shorten/drop window/stop/disable); TrayLeftClickAction picker (right click always menus); TrayIconProgressEnabled draws a progress ring on the status icon. macOS extras: a "Check for Updates…" entry, Settings → Menu Bar → Menu contents hides individual entries (TrayMenuHiddenItems; Settings/Quit and live recording controls stay), an "Upload with SwiftX" Services entry puts SwiftX in the system-wide right-click Services menu for files and selected text, and an embedded `SwiftXShare.appex` (`com.apple.share-services`) puts SwiftX in the system "Share…" menu / share sheet for files, images, movies, text and links |
| DisableHotkeysOnFullscreen, HotkeyRepeatLimit | Ported — both enforced in HotkeyCenter.fire; the DisableHotkeys toggle hotkey stays live |
| Configurable actions toolbar (button list, position lock, run at startup) | Ported — ActionsToolbarList (HotkeyType names) with add/remove/reorder editor, ActionsToolbarLockPosition, ActionsToolbarRunAtStartup |

## Phase 15 — Upstream v21 additions & supportability

| Feature | Status |
|---|---|
| History.db schema re-verification vs upstream v21's new SQLite writer | Ported — verified 2026-07 against `HistoryManagerSQLite.cs`: schema, insert order, Tags JSON and date formats all match; `busy_timeout` pragma adopted; a PRAGMA table_info test guards future drift |
| Background remover | Ported — Vision `VNGenerateForegroundInstanceMaskRequest` (no model download, unlike upstream's user-supplied ONNX); Tools → Background Remover with checkerboard preview + Copy/Save, `BackgroundRemover` hotkey verb (upstream v21 name) |
| Image comparer tool (v21) | Ported — side-by-side and slider-overlay modes; `ImageComparer` hotkey verb (upstream v21 name) |
| History import folder (v21) | Ported — main window Import Folder… ingests images/media recursively (creation dates, Image/File types) |
| Editor: font family, arrow styles (classic/modern), middle-click canvas pan (v20.1–21) | Ported — font-family picker (System + installed families) for text/balloon incl. the inline entry field; Classic (filled triangle) / Modern (open chevron) arrow heads; middle-drag pans the canvas |
| Sticker packs / sticker browser | Deferred — image stamp covers local files; emoji via macOS palette |
| Log subsystem (os.Logger) + Show Log window, auto-cleanup of logs/backups | Ported — `AppLog` os.Logger subsystem (all NSLog call sites migrated), tray Show Log… window reads the session's entries via OSLogStore. Auto-cleanup knobs are N/A: the unified log owns storage/rotation and SwiftX writes no log or backup files |
| Native settings export/restore | Ported — Export/Import Settings in General settings (zip via ditto; restore only touches known file names). Keychain secrets are never exported by design — the consent story is re-entry after restore, stated in the UI. Import Settings… also accepts Windows ShareX .sxb backups (see Phase 11) |
| Themes, SilentRun, BrowserPath, white-icon variant, machine-specific config paths, taskbar progress | N/A — macOS-native equivalents (appearance, menu bar app, default browser, template icon) |
| Manual proxy configuration | N/A — URLSession follows the system proxy automatically |
