cask "swiftx" do
  version "2026.7.1"
  sha256 "4f6e5510689bd0d581910f720d55e661ff5ad2566b8e1176cbb43a0e56262764"

  url "https://github.com/RetroHazard/SwiftX/releases/download/v#{version}/SwiftX-#{version}.dmg"
  name "SwiftX"
  desc "Screenshot, screen recording, and file-sharing tool derived from ShareX"
  homepage "https://github.com/RetroHazard/SwiftX"

  # Menu-bar (LSUIElement) app. No auto_updates stanza: `brew upgrade --cask` is
  # the update channel, so Sparkle is unnecessary.
  # Matches Package.swift's .macOS(.v14) and the bundle's LSMinimumSystemVersion
  # 14.0. SwiftX calls SCScreenshotManager, which is macOS 14+, so a Ventura
  # install would place an app that cannot run.
  depends_on macos: :sonoma # ">= 14"

  app "SwiftX.app"

  # Releases are Developer ID-signed, notarized, and stapled by the release
  # workflow (.github/workflows/release.yml), so no quarantine workaround is
  # needed — Gatekeeper clears the DMG on its own.

  uninstall quit: "com.retrohazard.swiftx"

  # Deliberately leaves ~/Pictures/SwiftX (user screenshots) in place.
  zap trash: [
    "~/Library/Application Support/SwiftX",
    "~/Library/Preferences/com.retrohazard.swiftx.plist",
  ]
end
