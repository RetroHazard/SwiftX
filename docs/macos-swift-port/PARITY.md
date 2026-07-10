# macOS Swift Port — Feature Parity Tracker

Statuses: **Ported** · **Partial** (works, known gaps) · **Planned** (phase noted) · **N/A** (Windows-only) · **Dead** (service defunct upstream)

## Phase 0 — Foundation

| Feature | Status | Notes |
|---|---|---|
| Menu bar app shell (tray icon equivalent) | Ported | `NSStatusItem`, accessory activation policy |
| Settings engine (JSON, Windows-compatible keys) | Ported | Fields grow per phase; unknown keys tolerated |
| Name parser macro engine | Partial | All codes ported; `%remoji` uses a curated subset, `%rf` error surfacing waits on task pipeline (Phase 2) |
| TCC permission onboarding | Ported | Screen Recording + Accessibility status/request UI |
| Single instance enforcement | Ported | flock-based; arg forwarding lands with CLI (Phase 10) |
| `sharex://` URL scheme | Partial | Registered + received; dispatch lands in Phase 2 |
| CI (build + test) | Ported | GitHub Actions, macOS runner |
| Main window | Planned (4) | Shell only |

## Phase 1 — Screen capture

| Feature | Status |
|---|---|
| Fullscreen (display under cursor) / active window capture | Ported — ActiveMonitor hotkey maps here too |
| Monitor picker / window picker capture | Ported — status-menu submenus populate on open |
| Region select overlay — rectangle, dimming, crosshair, size label, multi-display, Esc cancel | Ported |
| Region overlay — window snapping (hover highlight, click captures), last region (menu + hotkey) | Ported |
| Region overlay extras — ellipse/freehand, magnifier, fixed size, snap sizes, ruler, color picker modes | Planned (1 follow-up / 8 for ruler & color picker) |
| Save to file + subfolder patterns (name parser), clipboard copy | Ported |
| JPEG/GIF/BMP/TIFF encoders + quality, auto-JPEG for large captures | Ported — C# EImageFormat set; WebP is not a C# image format either |
| Cross-display region selection (stitching) | Planned — clamps to dominant display for now |
| Transparent/shadow window capture | N/A — ScreenCaptureKit window capture includes native shadows |

## Phase 2 — Task pipeline, hotkeys

| Feature | Status |
|---|---|
| After-capture pipeline (C#-compatible flag serialization) | Ported — 14 of 22 flags: annotate, image/file/paths to clipboard, pin, print, save, save-dialog, thumbnail, actions, show in Finder, upload, delete (Trash); remaining 8 wait on their phases (quick task menu, after-capture/before-upload windows, beautify, effects, analyze, QR, OCR) |
| Pin to screen (from capture, from clipboard, close all) | Partial — drag to move, double-click to close; resize/opacity options planned (8) |
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
| 15 adjustments, 18 filters, 10 manipulations, 8 drawings | Planned (6) |
| .sxie preset import/export | Planned (6) |
| Image beautifier | Planned (6) |

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
| Color picker, screen color picker, ruler, pin to screen | Planned (8) |
| OCR (Vision), QR generate/decode/scan | Planned (8) |
| Hash checker, metadata viewer/stripper | Planned (8) |
| Image viewer/combiner/splitter/thumbnailer, video converter/thumbnailer | Planned (8) |
| Folder indexer, clipboard viewer, monitor test, window inspector | Planned (8) |
| AI integration (OpenRouter) | Planned (8) |
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
| Watch folders, auto capture, scrolling capture | Planned (10) |
| CLI verbs, workflows, quick task menu | Planned (10) |
| Native messaging host (Chrome/Edge/Firefox) | Planned (10) |
| Safari extension | Planned (10) — evaluate, may defer |

## Phase 11 — Distribution

| Feature | Status |
|---|---|
| Developer ID signing, notarization, DMG, Homebrew cask | Planned (11) |
| Sparkle auto-update (Release/PreRelease) | Planned (11) |
| Login item, settings import from Windows backup, localization infra | Planned (11) |
| Steam build, Windows installer, DevBuilds channel | N/A |
