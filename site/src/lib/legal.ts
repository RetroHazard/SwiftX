/**
 * The Privacy Policy and Terms of Service, as data.
 *
 * These two pages exist because Google and Microsoft both require a published
 * privacy policy (and Microsoft a terms-of-service URL) before they will
 * approve the OAuth app registrations behind the Google Drive, YouTube and
 * OneDrive destinations. Google's OAuth verification reads the policy line by
 * line, so the `google` section states scopes, use, storage, sharing and the
 * Limited Use disclosure explicitly — do not soften or shorten it.
 *
 * Everything asserted here has to stay true of the code. When a destination,
 * scope, stored file or network call changes in Sources/, this file changes in
 * the same commit, and `effective` moves.
 *
 * Prose is plain text with two inline marks, rendered by LegalDoc:
 *   [label](https://example.com)  → link
 *   `code`                        → monospace
 */

export type LegalBlock =
  /** Body paragraph. */
  | { kind: "p"; text: string }
  /** Bulleted list. Leading "**Term** — " in an item renders as a lead-in. */
  | { kind: "list"; items: string[] }
  /** Boxed statement. Reserved for disclosures that must not be skimmed past. */
  | { kind: "callout"; title: string; text: string };

export type LegalSection = {
  /** Anchor id — also the contents-list target. Keep stable: these get linked. */
  id: string;
  heading: string;
  blocks: LegalBlock[];
};

export type LegalDoc = {
  title: string;
  /** Used for the page <title> and the meta description. */
  description: string;
  /** Human-readable, e.g. "25 July 2026". */
  effective: string;
  lede: string;
  sections: LegalSection[];
};

const issues = "https://github.com/RetroHazard/SwiftX/issues";

