export const links = {
  github: "https://github.com/RetroHazard/SwiftX",
  releases: "https://github.com/RetroHazard/SwiftX/releases",
  roadmap:
    "https://github.com/RetroHazard/SwiftX/blob/feat/macos-swift-port/docs/macos-swift-port/ROADMAP.md",
  parity:
    "https://github.com/RetroHazard/SwiftX/blob/feat/macos-swift-port/docs/macos-swift-port/PARITY.md",
  upstream: "https://github.com/ShareX/ShareX",
};

export type Feature = {
  title: string;
  description: string;
  icon: string;
};

export const features: Feature[] = [
  {
    title: "Screen Capture",
    description:
      "Fullscreen, window, and freeform region capture with a native overlay — magnifier, fixed sizes, snap presets, and multi-display stitching built on ScreenCaptureKit.",
    icon: "Crop",
  },
  {
    title: "Screen Recording",
    description:
      "H.264/HEVC and GIF recording with pause/resume, system + microphone audio, and WebM/VP9/VP8/APNG export via a detected local ffmpeg.",
    icon: "Video",
  },
  {
    title: "Annotation Editor",
    description:
      "A Screenshot.app-style canvas — shapes, step numbers, blur/pixelate regions, speech balloons, smart eraser, magnify, spotlight, and undoable crop.",
    icon: "PenTool",
  },
  {
    title: "51 Image Effects",
    description:
      "Every adjustment, filter, manipulation, and drawing from the original, reproduced with C#-exact matrices and kernels, plus live-preview presets.",
    icon: "Sparkles",
  },
  {
    title: "20+ Upload Destinations",
    description:
      "Amazon S3, Backblaze B2, Azure, ownCloud/Nextcloud, Imgur, and a full custom-uploader engine that reads your existing .sxcu files.",
    icon: "UploadCloud",
  },
  {
    title: "Searchable History",
    description:
      "A Windows-compatible SQLite history store with thumbnail grid view, tag filters, favorites, and live upload progress rows.",
    icon: "History",
  },
  {
    title: "Automation",
    description:
      "Watch folders, auto capture, scrolling capture, global hotkeys, CLI verbs, and a sharex:// URL scheme that behaves like the original.",
    icon: "Workflow",
  },
  {
    title: "AI & Vision Tools",
    description:
      "Vision-powered OCR and QR scanning, plus an OpenAI-compatible AI analysis pipeline for OpenAI, OpenRouter, and Gemini.",
    icon: "BrainCircuit",
  },
  {
    title: "Menu Bar Native",
    description:
      "A true NSStatusItem menu bar app with Carbon global hotkeys, TCC-aware permission onboarding, and single-instance enforcement.",
    icon: "AppWindow",
  },
];

export type Stat = {
  value: string;
  label: string;
};

export const stats: Stat[] = [
  { value: "12", label: "Build phases, foundation to distribution" },
  { value: "51", label: "Image effects ported bit-for-bit" },
  { value: "20+", label: "Upload destinations wired up" },
  { value: "100%", label: "Swift & SwiftUI — zero Electron" },
];

export type ParityRow = {
  phase: string;
  title: string;
  detail: string;
};

export const parityPhases: ParityRow[] = [
  { phase: "0", title: "Foundation", detail: "Menu bar shell, settings engine, TCC onboarding, CI — Ported" },
  { phase: "1", title: "Screen capture", detail: "Region overlay, window snapping, multi-display stitching — Ported" },
  { phase: "2", title: "Task pipeline & hotkeys", detail: "22-flag after-capture pipeline, global hotkeys, actions — Ported" },
  { phase: "3", title: "Upload engine", detail: "Custom uploaders, OAuth2 + PKCE, S3, URL shorteners — Ported" },
  { phase: "4", title: "History & main window", detail: "SQLite history, thumbnail grid, live task queue — Ported" },
  { phase: "5", title: "Annotation editor", detail: "Shapes, effects regions, speech balloons, cut-out — Ported" },
  { phase: "6", title: "Image effects", detail: "51 adjustments/filters/manipulations/drawings — Ported" },
  { phase: "7", title: "Screen recording", detail: "H.264/HEVC/GIF, pause/resume, ffmpeg transcodes — Ported" },
  { phase: "8", title: "Tools", detail: "Color picker, OCR, QR, hash checker, AI analysis — Ported" },
  { phase: "9", title: "Destination long tail", detail: "Uguu/Pomf clones, B2, Azure, shorteners — Ported" },
  { phase: "10", title: "Automation & integration", detail: "Watch folders, CLI verbs, native messaging host — Ported" },
  { phase: "11", title: "Distribution", detail: "Signing, notarization, Sparkle updates — Planned" },
];

export type FaqItem = {
  question: string;
  answer: string;
};

export const faqs: FaqItem[] = [
  {
    question: "Is this the official ShareX macOS app?",
    answer:
      "No. SwiftX is an independent, ground-up native port written in Swift and SwiftUI, built from an inventory of the original C# codebase. It isn't affiliated with or endorsed by the ShareX project.",
  },
  {
    question: "Why a rewrite instead of a wrapper?",
    answer:
      "ShareX is a Windows Forms app tied to GDI+, Win32 hotkeys, and DirectShow. There's no compatibility layer that gets you global hotkeys, arbitrary-app screen recording, and watch folders inside App Sandbox — so SwiftX targets ScreenCaptureKit, Carbon hotkeys, and Vision directly instead.",
  },
  {
    question: "Does it read my existing ShareX settings?",
    answer:
      "Settings, custom uploaders (.sxcu), image effect presets (.sxie), and History.db all use Windows-compatible formats and keys, so files carry over directly.",
  },
  {
    question: "What macOS version does it need?",
    answer:
      "macOS 14 or later — the baseline for the ScreenCaptureKit screenshot APIs the capture pipeline is built on.",
  },
  {
    question: "Where do I get it?",
    answer:
      "SwiftX is still pre-release. Signed builds, notarization, and a Homebrew cask are tracked in Phase 11 of the roadmap. Until then, build it from source with Swift Package Manager.",
  },
];
