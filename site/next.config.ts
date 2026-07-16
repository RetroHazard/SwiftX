import type { NextConfig } from "next";

// GitHub Pages serves this project at https://<owner>.github.io/SwiftX/,
// so every asset and internal link needs the /SwiftX base path baked in.
const repoName = "SwiftX";
const basePath = process.env.NODE_ENV === "production" ? `/${repoName}` : "";

const nextConfig: NextConfig = {
  output: "export",
  basePath,
  assetPrefix: basePath ? `${basePath}/` : undefined,
  trailingSlash: true,
  images: {
    unoptimized: true,
  },
  env: {
    NEXT_PUBLIC_BASE_PATH: basePath,
  },
};

export default nextConfig;
