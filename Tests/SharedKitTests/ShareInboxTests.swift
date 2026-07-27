// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import SharedKit

struct ShareInboxTests {
    @Test func manifestRoundTripsThroughJSON() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let request = ShareInbox.Request(createdAt: created,
                                         files: ["Screenshot.png", "Screenshot 2.png"],
                                         text: "hello",
                                         webURL: "https://example.com/x")
        let decoded = try JSONDecoder().decode(ShareInbox.Request.self,
                                               from: JSONEncoder().encode(request))
        #expect(decoded == request)
        #expect(decoded.version == ShareInbox.Request.currentVersion)
        #expect(!decoded.isEmpty)
        #expect(ShareInbox.Request().isEmpty)
    }

    @Test func requestIDsMustBeUUIDsSoLookupsStayInsideTheSpool() {
        #expect(ShareInbox.isValidRequestID(UUID().uuidString))
        #expect(!ShareInbox.isValidRequestID(""))
        #expect(!ShareInbox.isValidRequestID("../../../etc/passwd"))
        #expect(!ShareInbox.isValidRequestID("/Users/me/.ssh"))
        #expect(!ShareInbox.isValidRequestID(UUID().uuidString + "/.."))
    }

    @Test func stagedNamesRejectAnythingThatLeavesTheRequestDirectory() {
        #expect(ShareInbox.isSafeStagedName("Screenshot.png"))
        #expect(ShareInbox.isSafeStagedName("a b c.tar.gz"))
        #expect(!ShareInbox.isSafeStagedName(""))
        #expect(!ShareInbox.isSafeStagedName(".."))
        #expect(!ShareInbox.isSafeStagedName(".hidden"))
        #expect(!ShareInbox.isSafeStagedName("sub/dir.png"))
        #expect(!ShareInbox.isSafeStagedName("/etc/passwd"))
        #expect(!ShareInbox.isSafeStagedName("../../secret.txt"))
    }

    @Test func freshnessWindowDropsReplaysButToleratesClockSkew() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func request(offset: TimeInterval) -> ShareInbox.Request {
            ShareInbox.Request(createdAt: now.addingTimeInterval(offset))
        }
        #expect(ShareInbox.isFresh(request(offset: 0), now: now))
        #expect(ShareInbox.isFresh(request(offset: -ShareInbox.maxAge + 1), now: now))
        #expect(!ShareInbox.isFresh(request(offset: -ShareInbox.maxAge - 1), now: now))
        #expect(ShareInbox.isFresh(request(offset: 30), now: now))    // minor skew
        #expect(!ShareInbox.isFresh(request(offset: 120), now: now))  // stamped in the future
    }

    /// The extension writes with `spoolRoot(containerHome:)` from inside its
    /// sandbox; the app reads with `spoolRoots(userHome:)` from outside it. The
    /// two must land on the same directory or every share silently vanishes.
    @Test func writerAndReaderAgreeOnTheSpoolPath() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("swiftx-share-inbox-\(UUID().uuidString)", isDirectory: true)
        let container = home
            .appendingPathComponent("Library/Containers/\(ShareInbox.extensionBundleID)/Data",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let written = ShareInbox.spoolRoot(containerHome: container)
        try FileManager.default.createDirectory(at: written, withIntermediateDirectories: true)

        let found = ShareInbox.spoolRoots(userHome: home)
        #expect(found.count == 1)
        #expect(found.first?.standardizedFileURL == written.standardizedFileURL)
    }

    @Test func onlyTheShareExtensionsContainerIsSearched() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("swiftx-share-inbox-\(UUID().uuidString)", isDirectory: true)
        let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        for name in [ShareInbox.extensionBundleID,
                     ShareInbox.extensionBundleID + ".2",
                     "com.retrohazard.swiftx",
                     "com.example.evil"] {
            try FileManager.default.createDirectory(
                at: containers.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true)
        }

        let roots = ShareInbox.spoolRoots(userHome: home).map(\.path)
        #expect(roots.count == 2)
        #expect(roots.allSatisfy { $0.contains(ShareInbox.extensionBundleID) })
        #expect(!roots.contains { $0.contains("com.example.evil") })
        // the app's own container must not be mistaken for the extension's
        #expect(!roots.contains { $0.contains("/com.retrohazard.swiftx/") })
    }
}