export const privacy: LegalDoc = {
  title: "Privacy Policy",
  description:
    "SwiftX has no account, no server and no telemetry. What the app stores on your Mac, what it sends where, and how connected Google and Microsoft accounts are handled.",
  effective: "4 August 2026",
  lede: "SwiftX has no account, no backend and no telemetry. Your captures stay on your Mac unless you set up a destination to send them to — and then they go straight there, never through us.",
  sections: [
    {
      id: "scope",
      heading: "What this policy covers",
      blocks: [
        {
          kind: "p",
          text: "SwiftX is a native macOS screen capture app developed in the open by the SwiftX project (\"SwiftX\", \"the project\", \"we\"). This policy covers the SwiftX app for macOS and this website. It explains what the app does with your data, what leaves your machine and where it goes, and what the people who write SwiftX can and cannot see.",
        },
        {
          kind: "p",
          text: "SwiftX is free software licensed under the GNU General Public License v3. There is no SwiftX account, no SwiftX server, no paid tier and no company behind it collecting anything.",
        },
      ],
    },
    {
      id: "not-collected",
      heading: "What we do not collect",
      blocks: [
        {
          kind: "list",
          items: [
            "**No account.** There is no sign-up, no login and no SwiftX user identity. Nothing about you is registered anywhere.",
            "**No backend.** The project runs no servers that receive your captures, recordings, files, settings or metadata.",
            "**No telemetry or analytics.** The app sends no usage statistics, crash reports, device identifiers or diagnostics — not to us, not to anyone.",
            "**Nothing about you in the update check.** SwiftX asks GitHub for the version number of its latest release — the same public address anyone can open in a browser. It sends no identifiers and says nothing about you or your Mac, and you can turn it off entirely. \"Checking for updates\" below describes it in full.",
            "**No advertising, profiling or sale of data.** There is nothing to sell, because nothing reaches us.",
          ],
        },
        {
          kind: "p",
          text: "That is a property of how the app is built rather than a promise you have to take on trust. The source is public at [github.com/RetroHazard/SwiftX](https://github.com/RetroHazard/SwiftX), and the network calls SwiftX makes are the ones described below — the destinations you configure, the update check, and nothing else.",
        },
      ],
    },
    {
      id: "on-your-mac",
      heading: "What SwiftX stores on your Mac",
      blocks: [
        {
          kind: "p",
          text: "Everything the app keeps, it keeps locally, in your own user account:",
        },
        {
          kind: "list",
          items: [
            "**Captures and recordings** — written to `~/Pictures/SwiftX` by default, or to whichever folder you choose.",
            "**History** — a `History.db` SQLite file in `~/Library/Application Support/SwiftX` recording each task's file name, path, date, type, destination host and resulting URLs.",
            "**Settings** — JSON files in the same folder holding your hotkeys, capture preferences, workflows, watched folders, image-effect presets, destination configuration, and update preferences (how often to check, and the time of the last check).",
            "**Logs** — a local troubleshooting log. It is written for you to read; it is never transmitted.",
            "**Credentials** — API keys, upload tokens and OAuth access and refresh tokens live in the macOS Keychain, not in the JSON settings.",
          ],
        },
        {
          kind: "p",
          text: "All of it is yours. Delete those folders and it is gone, because nothing is mirrored anywhere else.",
        },
      ],
    },
    {
      id: "permissions",
      heading: "macOS permissions the app asks for",
      blocks: [
        {
          kind: "p",
          text: "macOS grants these, not us, and you can withdraw any of them at any time in System Settings → Privacy & Security:",
        },
        {
          kind: "list",
          items: [
            "**Screen Recording** — required by ScreenCaptureKit for every screenshot and screen recording. Without it the app cannot capture anything.",
            "**Accessibility** — used for window snapping, scrolling capture and the window tools, which need to read and move window geometry.",
            "**Microphone** — requested only if you turn on \"Record microphone\" for a screen recording. Audio is written into that recording's file and nowhere else.",
            "**Files and folders** — to write captures to the folder you pick and to watch any folders you configure.",
          ],
        },
        {
          kind: "p",
          text: "SwiftX runs outside the App Sandbox because it launches helper binaries such as ffmpeg and the shell that runs your custom Actions. It ships under the macOS hardened runtime with no entitlement exceptions.",
        },
      ],
    },
    {
      id: "destinations",
      heading: "Uploads go where you send them",
      blocks: [
        {
          kind: "p",
          text: "SwiftX uploads nothing by default. When you configure a destination, the file is transferred directly from your Mac to that destination. It does not pass through project infrastructure at any point, and the project keeps no copy, no log and no record of it.",
        },
        {
          kind: "p",
          text: "The destinations you can choose from include:",
        },
        {
          kind: "list",
          items: [
            "**Your own storage** — Amazon S3, Backblaze B2, Azure Blob and S3-compatible endpoints, using credentials you supply.",
            "**Your own servers** — Nextcloud, ownCloud, Seafile and similar self-hosted destinations.",
            "**Third-party hosts** — image, file and video hosts, and any service reachable through a custom uploader (`.sxcu`) definition.",
            "**Connected accounts** — Google Drive, YouTube and OneDrive, covered in their own sections below.",
            "**URL shorteners** — when you shorten a link, the URL (not the file) is sent to the shortener you picked.",
            "**Share links** — the \"share\" actions open your browser at a third-party site with the URL as a parameter. Nothing is uploaded by that action; your browser makes the request.",
          ],
        },
        {
          kind: "p",
          text: "Once a file reaches a destination it is governed by that provider's privacy policy and terms, not by this one. Choose destinations you trust, and remember that a public image host means a publicly reachable URL.",
        },
      ],
    },
    {
      id: "google",
      heading: "Google user data (Google Drive and YouTube)",
      blocks: [
        {
          kind: "p",
          text: "Connecting a Google destination is optional and inert until you click Connect. Sign-in happens in your own browser, against Google's own consent screen, using OAuth 2.0 with PKCE and a loopback redirect to `http://127.0.0.1`. SwiftX never sees or handles your Google password.",
        },
        {
          kind: "p",
          text: "**Scopes requested.** SwiftX asks for the narrowest scope that lets the feature work:",
        },
        {
          kind: "list",
          items: [
            "`https://www.googleapis.com/auth/drive.file` — per-file access to Google Drive, limited to files SwiftX itself creates. It gives SwiftX no ability to list, open, modify or delete anything else in your Drive.",
            "`https://www.googleapis.com/auth/youtube.upload` — permission to upload a video to your own channel. Uploads are created as unlisted. It grants no access to your account details, comments, subscribers, playlists or analytics.",
          ],
        },
        {
          kind: "p",
          text: "**How Google user data is accessed, used, stored and shared:**",
        },
        {
          kind: "list",
          items: [
            "**Accessed** — only when you run an upload. SwiftX uses the token to create the file you asked it to create and, for Drive, to set the sharing permission that makes the returned link usable.",
            "**Used** — solely to deliver that upload and hand you back its link. For no other purpose, and never to build a profile of you.",
            "**Stored** — the OAuth access and refresh tokens are stored in the macOS Keychain on your own Mac. The resulting file ID and link are written to your local history. No Google user data is stored on any system operated by the project, because the project operates none.",
            "**Shared** — with nobody. SwiftX transfers no Google user data to any third party, uses none of it for advertising, sells none of it, and uses none of it to develop, improve or train generalized AI or machine-learning models. Humans do not read it; no one on the project can, as it never leaves your machine.",
            "**Deleted** — disconnect the account in SwiftX to erase its tokens from the Keychain immediately, then revoke the grant at Google as below.",
          ],
        },
        {
          kind: "callout",
          title: "Limited Use disclosure",
          text: "SwiftX's use and transfer of information received from Google APIs to any other app will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.",
        },
        {
          kind: "p",
          text: "You can review or revoke SwiftX's access to your Google account at any time at [myaccount.google.com/permissions](https://myaccount.google.com/permissions). Revoking there stops all further access even if the app is still installed.",
        },
      ],
    },
    {
      id: "microsoft",
      heading: "Microsoft account data (OneDrive)",
      blocks: [
        {
          kind: "p",
          text: "OneDrive works the same way and is equally optional. Sign-in happens in your browser against Microsoft's own consent screen, using OAuth 2.0 with PKCE and a loopback redirect to `http://127.0.0.1`. SwiftX is registered as a public client and never sees your Microsoft password.",
        },
        {
          kind: "list",
          items: [
            "`Files.ReadWrite` — the Microsoft Graph permission required to write a file into your OneDrive and create a share link for it. SwiftX uses it only to upload the file you asked it to upload and to create that link. It does not browse, index, read or delete your other files.",
            "`offline_access` — returns a refresh token so you do not have to sign in again for every upload.",
          ],
        },
        {
          kind: "p",
          text: "Access, use, storage and sharing follow the same rules as the Google section: tokens in your Keychain, uploads direct from your Mac to OneDrive, nothing stored by the project, nothing shared with anyone, and no use for advertising or model training.",
        },
        {
          kind: "p",
          text: "Revoke SwiftX's access at [account.live.com/consent/Manage](https://account.live.com/consent/Manage) for a personal Microsoft account, or at [myapplications.microsoft.com](https://myapplications.microsoft.com) for a work or school account.",
        },
      ],
    },
    {
      id: "ai-analysis",
      heading: "Optional AI image analysis",
      blocks: [
        {
          kind: "p",
          text: "SwiftX can send a capture to an AI endpoint to describe it or pull text out of it. The feature is dormant until you enter an API key and pick a model, and the endpoint is whichever OpenAI-compatible base URL you configure — a commercial provider, or a model you host yourself.",
        },
        {
          kind: "p",
          text: "When you run an analysis, the image and your prompt go from your Mac straight to that provider. What they retain, log or train on is governed by their policy, so read it before pointing SwiftX at them — especially if your captures contain anything confidential. Your API key is kept in the Keychain. Leave it empty and no image is ever sent.",
        },
      ],
    },
    {
      id: "updates",
      heading: "Checking for updates",
      blocks: [
        {
          kind: "p",
          text: "SwiftX can check whether a newer version has been released. It asks GitHub's public releases API for the latest release of the SwiftX repository — one request, to a public address, containing no account, no device identifier, no licence key and nothing about how you use the app. GitHub sees the request the same way it sees anyone opening the releases page in a browser; their handling of that is covered by GitHub's own privacy statement. The project runs no update server and receives nothing.",
        },
        {
          kind: "p",
          text: "You choose how often this happens in Settings → Updates: daily (the default), weekly, monthly, or off, and you can check by hand at any time from the menu bar. Set it to off and SwiftX makes no update request at all.",
        },
        {
          kind: "p",
          text: "If you choose to install an update, the app downloads that release's disk image from GitHub and verifies it before use: the download must match the SHA-256 checksum published with the release, and the new copy must carry a valid Apple code signature from the same Developer ID team as the copy already running. Only then is the app replaced. Nothing is uploaded as part of an update, and installs managed by Homebrew are left to `brew upgrade --cask swiftx` rather than replaced in place.",
        },
      ],
    },
    {
      id: "on-device",
      heading: "What never leaves the device",
      blocks: [
        {
          kind: "list",
          items: [
            "**Text recognition (OCR)** runs through Apple's Vision framework, entirely on-device. Grabbed text goes to your clipboard, not to a server.",
            "**Annotation, image effects, resizing, colour picking, QR codes, hashing and thumbnails** are all local computation.",
            "**Window and screen enumeration** happens through ScreenCaptureKit and stays on the Mac.",
            "**The browser extension bridge** hands an image or URL from your browser to SwiftX over standard input on your own machine. The bridge itself makes no web request.",
          ],
        },
        {
          kind: "p",
          text: "None of these features opens a network connection.",
        },
      ],
    },
    {
      id: "security",
      heading: "Security",
      blocks: [
        {
          kind: "list",
          items: [
            "Secrets are held in the macOS Keychain rather than in plain-text configuration files.",
            "Every OAuth flow uses PKCE with a loopback redirect, so no authorization code passes through a third-party redirect service.",
            "Uploads use HTTPS wherever the destination offers it. If you point a custom uploader at a plain-text endpoint, that is your decision to make.",
            "Release builds are signed with an Apple Developer ID certificate and notarized by Apple, and the notarization ticket is stapled to the disk image — so macOS can verify the build is genuine and unaltered even with no network connection.",
            "They run under the macOS hardened runtime with no entitlement exceptions, so every protection it offers — library validation, no unsigned executable memory, no debugger attach — stays at its strictest setting.",
            "Releases are built and signed by a public automated workflow from tagged source in the repository, not assembled by hand on a maintainer's machine. What the release contains is what the public commit says it contains.",
            "In-app updates are verified before they are installed: the downloaded disk image must match the SHA-256 checksum published with the release, and the replacement app must be validly signed by the same Apple Developer ID team as the running copy. A download that fails either check is discarded, and the app falls back to sending you to the release page rather than installing anything.",
          ],
        },
        {
          kind: "p",
          text: "No system is perfect. If you believe you have found a vulnerability, report it through the repository rather than a public post where the details would be exposed.",
        },
      ],
    },
    {
      id: "children",
      heading: "Children",
      blocks: [
        {
          kind: "p",
          text: "SwiftX is a tool for developers and other professionals and is not directed at children under 13 — or under 16 in the EEA and the UK. We knowingly collect no personal information from anyone, children included, because we collect none at all.",
        },
      ],
    },
    {
      id: "deletion",
      heading: "Keeping and deleting your data",
      blocks: [
        {
          kind: "p",
          text: "Because everything is local, deletion is entirely in your hands:",
        },
        {
          kind: "list",
          items: [
            "**Captures** — delete the files from your screenshots folder.",
            "**History** — clear entries in the History window, or delete `~/Library/Application Support/SwiftX/History.db`.",
            "**Settings and credentials** — delete the `~/Library/Application Support/SwiftX` folder, and disconnect each connected account so its Keychain entry is removed.",
            "**Connected accounts** — disconnect in SwiftX, then revoke the grant with Google or Microsoft using the links above.",
            "**Files you have already uploaded** — those live at the destination. Remove them there.",
          ],
        },
        {
          kind: "p",
          text: "We cannot delete anything on your behalf, because we hold nothing to delete.",
        },
      ],
    },
    {
      id: "your-rights",
      heading: "GDPR, CCPA and similar laws",
      blocks: [
        {
          kind: "p",
          text: "Privacy laws such as the GDPR and the CCPA give you rights over personal data an organisation holds about you: access, correction, deletion, portability, objection, and the right not to have it sold. Those rights are exercised against whoever holds the data.",
        },
        {
          kind: "p",
          text: "The SwiftX project holds none. It is not a controller or processor of your captures — they never reach it — and it sells nothing. Where you have connected a Google or Microsoft account, those companies are the controllers of what sits in your account there, and their policies and request channels apply to it. The same is true of any other host you upload to.",
        },
      ],
    },
    {
      id: "website",
      heading: "This website",
      blocks: [
        {
          kind: "list",
          items: [
            "The site is a static export hosted on GitHub Pages. GitHub serves the files and may log requests as part of operating its network — see the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).",
            "There are no analytics, no tracking pixels, no advertising and no third-party embeds.",
            "Fonts are served from this origin, so loading a page contacts no font CDN.",
            "The only browser storage is a `swiftx-theme` key in `localStorage` remembering your light or dark choice. It is not a cookie, carries no identifier, and never leaves your browser.",
          ],
        },
      ],
    },
    {
      id: "changes",
      heading: "Changes to this policy",
      blocks: [
        {
          kind: "p",
          text: "If SwiftX gains a feature that changes what leaves your machine, this page changes with it and the effective date at the top moves. Every revision is in public version control, so you can see exactly what changed and when, and material changes are called out in the release notes for the version that introduces them.",
        },
      ],
    },
    {
      id: "contact",
      heading: "Contact",
      blocks: [
        {
          kind: "p",
          text: `Questions about this policy, or about how SwiftX handles data, belong on the issue tracker: [github.com/RetroHazard/SwiftX/issues](${issues}). That is the project's contact channel. It is public, so keep credentials, tokens and personal details out of anything you post there.`,
        },
      ],
    },
  ],
};

