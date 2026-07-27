// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// App side of the Share extension handoff (SharedKit/ShareInbox.swift). The
// extension stages what the user shared inside its own sandbox container and
// opens swiftx://ShareExtensionInput/<uuid>; this resolves that id, runs the
// staged payload through the normal upload pipeline, and deletes it.
//
// The URL scheme is untrusted (any web page can open one), so this deliberately
// takes nothing but a UUID from the caller: every path is derived from the
// extension's container, which a web page cannot write into. Combined with the
// freshness window and consume-on-read, a forged or replayed URL can only ever
// resolve to nothing. Uploading is therefore not gated behind a second
// confirmation — the user already picked SwiftX in the Share menu and
// confirmed the item list in the extension's own sheet.

import AppKit
import SharedKit

@MainActor
enum ShareRequests {
    /// Handles `-ShareExtensionInput <uuid>`.
    static func handle(id: String) {
        guard ShareInbox.isValidRequestID(id) else {
            AppLog.app.warning("Ignored a share request with a malformed id")
            return
        }
        for root in spoolRoots() {
            let directory = root.appendingPathComponent(id, isDirectory: true)
            guard FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(ShareInbox.manifestName).path) else { continue }
            process(directory)
            return
        }
        // Not an error on a cold launch: drainPending() runs first and will
        // already have consumed the request the URL event is announcing.
        AppLog.app.info("Share request \(id, privacy: .public) was already consumed")
    }

    /// Picks up anything the extension staged while we were starting up (the
    /// URL event can arrive before the handler is installed on a cold launch)
    /// and clears out requests that expired unread.
    static func drainPending() {
        for root in spoolRoots() {
            let directories = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
            for directory in directories where ShareInbox.isValidRequestID(directory.lastPathComponent) {
                process(directory)
            }
        }
    }

    private static func spoolRoots() -> [URL] {
        ShareInbox.spoolRoots(userHome: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Reads one request and consumes it. The directory goes away either way:
    /// a request that cannot be parsed is never going to become valid, and
    /// leaving it would let a replay retry it.
    private static func process(_ directory: URL) {
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(ShareInbox.manifestName)),
              let request = try? JSONDecoder().decode(ShareInbox.Request.self, from: data) else { return }
        guard request.version == ShareInbox.Request.currentVersion else {
            AppLog.app.warning("Ignored a share request written by a different SwiftX version")
            return
        }
        guard ShareInbox.isFresh(request) else {
            AppLog.app.warning("Dropped a share request that expired before SwiftX read it")
            return
        }

        let files = request.files
            .filter(ShareInbox.isSafeStagedName)
            .map { directory.appendingPathComponent($0) }
        if !files.isEmpty {
            guard UploadCoordinator.confirmMultiUpload(count: files.count) else { return }
            // uploadFile reads the bytes synchronously, so the staged copies
            // are safe to delete as soon as this loop finishes.
            files.forEach { UploadCoordinator.uploadFile(at: $0) }
        }
        if let link = request.webURL, !link.isEmpty {
            // Same routing a copied link gets: download its contents, shorten
            // it, or hand it to the sharing service, per the ClipboardUpload*
            // toggles; plain text upload is the fallback.
            UploadActions.uploadTextOrURL(link, settings: TaskSettings.load())
        } else if let text = request.text, !text.isEmpty {
            UploadCoordinator.uploadText(text)
        }
    }
}
