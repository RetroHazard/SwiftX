// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Handoff contract between the embedded Share extension (writer) and the app
// (reader). The extension is sandboxed and the app is not, so the payload
// travels one way: the extension stages copies of what was shared inside its
// own sandbox container, then opens swiftx://ShareExtensionInput/<uuid>; the
// app resolves that id against the container and consumes the request.
//
// The container is what authenticates the request. A web page — the reason the
// URL scheme is untrusted in the first place — cannot create a directory inside
// another process's sandbox container, so it cannot forge a request; the most
// it could do is replay an id it does not know, which the freshness window and
// the consume-on-read below close off.

import Foundation

public enum ShareInbox {
    /// Bundle identifier of `SwiftXShare.appex`. Its App Sandbox container is
    /// the ONLY place the app reads share requests from — see the header.
    public static let extensionBundleID = "com.retrohazard.swiftx.share"

    /// CLI/URL verb the extension opens: `swiftx://ShareExtensionInput/<uuid>`.
    public static let verb = "ShareExtensionInput"

    /// Manifest file inside a request directory.
    public static let manifestName = "request.json"

    /// A request older than this is dropped unread. The extension opens the URL
    /// immediately after staging, so the only thing this window has to cover is
    /// a cold app launch (plus a first-run TCC prompt or two).
    public static let maxAge: TimeInterval = 300

    /// What the user handed to the Share menu, as staged by the extension.
    public struct Request: Codable, Equatable, Sendable {
        public static let currentVersion = 1

        public var version: Int
        public var createdAt: Date
        /// File names — not paths — of the staged copies sitting next to the
        /// manifest. Validate each with ``isSafeStagedName(_:)`` before use.
        public var files: [String]
        /// Shared plain text, if any.
        public var text: String?
        /// A shared http(s) link, routed through the same ClipboardUpload*
        /// toggles a copied URL takes (download contents / shorten / share).
        public var webURL: String?

        public init(createdAt: Date = Date(), files: [String] = [],
                    text: String? = nil, webURL: String? = nil) {
            self.version = Self.currentVersion
            self.createdAt = createdAt
            self.files = files
            self.text = text
            self.webURL = webURL
        }

        public var isEmpty: Bool {
            files.isEmpty && (text?.isEmpty ?? true) && (webURL?.isEmpty ?? true)
        }
    }

    /// `Library/Caches/SwiftX/Share` — inside the container this is a cache
    /// directory the system already expects to be able to purge.
    private static let spoolComponents = ["Library", "Caches", "SwiftX", "Share"]

    /// Extension side. `containerHome` is the sandbox container's `Data`
    /// directory, which is what `NSHomeDirectory()` returns inside the appex.
    public static func spoolRoot(containerHome: URL) -> URL {
        spoolComponents.reduce(containerHome) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// App side. Resolves the extension's container(s) under the real home —
    /// the app is not sandboxed, so it can read straight into them. macOS names
    /// the container after the appex bundle id; the prefix match also catches
    /// the `<id>.<suffix>` variants the system creates when it re-homes one.
    public static func spoolRoots(userHome: URL) -> [URL] {
        let containers = userHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: containers.path)) ?? []
        return names
            .filter { $0 == extensionBundleID || $0.hasPrefix(extensionBundleID + ".") }
            .sorted()
            .map {
                spoolRoot(containerHome: containers
                    .appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent("Data", isDirectory: true))
            }
    }

    /// Request ids are UUIDs, so nothing a caller sends can steer the lookup
    /// outside the spool root — no separators, no `..`, no absolute paths.
    public static func isValidRequestID(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }

    /// The manifest crosses a process boundary, so its file names get the same
    /// treatment: a plain name only, never something that walks out of the
    /// request directory.
    public static func isSafeStagedName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\0")
    }

    /// Rejects stale requests (replay) and ones stamped in the future (a clock
    /// skew of a minute is tolerated rather than silently dropping the upload).
    public static func isFresh(_ request: Request, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(request.createdAt)
        return age >= -60 && age <= maxAge
    }
}
