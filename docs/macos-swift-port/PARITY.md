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
| Fullscreen (display under cursor) / active window capture | Ported |
| Monitor picker / window picker capture | Planned (1) |
| Region select overlay — rectangle, dimming, crosshair, size label, multi-display, Esc cancel | Ported |
| Region overlay extras — ellipse/freehand, magnifier, window/control snapping, fixed size, snap sizes, last region, ruler, color picker modes | Planned (1–8) |
| Save to file + subfolder patterns (name parser), clipboard copy | Ported |
| JPEG/WebP/TIFF encoders + quality settings | Planned (1) |
| Cross-display region selection (stitching) | Planned — clamps to dominant display for now |
| Transparent/shadow window capture | N/A — ScreenCaptureKit window capture includes native shadows |

## Phase 2 — Task pipeline, hotkeys

| Feature | Status |
|---|---|
| After-capture pipeline (C#-compatible flag serialization) | Ported — 7 of 22 flags implemented: clipboard, save, save-dialog, pin, file/folder path copy, show in Finder; rest dispatch as stubs |
| Pin to screen (from capture, from clipboard, close all) | Partial — drag to move, double-click to close; resize/opacity options planned (8) |
| After-upload tasks (6) | Planned (3) — flags model ready |
| Global hotkey engine (Carbon), defaults ⌃⇧3/4/5, DisableHotkeys toggle | Ported — recorder UI planned, edit JSON for now |
| HotkeyType vocabulary (C#-compatible raw values) | Ported — 7 actions implemented, rest dispatch as stubs |
| Capture notifications | Partial — banner on save; sounds/click actions planned |
| Actions (external commands) | Planned (2) |

## Phase 3 — Upload engine & core destinations

| Feature | Status |
|---|---|
| Upload core — multipart, form-urlencoded, JSON/XML body, binary | Ported |
| Upload core — chunked/resumable, progress UI, retry, secondary fallback | Planned (3) |
| Custom uploader engine (.sxcu) — syntax parser (json/regex/base64/random/select/filename/header/response), import, destination picker | Ported — `{xml:…}` function and legacy `$var$` syntax unsupported; interactive select takes first option |
| OAuth1 + OAuth2 infrastructure | Planned (3) |
| Amazon S3 (+ S3-compatible via custom endpoint) — SigV4, prefix patterns | Ported |
| Imgur, Dropbox, Google Drive, OneDrive, FTP/FTPS/SFTP, Pastebin, GitHub Gist, Email (SMTP) | Planned (3) — many work today via community .sxcu files |
| URL shorteners: is.gd, v.gd, TinyURL (keyless) | Ported — wired to UseURLShortener flag |
| URL shorteners requiring keys: bit.ly, Polr, Kutt, YOURLS | Planned (9) |
| After-upload: copy URL to clipboard, open URL | Ported |

## Phase 4 — History & main window

| Feature | Status |
|---|---|
| SQLite history (Windows-compatible History.db schema) | Ported — a Windows History.db opens directly |
| JSON/XML history import from Windows | Planned (4/11) |
| Main window: searchable history list, thumbnails, context actions | Ported — search by name/URL/host |
| Thumbnail grid view (persisted TaskViewMode), time-range filter, favorites (Windows-compatible "Favorite" tag) | Ported |
| Tag filters (window title/process), stats | Planned (4) |
| Live task queue with upload progress rows | Planned (7) — deferred until recording makes progress worth watching |

## Phase 5 — Annotation editor

| Feature | Status |
|---|---|
| Shapes: rectangle, ellipse, line, arrow, freehand | Ported |
| Text (inline entry), step numbers (auto-increment) | Ported |
| Effect regions: blur, pixelate, highlight | Ported |
| Undo/redo, color/width controls, AnnotateImage pipeline flag (Cancel aborts task) | Ported |
| Shape selection, move, resize handles, Delete, double-click text re-edit, recolor selection | Ported — Screenshot.app-style manipulation |
| Smart eraser, image/emoji/cursor stamps, speech balloon, magnify, spotlight, crop/cut-out | Planned (5 follow-up) |
| Canvas expand, zoom/pan, border/fill/shadow style options | Planned (5 follow-up) |

## Phase 6 — Image effects

| Feature | Status |
|---|---|
| 15 adjustments, 18 filters, 10 manipulations, 8 drawings | Planned (6) |
| .sxie preset import/export | Planned (6) |
| Image beautifier | Planned (6) |

## Phase 7 — Screen recording

| Feature | Status |
|---|---|
| H.264/HEVC recording (region/window/screen, audio, pause) | Planned (7) |
| GIF recording | Planned (7) |
| VP8/VP9/WebP/APNG via ffmpeg, custom ffmpeg args | Planned (7) |
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
| Box, Backblaze B2, Azure, GCS, YouTube, Streamable, Nextcloud/ownCloud, Seafile, MediaFire, Puush, Pushbullet, transfer.sh, Pomf, Plik, s-ul, Uguu, Lambda, LobFile, vgy.me, Chevereto, ImageShack, Flickr, Photobucket, remaining text hosts | Planned (9) |
| Remaining shorteners: Polr, Kutt, YOURLS, Firebase, qr.net, 2.gp, vurl, zws | Planned (9) |
| URL sharing services (Facebook, Reddit, Pinterest, Tumblr, LinkedIn, VK, Google Lens, Bing VS, …) | Planned (9) |
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
