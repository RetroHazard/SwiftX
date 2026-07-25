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
| `.github/workflows/site-ci.yml` | pull requests touching `site/**` | lint, build, sanity-check the export |
| `.github/workflows/pages.yml` | push to `develop` touching `site/**`, or manual dispatch | build and publish via `actions/deploy-pages` |

### Before the first deploy

1. **Settings → Pages → Build and deployment → Source** must be **GitHub
   Actions**, not "Deploy from a branch".
2. The repo must be **public**, or the account needs GitHub Pro/Team — Pages is
   unavailable on private repos on the free plan. Until then `pages.yml` builds
   fine but the deploy step fails at the Pages API.
3. **The `develop` branch does not exist yet.** Until it is created, the push
   trigger never fires and the only way to publish is `workflow_dispatch` from
   the Actions tab. Create `develop`, or point the trigger at whichever branch
   should publish.

### Why not `swiftx.github.io`

That URL form is only served from a repo named `<account>.github.io` owned by an
account of the same name, and the GitHub account `Swiftx` is already taken. A
project site under `retrohazard.github.io/SwiftX/` is what this repo can serve.
To move to a custom domain later, see the `SITE_BASE_PATH` note under
[Building](#building) and add `public/CNAME`.
