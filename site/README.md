# SwiftX landing site

The GitHub Pages marketing site for SwiftX, built with Next.js (static export),
React, Tailwind CSS, and Motion.

## Stack

- **Next.js App Router**, `output: "export"` — no server, ships as static HTML/CSS/JS
- **Tailwind CSS v4** for styling
- **[Motion](https://motion.dev)** (`motion/react`) for scroll-reveal and entrance animations
- **lucide-react** for icons

## Developing

```bash
npm install
npm run dev
```

## Building

```bash
npm run build
```

Outputs a static site to `out/`. Because GitHub Pages serves this repo at
`https://<owner>.github.io/SwiftX/`, `next.config.ts` bakes in `basePath: "/SwiftX"`
whenever `NODE_ENV=production` — `npm run dev` stays unprefixed.

## Deploying

Handled by `.github/workflows/pages.yml`: on every push to `develop` that
touches `site/**`, it builds the export and publishes it via
`actions/deploy-pages`. Trigger it manually from the Actions tab if needed
(`workflow_dispatch`).
