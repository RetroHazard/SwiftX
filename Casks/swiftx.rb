cask "swiftx" do
  version "2026.8.2"
  sha256 "d4d819ff77d54b59102bb03cf973bf54b4d9b5899bbb2a5c081e48ff534e99ce"

  url "https://github.com/RetroHazard/SwiftX/releases/download/v#{version}/SwiftX-#{version}.dmg"
  name "SwiftX"
  desc "Screenshot, screen recording, and file-sharing tool derived from ShareX"
  homepage "https://github.com/RetroHazard/SwiftX"

  # Menu-bar (LSUIElement) app. No auto_updates stanza, even though the app has
  # an in-app updater: it detects a Caskroom install and defers to
  # `brew upgrade --cask swiftx` rather than replacing its own bundle, so brew
  # stays the update channel — and the version it recorded stays accurate — for
  # copies installed this way.
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
