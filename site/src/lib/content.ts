export const links = {
  github: "https://github.com/RetroHazard/SwiftX",
  releases: "https://github.com/RetroHazard/SwiftX/releases",
  roadmap:
    "https://github.com/RetroHazard/SwiftX/blob/feat/macos-swift-port/docs/macos-swift-port/ROADMAP.md",
  parity:
    "https://github.com/RetroHazard/SwiftX/blob/feat/macos-swift-port/docs/macos-swift-port/PARITY.md",
  upstream: "https://github.com/ShareX/ShareX",
};

/* The after-capture pipeline is a real sequence, so it is the one place on
   the page where step ordering carries information the reader needs. */
export type Step = {
  id: string;
  label: string;
  title: string;
  detail: string;
  icon: string;
};

export const workflow: Step[] = [
  {
    id: "capture",
    label: "Press",
    title: "Capture",
    detail:
      "A hotkey dims the screen. Drag out a region, or hover a window to snap to its edges.",
    icon: "Crop",
  },
  {
    id: "mark",
    label: "Mark",
    title: "Annotate",
    detail:
      "Arrows, step numbers and blur land straight on the shot — no trip through another app.",
    icon: "PenTool",
  },
  {
    id: "send",
    label: "Send",
    title: "Upload",
    detail:
      "It goes to your own bucket or host in the background while you carry on working.",
    icon: "UploadCloud",
  },
  {
    id: "paste",
    label: "Paste",
    title: "Link is ready",
    detail:
      "The URL is on your clipboard before the window closes. Paste it and move on.",
    icon: "Link",
  },
];

/* Effect names paired with the CSS that approximates them in the preview
   strip. The app renders these properly; the page only has to suggest them. */
export type EffectSwatch = {
  name: string;
  css: string;
};

export const effectSwatches: EffectSwatch[] = [
  { name: "Original", css: "none" },
  { name: "Grayscale", css: "grayscale(1) contrast(1.05)" },
  { name: "Sepia", css: "sepia(0.85) saturate(1.3)" },
  { name: "Invert", css: "invert(1) hue-rotate(180deg)" },
  { name: "Gaussian blur", css: "blur(2.5px) saturate(1.1)" },
  { name: "Hue shift", css: "hue-rotate(140deg) saturate(1.5)" },
  { name: "Contrast", css: "contrast(1.85) saturate(1.15)" },
  { name: "Bloom", css: "brightness(1.22) saturate(1.6) blur(0.5px)" },
];

export type Destination = {
  name: string;
  kind: string;
};

export const destinations: Destination[] = [
  { name: "Amazon S3", kind: "Storage" },
  { name: "Backblaze B2", kind: "Storage" },
  { name: "Azure Blob", kind: "Storage" },
  { name: "Nextcloud", kind: "Self-hosted" },
  { name: "ownCloud", kind: "Self-hosted" },
  { name: "SFTP", kind: "Self-hosted" },
  { name: "Imgur", kind: "Image host" },
  { name: "Custom", kind: ".sxcu" },
];

export type Hotkey = {
  keys: string[];
  action: string;
};

export const hotkeys: Hotkey[] = [
  { keys: ["⌘", "⇧", "4"], action: "Capture region" },
  { keys: ["⌘", "⇧", "5"], action: "Record screen" },
  { keys: ["⌘", "⇧", "O"], action: "Grab text on screen" },
  { keys: ["⌘", "⇧", "C"], action: "Pick a colour" },
];

export type FaqItem = {
  question: string;
  answer: string;
};

export const faqs: FaqItem[] = [
  {
    question: "Can I download it today?",
    answer:
      "Not as a signed build yet. SwiftX is pre-release — code signing, notarization and a Homebrew cask are the last pieces before a public download. Until then you can clone the repository and build it with Swift Package Manager.",
  },
  {
    question: "What does it need to run?",
    answer:
      "macOS 14 Sonoma or later, on Apple silicon or Intel. That is the baseline for the ScreenCaptureKit APIs the capture and recording pipeline is built on.",
  },
  {
    question: "Do my screenshots pass through your servers?",
    answer:
      "No. There is no SwiftX account and no SwiftX backend. Uploads go straight from your Mac to whichever destination you set up — your own S3 bucket, your Nextcloud, an image host, or nowhere at all if you only save locally.",
  },
  {
    question: "I already use ShareX on Windows. Does my setup come with me?",
    answer:
      "Largely, yes. SwiftX reads the same custom uploader (.sxcu) and image effect preset (.sxie) files, keeps a compatible history database, and works with the existing browser extensions — so destinations and presets you have already tuned carry over.",
  },
  {
    question: "Is this the official ShareX for Mac?",
    answer:
      "No. SwiftX is an independent app, written from scratch in Swift and SwiftUI. It follows the capture-to-upload workflow ShareX made popular and stays compatible with its config files, but it is not a build of ShareX and is not affiliated with or endorsed by that project.",
  },
  {
    question: "Why not just wrap the Windows app?",
    answer:
      "A compatibility layer cannot give you real global hotkeys, recording of arbitrary windows, or folder watching inside the macOS sandbox. Building directly against ScreenCaptureKit, Vision and AVFoundation is what makes it behave like a Mac app instead of a port.",
  },
];
