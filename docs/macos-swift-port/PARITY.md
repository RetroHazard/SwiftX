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
| After-capture tasks (21) | Planned (2) |
| After-upload tasks (6) | Planned (2) |
| Global hotkeys, all HotkeyType actions (65+) | Planned (2) |
| Notifications, sounds, Actions (external commands) | Planned (2) |

## Phase 3 — Upload engine & core destinations

| Feature | Status |
|---|---|
| Upload core (multipart, chunked, progress, retry, secondary fallback) | Planned (3) |
| OAuth1 + OAuth2 infrastructure | Planned (3) |
| Custom uploader engine (.sxcu full syntax) | Planned (3) |
| Imgur, Dropbox, Google Drive, OneDrive, Amazon S3, FTP/FTPS/SFTP, Pastebin, GitHub Gist, Email (SMTP) | Planned (3) |
| URL shorteners: is.gd, v.gd, TinyURL, bit.ly | Planned (3) |

## Phase 4 — History & main window

| Feature | Status |
|---|---|
| SQLite history + JSON/XML import from Windows | Planned (4) |
| Task list / thumbnail views, history + image history viewers | Planned (4) |

## Phase 5 — Annotation editor

| Feature | Status |
|---|---|
| Shapes: rect, ellipse, line, arrow, freehand, smart eraser, image, emoji, cursor | Planned (5) |
| Text, speech balloon, step numbers | Planned (5) |
| Effect regions: blur, pixelate, highlight, magnify, spotlight; crop/cut-out | Planned (5) |
| Undo/redo, style options, canvas expand, zoom/pan | Planned (5) |

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
