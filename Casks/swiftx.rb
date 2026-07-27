cask "swiftx" do
  version "0.16.63"
  sha256 "5c6c9fd2091e5209b66ded554d9b5eea80be7f23b4b41862f697d2564e42d843"

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
