import type { NextConfig } from "next";

// Published as a GitHub Pages *project* site at
// https://retrohazard.github.io/SwiftX/, so every route and asset is served
// under the /SwiftX prefix. This is the default so a local `npm run build`
// produces exactly what deploys — a root-served build would hide broken
// sub-path links until production.
//
// To serve from the root of a custom domain instead, build with
// SITE_BASE_PATH="" and add a public/CNAME file naming the domain.
const basePath = process.env.SITE_BASE_PATH ?? "/SwiftX";

const nextConfig: NextConfig = {
  output: "export",
  basePath,
  // No assetPrefix: basePath already prefixes assets, and the Next docs
  // advise against assetPrefix for sub-path hosting.
  trailingSlash: true,
  images: {
    unoptimized: true,
  },
  env: {
    // next/image does not apply basePath to `src`, so components prefix it
    // themselves from this value.
    NEXT_PUBLIC_BASE_PATH: basePath,
  },
};

export default nextConfig;
