# SwiftX landing site

The GitHub Pages marketing site for SwiftX, built with Next.js (static export),
React, Tailwind CSS, and Motion.

## Stack

- **Next.js App Router**, `output: "export"` — no server, ships as static HTML/CSS/JS
- **Tailwind CSS v4** for styling
- **[Motion](https://motion.dev)** (`motion/react`) for scroll-reveal and entrance animations
- **lucide-react** for icons
- **Fontsource + `next/font/local`** for type — the woff2 files come from the
  `@fontsource-variable/*` packages and are served from our own origin, so the
  build never reaches out to a font CDN

## Design notes

Colour, type and spacing all run through CSS custom properties declared in
`src/app/globals.css`. Light is the default; dark comes from
`prefers-color-scheme`, and the header toggle stamps `data-theme` on the root
element to override either direction. Style components through the tokens
(`bg-panel`, `text-muted`, `border-line`, …) rather than hard-coded colours, or
they will not follow the theme.

Three type roles are set up as utility classes: `.display` (Archivo, heavy and
slightly expanded) for headings, the body default (Public Sans), and `.readout`
(JetBrains Mono, tabular figures) — reserved for real instrument data such as
capture dimensions, timers, hotkeys and file sizes.

`ShotSample` is the fake on-screen content every product mock operates on. Its
colours are deliberately *not* themed: it stands in for someone else's screen,
not for our own surface.

## Legal pages

`/privacy/` and `/terms/` exist because Google and Microsoft both require a
published privacy policy — and Microsoft a terms-of-service URL — before they
approve the OAuth app registrations behind the Google Drive, YouTube and
OneDrive destinations. Those URLs are recorded in the app registrations, so
**the routes must not move** while the registrations exist.

The copy lives in `src/lib/legal.ts` as plain data and is rendered by
`LegalDoc`. Google's OAuth verification reads the policy closely, so everything
it asserts has to stay true of the code: when a destination, OAuth scope,
locally stored file or outbound network call changes in `Sources/`, update
`src/lib/legal.ts` in the same commit and move its `effective` date.

Google's [home page requirements](https://support.google.com/cloud/answer/13807376)
also expect the home page itself — not just the privacy policy — to show the
functionality behind the scopes being requested. That's why Google Drive,
YouTube and OneDrive appear as destinations in `src/lib/content.ts` and get a
plain-language mention in the FAQ, not just a line in `/privacy/`: keep them
there alongside whatever else changes when a connected-account destination is
added, renamed or removed.

## Developing

```bash
npm install
npm run dev
```

## Building

```bash
npm run build
```

Outputs a static site to `out/`, rooted at `/SwiftX/` — the GitHub Pages
*project site* path for this repo. That prefix is the default in
`next.config.ts`, so the build you run locally is byte-for-byte the build that
deploys; a root-served build would hide broken sub-path links until production.

Serving from the root of a custom domain instead takes two steps:

```bash
SITE_BASE_PATH="" npm run build
```

and a `public/CNAME` file containing the domain.

> `next/image` does not apply `basePath` to `src`, so components prefix it
> themselves from `process.env.NEXT_PUBLIC_BASE_PATH`. Use that variable for
> anything you reference out of `public/`.

## Deploying

The site publishes to **https://retrohazard.github.io/SwiftX/**.

Two workflows cover it:

| Workflow | Runs on | Does |
| --- | --- | --- |
| `.github/workflows/ci.yml` | pull requests, when `site/**` changed | lint, build, sanity-check the export |
| `.github/workflows/pages.yml` | push to `master` touching `site/**`, or manual dispatch | build and publish via `actions/deploy-pages` |

Both run the same `.github/actions/build-site` composite action, so the export that deploys is
verified by exactly the checks that gated the pull request. The only difference is that `ci.yml`
also runs eslint — a lint regression must not block publishing a site that builds correctly.

**Settings → Pages → Build and deployment → Source** must be **GitHub
Actions**, not "Deploy from a branch". The site publishes from **`master`**;
use `workflow_dispatch` from the Actions tab to publish a branch manually
outside that push trigger.

### Why not `swiftx.github.io`

That URL form is only served from a repo named `<account>.github.io` owned by an
account of the same name, and the GitHub account `Swiftx` is already taken. A
project site under `retrohazard.github.io/SwiftX/` is what this repo can serve.
To move to a custom domain later, see the `SITE_BASE_PATH` note under
[Building](#building) and add `public/CNAME`.
