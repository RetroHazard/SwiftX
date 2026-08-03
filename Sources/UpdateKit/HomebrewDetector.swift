// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// The cask stanza `app "SwiftX.app"` MOVES the bundle into /Applications, so
// the running path never reveals a Homebrew install. The Caskroom metadata
// directory (created by install, removed by uninstall) is the reliable
// marker, and checking it needs no subprocess.

import Foundation

public enum HomebrewDetector {
    /// True when the swiftx cask is installed; such copies are updated with
    /// `brew upgrade --cask swiftx`, never by self-replacing the bundle.
    public static func isHomebrewManaged(prefixes: [String] = candidatePrefixes()) -> Bool {
        prefixes.contains {
            FileManager.default.fileExists(atPath: "\($0)/Caskroom/swiftx")
        }
    }

    static func candidatePrefixes() -> [String] {
        var prefixes = ["/opt/homebrew", "/usr/local"]
        if let env = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !env.isEmpty {
            prefixes.insert(env, at: 0)
        }
        return prefixes
    }
}
