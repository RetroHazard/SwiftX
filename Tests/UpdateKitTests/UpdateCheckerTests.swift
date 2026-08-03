// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import UpdateKit

struct UpdateCheckerTests {
    /// Shape of a real /releases/latest response, cut down to relevant fields.
    private func releaseJSON(tag: String = "v2026.8.1", draft: Bool = false,
                             prerelease: Bool = false, withAssets: Bool = true) -> String {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = withAssets ? """
        [
          {"name": "SwiftX-\(version).dmg",
           "browser_download_url": "https://github.com/RetroHazard/SwiftX/releases/download/\(tag)/SwiftX-\(version).dmg",
           "size": 12345678},
          {"name": "SwiftX-\(version).dmg.sha256",
           "browser_download_url": "https://github.com/RetroHazard/SwiftX/releases/download/\(tag)/SwiftX-\(version).dmg.sha256",
           "size": 65}
        ]
        """ : "[]"
        return """
        {
          "tag_name": "\(tag)",
          "html_url": "https://github.com/RetroHazard/SwiftX/releases/tag/\(tag)",
          "body": "## Changes\\n- Something new",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": \(assets)
        }
        """
    }

    private func decode(_ json: String) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    @Test func decodesReleaseResponse() throws {
        let release = try decode(releaseJSON())
        #expect(release.tagName == "v2026.8.1")
        #expect(release.htmlURL.absoluteString.hasSuffix("/releases/tag/v2026.8.1"))
        #expect(release.body?.contains("Something new") == true)
        #expect(!release.draft)
        #expect(!release.prerelease)
        #expect(release.assets.count == 2)
        #expect(release.assets[0].size == 12_345_678)
    }

    @Test func selectsAssetsByExactName() throws {
        let release = try decode(releaseJSON())
        let version = try #require(CalVer("2026.8.1"))
        #expect(release.dmgAsset(for: version)?.name == "SwiftX-2026.8.1.dmg")
        #expect(release.checksumAsset(for: version)?.name == "SwiftX-2026.8.1.dmg.sha256")
        let other = try #require(CalVer("2026.9.1"))
        #expect(release.dmgAsset(for: other) == nil)
    }

    @Test func olderOrEqualReleaseIsUpToDate() throws {
        let current = try #require(CalVer("2026.8.1"))
        let equal = try UpdateChecker.evaluate(current: current,
                                               release: decode(releaseJSON(tag: "v2026.8.1")),
                                               skippedVersion: "")
        guard case .upToDate = equal else { Issue.record("expected upToDate"); return }

        let older = try UpdateChecker.evaluate(current: current,
                                               release: decode(releaseJSON(tag: "v2026.7.2")),
                                               skippedVersion: "")
        guard case .upToDate = older else { Issue.record("expected upToDate"); return }
    }

    @Test func newerReleaseIsAvailable() throws {
        let current = try #require(CalVer("2026.7.1"))
        let outcome = try UpdateChecker.evaluate(current: current,
                                                 release: decode(releaseJSON(tag: "v2026.8.1")),
                                                 skippedVersion: "")
        guard case .available(let update) = outcome else { Issue.record("expected available"); return }
        #expect(update.version == CalVer("2026.8.1"))
        #expect(update.dmg.name == "SwiftX-2026.8.1.dmg")
        #expect(update.checksum != nil)
    }

    @Test func skippedVersionIsMuted() throws {
        let current = try #require(CalVer("2026.7.1"))
        let outcome = try UpdateChecker.evaluate(current: current,
                                                 release: decode(releaseJSON(tag: "v2026.8.1")),
                                                 skippedVersion: "2026.8.1")
        guard case .skipped = outcome else { Issue.record("expected skipped"); return }
    }

    @Test func newerReleaseOverridesOlderSkip() throws {
        let current = try #require(CalVer("2026.7.1"))
        let outcome = try UpdateChecker.evaluate(current: current,
                                                 release: decode(releaseJSON(tag: "v2026.9.1")),
                                                 skippedVersion: "2026.8.1")
        guard case .available = outcome else { Issue.record("expected available"); return }
    }

    @Test func draftAndPrereleaseAreIgnored() throws {
        let current = try #require(CalVer("2026.7.1"))
        for json in [releaseJSON(tag: "v2026.8.1", draft: true),
                     releaseJSON(tag: "v2026.8.1", prerelease: true)] {
            let outcome = try UpdateChecker.evaluate(current: current, release: decode(json),
                                                     skippedVersion: "")
            guard case .upToDate = outcome else { Issue.record("expected upToDate"); return }
        }
    }

    @Test func missingDMGAssetThrows() throws {
        let current = try #require(CalVer("2026.7.1"))
        let release = try decode(releaseJSON(tag: "v2026.8.1", withAssets: false))
        #expect(throws: UpdateChecker.CheckError.self) {
            try UpdateChecker.evaluate(current: current, release: release, skippedVersion: "")
        }
    }

    @Test func unparsableTagThrows() throws {
        let current = try #require(CalVer("2026.7.1"))
        let release = try decode(releaseJSON(tag: "nightly"))
        #expect(throws: UpdateChecker.CheckError.self) {
            try UpdateChecker.evaluate(current: current, release: release, skippedVersion: "")
        }
    }

    @Test func frequencyIntervalsMatchCadence() {
        #expect(UpdateCheckFrequency.off.interval == nil)
        #expect(UpdateCheckFrequency.daily.interval == 23.5 * 3600)
        #expect(UpdateCheckFrequency.weekly.interval == 7 * 86_400 - 1800)
        #expect(UpdateCheckFrequency.monthly.interval == 30 * 86_400 - 1800)
        // raw values are what ApplicationConfig persists
        #expect(UpdateCheckFrequency(rawValue: "Daily") == .daily)
        #expect(UpdateCheckFrequency(rawValue: "daily") == nil)
        #expect(UpdateCheckFrequency.allCases.map(\.rawValue) == ["Off", "Daily", "Weekly", "Monthly"])
    }
}
