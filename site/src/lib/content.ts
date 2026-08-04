/**
 * How people get the app.
 *
 * SwiftX ships as a Developer ID-signed, notarized .dmg on GitHub Releases and
 * through a Homebrew cask, built by the automated release pipeline
 * (.github/workflows/release.yml).
 *
 * Keep `version` and `minMacOS` in step with Casks/swiftx.rb and
 * Package.swift's platform baseline.
 */
export type Release = {
  version: string;
  minMacOS: string;
  /** Matches the url stanza in Casks/swiftx.rb. */
  dmgUrl: string;
  brewCommand: string;
};

const version = "2026.8.1";

export const release: Release = {
  version,
  minMacOS: "macOS 14 Sonoma or later",
  dmgUrl: `https://github.com/RetroHazard/SwiftX/releases/download/v${version}/SwiftX-${version}.dmg`,
  // The SwiftX repo doubles as the Homebrew tap (no homebrew- prefix), so the
  // shorthand auto-tap doesn't apply — tap by URL first, then install.
  brewCommand:
    "brew tap retrohazard/swiftx https://github.com/RetroHazard/SwiftX && brew install --cask swiftx",
};

export const links = {
  github: "https://github.com/RetroHazard/SwiftX",
  releases: "https://github.com/RetroHazard/SwiftX/releases",
  parity:
    "https://github.com/RetroHazard/SwiftX/blob/master/docs/macos-swift-port/PARITY.md",
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
  { name: "Inverse", css: "invert(1) hue-rotate(180deg)" },
  { name: "Gaussian blur", css: "blur(2.5px) saturate(1.1)" },
  { name: "Hue", css: "hue-rotate(140deg) saturate(1.5)" },
  { name: "Contrast", css: "contrast(1.85) saturate(1.15)" },
  { name: "Glow", css: "brightness(1.22) saturate(1.6) blur(0.5px)" },
];

export type Destination = {
  name: string;
  kind: string;
};

/* Every name here must have a real uploader in Sources/UploadKit — this grid
   is a sample of what ships, not a wish list. Google Drive, YouTube and
   OneDrive stay in the list (not just in the privacy policy) because Google's
   OAuth verification checks that the home page actually shows the
   functionality behind the scopes it is granting — see site/README.md. */
export const destinations: Destination[] = [
  { name: "Amazon S3", kind: "Storage" },
  { name: "Backblaze B2", kind: "Storage" },
  { name: "Azure Blob", kind: "Storage" },
  { name: "Nextcloud", kind: "Self-hosted" },
  { name: "ownCloud", kind: "Self-hosted" },
  { name: "Seafile", kind: "Self-hosted" },
  { name: "Chevereto", kind: "Image host" },
  { name: "Google Drive", kind: "Connected account" },
  { name: "YouTube", kind: "Connected account" },
  { name: "OneDrive", kind: "Connected account" },
  { name: "Custom", kind: ".sxcu" },
];

export type Hotkey = {
  keys: string[];
  action: string;
};

/* The first three are the app's actual defaults (⌃⇧ so they never fight
   macOS's own ⌘⇧3/4/5 shortcuts); the last is a custom binding of the kind
   the panel is inviting. Keep this list in step with the defaults seeded in
   Sources/SwiftXApp/AppDelegate.swift. */
export const hotkeys: Hotkey[] = [
  { keys: ["⌃", "⇧", "3"], action: "Capture full screen" },
  { keys: ["⌃", "⇧", "4"], action: "Capture region" },
  { keys: ["⌃", "⇧", "5"], action: "Capture active window" },
  { keys: ["⌃", "⇧", "O"], action: "Grab text on screen" },
];

export type FaqItem = {
  question: string;
  answer: string;
};

export const faqs: FaqItem[] = [
  {
    question: "How will I install it?",
    answer:
      "Two ways: download the .dmg straight from the GitHub releases page, or tap the SwiftX repo with `brew tap retrohazard/swiftx https://github.com/RetroHazard/SwiftX` and install with `brew install --cask swiftx`. Builds are signed with an Apple Developer ID and notarized, so Gatekeeper opens them without a right-click or a trip to System Settings. Either way the app keeps itself up to date afterwards. Building from source works too, if you'd rather compile it yourself.",
  },
  {
    question: "How do I get updates?",
    answer:
      "SwiftX checks for them itself. Choose Check for Updates… from the menu bar whenever you like, or leave the automatic check on — daily by default, with weekly, monthly and off as alternatives in Settings → Updates. When a new version is out you get a notification and can install it in place; turn on automatic installs and it handles that too. Downloads are checked against the release's published SHA-256 and must be signed by the same Apple Developer ID as the copy you're running before anything is replaced. Installed with Homebrew? SwiftX notices and points you at `brew upgrade --cask swiftx` instead, so brew stays the source of truth for that copy.",
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
    question: "What can SwiftX do with my Google or Microsoft account?",
    answer:
      "Only what you connect it for. Signing in opens your browser at Google's or Microsoft's own consent screen — SwiftX never sees your password. A connected Google account can upload a file to your Drive (limited to files SwiftX itself creates) or a video to your YouTube channel as unlisted; a connected Microsoft account can upload a file to your OneDrive. Nothing else in your account is read, listed or changed. Tokens live in the macOS Keychain, and you can disconnect and revoke access at any time — details are in the Privacy Policy.",
  },
  {
    question: "Why does Google Drive, YouTube or OneDrive say the app is unverified?",
    answer:
      "Because SwiftX's registration with those providers is still in review — the Google submission is pending and the Microsoft one needs a Partner Center business account. The destinations work regardless. That warning is about SwiftX's paperwork with Google and Microsoft, not about what it does with your files: uploads go straight from your Mac to your own account, and the access tokens stay in your login Keychain. On Google's screen, choose Advanced, then \"Go to SwiftX (unsafe)\". Every other destination is unaffected.",
  },
  {
    question: "I already use ShareX on Windows. Does my setup come with me?",
    answer:
      "Largely, yes. Import Settings… in SwiftX reads a Windows ShareX .sxb backup directly and merges its custom uploaders, hotkeys, and (optionally) upload history into your Mac config in one step. Short of a full backup, SwiftX also reads the same custom uploader (.sxcu) and image effect preset (.sxie) files on their own, keeps a compatible history database, and works with the existing browser extensions.",
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
