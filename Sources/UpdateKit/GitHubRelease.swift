// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Subset of the GitHub /releases/latest response the updater needs. The
// release workflow publishes SwiftX-$VERSION.dmg plus a .dmg.sha256 asset
// containing the bare hex digest.

import Foundation

public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL
        public let size: Int

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }

        public init(name: String, browserDownloadURL: URL, size: Int) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
            self.size = size
        }
    }

    /// Tag form "v2026.7.1".
    public let tagName: String
    /// Release page; the browser fallback whenever self-install is unavailable.
    public let htmlURL: URL
    /// Markdown release notes.
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public init(tagName: String, htmlURL: URL, body: String?,
                draft: Bool, prerelease: Bool, assets: [Asset]) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.body = body
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    public func dmgAsset(for version: CalVer) -> Asset? {
        assets.first { $0.name == "SwiftX-\(version).dmg" }
    }

    public func checksumAsset(for version: CalVer) -> Asset? {
        assets.first { $0.name == "SwiftX-\(version).dmg.sha256" }
    }
}
