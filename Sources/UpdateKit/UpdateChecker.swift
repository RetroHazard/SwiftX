// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Latest-release lookup against the GitHub API. C# ships an
// UpdateChecker/GitHubUpdateChecker pair over release feeds; here one enum
// covers the fetch plus a pure evaluate step so the decision logic stays
// unit-testable. Unauthenticated API quota is 60 requests/hour per IP -
// orders of magnitude above the background cadence.

import Foundation
import SharedKit

/// How often the background update check runs. Raw values are stored in
/// ApplicationConfig.updateCheckFrequency.
public enum UpdateCheckFrequency: String, CaseIterable, Sendable {
    case off = "Off"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    /// Seconds between background checks; nil = never check. Slightly under
    /// the nominal period so launch-time jitter can't skip a whole cycle.
    public var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 23.5 * 3600
        case .weekly: return 7 * 86_400 - 1800
        case .monthly: return 30 * 86_400 - 1800
        }
    }

    public var displayName: String { rawValue }
}

public enum UpdateChecker {
    public struct AvailableUpdate: Sendable {
        public let version: CalVer
        public let release: GitHubRelease
        public let dmg: GitHubRelease.Asset
        /// Absent on a malformed release; the installer fails closed without it.
        public let checksum: GitHubRelease.Asset?
    }

    public enum Outcome: Sendable {
        case upToDate
        case available(AvailableUpdate)
        /// Newer than current but matches the user's skipped version. The
        /// background check stays silent; a manual check reports it anyway.
        case skipped(AvailableUpdate)
    }

    public enum CheckError: LocalizedError {
        case http(Int, String)
        case badVersion(String)
        case noDMGAsset(String)

        public var errorDescription: String? {
            switch self {
            case .http(let status, let body): return L10n.t("update.error.http", "\(status)", body)
            case .badVersion(let tag): return L10n.t("update.error.bad_version", tag)
            case .noDMGAsset(let tag): return L10n.t("update.error.no_dmg_asset", tag)
            }
        }
    }

    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/RetroHazard/SwiftX/releases/latest")!

    public static func fetchLatestRelease(session: URLSession = .shared) async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CheckError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// Pure decision step. `skippedVersion` is the stored CalVer string the
    /// user chose to skip ("" = none); it only mutes that exact version, so a
    /// later release surfaces again.
    public static func evaluate(current: CalVer, release: GitHubRelease,
                                skippedVersion: String) throws -> Outcome {
        // /releases/latest never serves drafts or prereleases; belt and braces.
        guard !release.draft, !release.prerelease else { return .upToDate }
        guard let latest = CalVer(release.tagName) else {
            throw CheckError.badVersion(release.tagName)
        }
        guard latest > current else { return .upToDate }
        guard let dmg = release.dmgAsset(for: latest) else {
            throw CheckError.noDMGAsset(release.tagName)
        }
        let update = AvailableUpdate(version: latest, release: release,
                                     dmg: dmg, checksum: release.checksumAsset(for: latest))
        return CalVer(skippedVersion) == latest ? .skipped(update) : .available(update)
    }
}
