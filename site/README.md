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

Outputs a static site to `out/`, rooted at `/` — the site is served from the
custom domain `swiftx.retrohazard.jp` (see `public/CNAME`), not a
`/SwiftX/` subpath. If the domain isn't live yet and you need the fallback
`https://<owner>.github.io/SwiftX/` URL instead, build with
`NEXT_PUBLIC_USE_REPO_BASE_PATH=true npm run build` to prefix every
asset/link with `/SwiftX`.

## Deploying

Handled by `.github/workflows/pages.yml`: on every push to `develop` that
touches `site/**`, it builds the export and publishes it via
`actions/deploy-pages`. Trigger it manually from the Actions tab if needed
(`workflow_dispatch`).

### Custom domain checklist (one-time, done in GitHub/DNS settings — not in this repo)

1. Repo **Settings → Pages → Build and deployment → Source** must be set to
   **GitHub Actions** (not "Deploy from a branch").
2. Add a DNS **CNAME** record for `swiftx` under `retrohazard.jp` pointing at
   `retrohazard.github.io`.
3. In **Settings → Pages → Custom domain**, enter `swiftx.retrohazard.jp` and
   save — GitHub will show an **unverified** badge until step 4 is done.
4. Verify domain ownership under your GitHub account/org
   **Settings → Pages → Custom domains** (adds a `_github-pages-challenge-*`
   TXT record you create at your DNS provider).
5. Once DNS + verification resolve, check **Enforce HTTPS** on the Pages
   settings page.

Until all of this is done, pushes still deploy successfully — GitHub just
serves the build at the default `github.io` URL (or 404s until a domain is
configured) rather than the custom domain.
