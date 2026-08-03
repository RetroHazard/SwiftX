// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Release version scheme: CalVer YYYY.M.N as produced by Scripts/version.sh
// and tagged v$VERSION by the release workflow.

import Foundation

public struct CalVer: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let patch: Int

    /// Accepts "2026.7.1" and the tag form "v2026.7.1"; a "-suffix" prerelease
    /// marker ("2026.7.1-beta.1") is stripped so the base version compares.
    public init?(_ string: String) {
        var s = string.hasPrefix("v") ? String(string.dropFirst()) : string
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let p = Int(parts[2]),
              y > 0, m > 0, p >= 0
        else { return nil }
        (year, month, patch) = (y, m, p)
    }

    public static func < (a: CalVer, b: CalVer) -> Bool {
        (a.year, a.month, a.patch) < (b.year, b.month, b.patch)
    }

    public var description: String { "\(year).\(month).\(patch)" }
}
