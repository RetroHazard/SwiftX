# macOS Swift Port — Feature Parity Tracker

Statuses: **Ported** · **Partial** (works, known gaps) · **Planned** (phase noted) · **N/A** (Windows-only) · **Dead** (service defunct upstream)

## Phase 0 — Foundation

| Feature | Status | Notes |
|---|---|---|
| Menu bar app shell (tray icon equivalent) | Ported | `NSStatusItem`, accessory activation policy |
| Settings engine (JSON, Windows-compatible keys) | Ported | Fields grow per phase; unknown keys tolerated |
| Name parser macro engine | Partial | All codes ported; `%remoji` uses a curated subset, `%rf` error surfacing waits on task pipeline (Phase 2) |
| TCC permission onboarding | Ported | Screen Recording + Accessibility status/request UI |
| Single instance enforcement | Ported | flock-based; second instance forwards argv over distributed notifications and exits |
| `sharex://` URL scheme | Partial | Registered + received; dispatch lands in Phase 2 |
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
| Save to file + subfolder patterns (name parser), clipboard copy | Ported |
| JPEG/GIF/BMP/TIFF encoders + quality, auto-JPEG for large captures | Ported — C# EImageFormat set; WebP is not a C# image format either |
| Cross-display region selection (stitching) | Ported — per-display captures composited at the highest backing scale |
| Transparent/shadow window capture | N/A — ScreenCaptureKit window capture includes native shadows |

## Phase 2 — Task pipeline, hotkeys

