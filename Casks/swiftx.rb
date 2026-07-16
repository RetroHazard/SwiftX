cask "swiftx" do
  version "0.1.0"
  sha256 "ff09aefcd49863951ab67cdc4f0af792cf785b731741297476d2d323f7190af4"

  url "https://github.com/RetroHazard/SwiftX/releases/download/v#{version}/SwiftX-#{version}.dmg"
  name "SwiftX"
  desc "Screenshot, screen recording, and file-sharing tool derived from ShareX"
  homepage "https://github.com/RetroHazard/SwiftX"

  # Menu-bar (LSUIElement) app. No auto_updates stanza: `brew upgrade --cask` is
  # the update channel, so Sparkle is unnecessary.
  depends_on macos: :ventura # Info.plist LSMinimumSystemVersion 13.0; :ventura means ">= 13"

  app "SwiftX.app"

  # ponytail: interim — builds are not yet notarized (no paid Developer ID), so
  # Gatekeeper quarantines the download. Strip the flag on install so it launches.
  # DELETE this block once make-app.sh signs with Developer ID and notarize.sh runs.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/SwiftX.app"],
                   sudo: false
  end

  uninstall quit: "com.retrohazard.swiftx"

  # Deliberately leaves ~/Pictures/SwiftX (user screenshots) in place.
  zap trash: [
    "~/Library/Application Support/SwiftX",
    "~/Library/Preferences/com.retrohazard.swiftx.plist",
  ]
end