export const terms: LegalDoc = {
  title: "Terms of Service",
  description:
    "The terms covering SwiftX, the free and open-source macOS screen capture app: its GPL v3 licence, your responsibilities, third-party destinations, and the absence of any warranty.",
  effective: "25 July 2026",
  lede: "SwiftX is free software that runs on your own Mac. These terms set out what you can expect from it, what is expected of you, and what it does not promise.",
  sections: [
    {
      id: "agreement",
      heading: "These terms",
      blocks: [
        {
          kind: "p",
          text: "By downloading, installing or using SwiftX (\"the app\"), you agree to these terms. If you do not agree with them, do not use the app.",
        },
        {
          kind: "p",
          text: "They sit alongside the GNU General Public License v3 that SwiftX is distributed under — never in place of it. Where these terms and that licence disagree, the licence wins, and nothing here limits any right the licence grants you.",
        },
      ],
    },
    {
      id: "licence",
      heading: "The software and its licence",
      blocks: [
        {
          kind: "p",
          text: "SwiftX is free and open-source software released under the [GNU General Public License, version 3](https://www.gnu.org/licenses/gpl-3.0.html). You may run it for any purpose, study and modify the source, and redistribute it — including modified versions — under the same licence. The full text ships with the app and lives in the repository.",
        },
        {
          kind: "p",
          text: "SwiftX contains code derived from ShareX, which is also licensed under GPL v3. Attribution and the licences of bundled third-party components are listed in the app's About pane and in the repository.",
        },
        {
          kind: "p",
          text: "These terms grant no rights to the SwiftX name, icon or logo beyond what the licence and ordinary fair use already permit.",
        },
      ],
    },
    {
      id: "no-service",
      heading: "There is no service here",
      blocks: [
        {
          kind: "p",
          text: "SwiftX is a program, not a hosted service. There is no account to create, no server to sign in to, no subscription and no paid tier. Nothing you capture reaches the project.",
        },
        {
          kind: "p",
          text: "That cuts both ways: there is no uptime to guarantee and no service level to breach, but equally there is no one who can recover your files, restore your history or reset anything on your behalf. Your data is yours to back up.",
        },
      ],
    },
    {
      id: "your-use",
      heading: "How you use it",
      blocks: [
        {
          kind: "p",
          text: "SwiftX captures whatever is on your screen and sends it wherever you tell it to. Those are powerful defaults, and the responsibility for them is yours:",
        },
        {
          kind: "list",
          items: [
            "**Capture law is yours to know.** Recording screens, calls, meetings and other people's material may require consent or notice where you are. SwiftX will not ask on your behalf.",
            "**Respect each destination's rules.** Every host, bucket and API you point SwiftX at has its own terms and acceptable-use policy. Uploading through SwiftX does not exempt you from them.",
            "**Do not use it for unlawful or infringing material,** or to capture or distribute content you have no right to.",
            "**Guard your credentials.** API keys, tokens and connected accounts sit in your Mac's Keychain. Anyone with access to your unlocked Mac can use them through the app.",
            "**Custom uploaders and Actions execute what you configure.** A `.sxcu` definition or shell Action from an untrusted source can do anything you have permission to do on your machine. Read before you import.",
          ],
        },
      ],
    },
    {
      id: "third-party",
      heading: "Third-party services",
      blocks: [
        {
          kind: "p",
          text: "When you connect Google Drive, YouTube, OneDrive, an S3 bucket, an image host, a URL shortener or any other destination, you enter into a relationship with that provider directly. Their terms, quotas, pricing and content policies govern what you send them.",
        },
        {
          kind: "p",
          text: "SwiftX is a client. The project makes no representation about any provider's availability, pricing or conduct, and cannot address outages, deleted files, rate limits or account suspensions on their side. A provider changing or withdrawing its API may break a SwiftX destination without notice.",
        },
      ],
    },
    {
      id: "affiliation",
      heading: "Affiliation",
      blocks: [
        {
          kind: "p",
          text: "SwiftX is not affiliated with, endorsed by or sponsored by the ShareX project. It is an independent app, written from scratch in Swift, that follows the capture-to-upload workflow ShareX made popular and stays compatible with its configuration files. ShareX is the work of its own authors and contributors.",
        },
        {
          kind: "p",
          text: "Nor is it affiliated with Apple, Google, Microsoft, Amazon or any other company whose service it can upload to. Their names appear only to identify the destinations SwiftX supports, and all trademarks belong to their respective owners.",
        },
      ],
    },
    {
      id: "releases",
      heading: "Releases, changes and support",
      blocks: [
        {
          kind: "p",
          text: "SwiftX is developed in the open. Features may be added, changed or removed between releases, and compatibility with a third-party API can break when that API changes.",
        },
        {
          kind: "p",
          text: "Support is best-effort through the public issue tracker. Nothing on this page creates an obligation to fix a bug, ship a release, maintain a feature or answer a question within any timeframe.",
        },
      ],
    },
    {
      id: "warranty",
      heading: "No warranty",
      blocks: [
        {
          kind: "p",
          text: "SwiftX is provided \"as is\", without warranty of any kind, express or implied, including but not limited to the implied warranties of merchantability, fitness for a particular purpose and non-infringement. The entire risk as to the quality and performance of the software is with you. This restates sections 15 and 16 of the GNU General Public License v3, which govern.",
        },
      ],
    },
    {
      id: "liability",
      heading: "Limitation of liability",
      blocks: [
        {
          kind: "p",
          text: "To the maximum extent permitted by applicable law, neither the project nor its contributors are liable for any damages arising out of the use or inability to use SwiftX. That includes, without limitation, lost or corrupted captures and recordings, failed or incomplete uploads, content exposed by a destination you configured, charges incurred at a third-party provider, and any other loss of data, profit or goodwill — whether or not anyone was advised that such damages were possible.",
        },
        {
          kind: "p",
          text: "Some jurisdictions do not allow the exclusion of certain warranties or the limitation of certain liabilities. Where that is the case, the exclusions and limitations above apply to the greatest extent the law permits, and nothing here excludes liability that cannot lawfully be excluded.",
        },
      ],
    },
    {
      id: "privacy",
      heading: "Privacy",
      blocks: [
        {
          kind: "p",
          text: "SwiftX collects nothing about you. The details — what the app stores locally, what leaves your machine, and how connected Google and Microsoft accounts are handled — are in the [Privacy Policy](/privacy/), which forms part of these terms.",
        },
      ],
    },
    {
      id: "ending",
      heading: "Ending the agreement",
      blocks: [
        {
          kind: "p",
          text: "Stop using SwiftX and delete it, and these terms cease to apply to you. Your rights under the GPL survive independently — they come from the licence, not from this page.",
        },
      ],
    },
    {
      id: "changes",
      heading: "Changes to these terms",
      blocks: [
        {
          kind: "p",
          text: "These terms may change as the app does. When they do, the effective date at the top moves, and the revision is in public version control for you to inspect. Continuing to use SwiftX after a change means you accept the revised terms.",
        },
      ],
    },
    {
      id: "contact",
      heading: "Contact",
      blocks: [
        {
          kind: "p",
          text: `Questions about these terms go to the issue tracker: [github.com/RetroHazard/SwiftX/issues](${issues}). It is a public channel, so keep credentials and personal details out of anything you post.`,
        },
      ],
    },
  ],
};