| Feature | Status |
|---|---|
| After-capture pipeline (C#-compatible flag serialization) | Ported — all 22 flags: beautify, effects, annotate, image/file/paths to clipboard, pin, print, save, save-dialog, thumbnail, actions, show in Finder, analyze (AI), scan QR, OCR, upload, delete (Trash), quick task menu, after-capture window, before-upload window |
| Pin to screen (from capture, clipboard, file, screen region, close all) | Ported — drag to move, double-click to close, scroll/± to scale, ⌘-scroll/⌘± for opacity (C# 10% steps), right-click menu (copy, save, close all) |
| After-upload tasks (6) | Planned (3) — flags model ready |
| Global hotkey engine (Carbon), defaults ⌃⇧3/4/5, DisableHotkeys toggle | Ported — recorder UI in Settings, live re-registration |
| HotkeyType vocabulary (C#-compatible raw values) | Ported — capture/record/pin/window actions implemented, rest dispatch as stubs |
| Capture notifications | Ported — banner + optional sound (C# PlaySound keys); click reveals file or opens URL |
| Actions (external commands) | Ported — C# ExternalProgram JSON, $input/$output placeholders, output-extension chaining, Settings pane |

## Phase 3 — Upload engine & core destinations

| Feature | Status |
|---|---|
| Upload core — multipart, form-urlencoded, JSON/XML body, binary | Ported |
| Upload core — progress UI, retry | Ported — live rows in main window (bar, retry state, URL/error); RetryUpload retries once |
| Upload core — chunked/resumable, secondary fallback | Planned — chunked only serves the benched OAuth hosts; fallback needs multi-destination config |
| Custom uploader engine (.sxcu) — syntax parser (json/xml/regex/base64/random/select/filename/header/response), import, destination picker | Ported — legacy pre-13.7.1 `$var$` files migrate at load; interactive select takes first option |
| Custom uploader editor (create/edit/duplicate/delete in settings) | Ported — Settings → Custom Uploader pane; edits write Windows-compatible .sxcu files |
| OAuth1 + OAuth2 infrastructure | Planned (3) |
| Amazon S3 (+ S3-compatible via custom endpoint) — SigV4, prefix patterns | Ported |
| Imgur, Dropbox, Google Drive, OneDrive, FTP/FTPS/SFTP, Pastebin, GitHub Gist, Email (SMTP) | Planned (3) — many work today via community .sxcu files |
| URL shorteners: is.gd, v.gd, TinyURL (keyless) | Ported — wired to UseURLShortener flag |
| URL shorteners requiring keys: bit.ly, Polr, Kutt, YOURLS | Ported (9) — see Phase 9 |
| After-upload: copy URL to clipboard, open URL | Ported |

## Phase 4 — History & main window

| Feature | Status |
|---|---|
| SQLite history (Windows-compatible History.db schema) | Ported — a Windows History.db opens directly |
| JSON/XML history import from Windows | Planned (4/11) |
| Main window: searchable history list, thumbnails, context actions | Ported — search by name/URL/host |
| Thumbnail grid view (persisted TaskViewMode), time-range filter, favorites (Windows-compatible "Favorite" tag) | Ported |
| Tag filters (window title/process), stats | Planned (4) |
| Live task queue with upload progress rows | Ported — upload rows above the history list (progress bar, retry state, URL/error) |

## Phase 5 — Annotation editor

| Feature | Status |
|---|---|
| Shapes: rectangle, ellipse, line, arrow, freehand | Ported |
| Text (inline entry), step numbers (auto-increment) | Ported |
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
| Box, GCS, YouTube, Dropbox-family, Flickr, Photobucket | Benched — need OAuth1/OAuth2 app credentials; revisit if per-user client keys become acceptable |
| MediaFire (session signing), Plik (session protocol), ImageShack (login flow), Lambda (canonical domain down), remaining text hosts | Planned (9 follow-up) |
| transfer.sh | Dead — public instance offline, verified 2026-07 |
| Shorteners: bit.ly (personal access token), Polr, Kutt, YOURLS, Zero Width, vurl.com | Ported — settings UI per service; bit.ly uses a user token instead of C#'s app-key OAuth flow |
| URL sharing services (Email/mailto, Facebook, Reddit, Pinterest, Tumblr, LinkedIn, VK, Google Lens, Bing VS) | Ported — ShareURL flag opens the share page in the browser; Pushbullet + custom sharing land with their destinations |
| Firebase Dynamic Links (Google shutdown 2025), qr.net, 2.gp, turl.ca, nl.cm | Dead — API endpoints verified gone 2026-07 |
| Copy, StumbleUpon, Delicious, DropIO, Slexy | Dead — verify & drop |

## Phase 10 — Automation & integration

| Feature | Status |
|---|---|
| Watch folders | Ported — FSEvents watcher with glob filter, subdirectories, move-to-screenshots, C# size-stability gate; Settings pane |
| Auto capture | Ported — region/full-screen repeat timer, wait-for-uploads, C# AutoCapture* keys; annotate/menus stripped per shot like C# |
| Scrolling capture | Ported — synthetic scroll-wheel events + C# CombineImages row-matching stitcher (side margins, auto bottom-edge trim, best-guess fallback); Windows-message scroll methods N/A |
| Quick task menu (ShowQuickTaskMenu) + editor | Ported — C# QuickTaskPresets JSON incl. separators; menu at cursor |
| After-capture / before-upload windows | Ported — filename + task toggles; destination override before upload (all sources) |
| CLI verbs, workflows | Ported — -HotkeyTypeName [file], -workflow, -CustomUploader .sxcu, -ImageEffect .sxie, -NativeMessagingInput .json, bare path/URL upload; second instance forwards to primary |
| Native messaging host (Chrome/Edge/Firefox) | Ported — SwiftXHost binary in bundle speaks the Chrome stdio protocol; manifest install toggle in General settings |
| Safari extension | Deferred — needs an Xcode app-extension target + separate distribution; revisit after Phase 11 signing |

## Phase 11 — Distribution

| Feature | Status |
|---|---|
| Developer ID signing, notarization, DMG, Homebrew cask | Planned (11) |
| Sparkle auto-update (Release/PreRelease) | Planned (11) |
| Login item, settings import from Windows backup, localization infra | Planned (11) |
| Steam build, Windows installer, DevBuilds channel | N/A |
