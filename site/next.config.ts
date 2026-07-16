import type { NextConfig } from "next";

// Served at the custom domain root (swiftx.retrohazard.jp — see public/CNAME).
// If the domain isn't active yet and you need the fallback
// https://<owner>.github.io/SwiftX/ URL instead, build with
// NEXT_PUBLIC_USE_REPO_BASE_PATH=true to prefix every asset/link with /SwiftX.
const useRepoBasePath = process.env.NEXT_PUBLIC_USE_REPO_BASE_PATH === "true";
const basePath = useRepoBasePath ? "/SwiftX" : "";

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
