cask "swiftx" do
  version "0.1.0"
  sha256 "ff09aefcd49863951ab67cdc4f0af792cf785b731741297476d2d323f7190af4"

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
