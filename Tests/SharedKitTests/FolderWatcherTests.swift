// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct FolderWatcherTests {
    @Test func watchFolderSettingsDecodeWindowsJSON() throws {
        let json = """
        {"FolderPath": "C:\\\\Users\\\\me\\\\Dropbox", "Filter": "*.png",
         "IncludeSubdirectories": true, "MoveFilesToScreenshotsFolder": true}
        """
        let settings = try JSONDecoder().decode(WatchFolderSettings.self, from: json.data(using: .utf8)!)
        #expect(settings.folderPath == "C:\\Users\\me\\Dropbox")
        #expect(settings.filter == "*.png")
        #expect(settings.includeSubdirectories)
        #expect(settings.moveFilesToScreenshotsFolder)
    }

    @Test func missingDirectoryReturnsNil() {
        #expect(FolderWatcher(path: "/nonexistent/swiftx-test") { _ in } == nil)
    }

    @MainActor
    @Test func detectsNewFileMatchingFilter() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        nonisolated(unsafe) var seen: [String] = []
        let watcher = try #require(FolderWatcher(path: dir.path, filter: "*.png") { seen.append($0) })
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(300)) // let the stream start
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("shot.png"))
        try Data([1]).write(to: dir.appendingPathComponent("ignored.txt"))

        for _ in 0..<50 where seen.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(seen.count == 1)
        #expect(seen.first?.hasSuffix("shot.png") == true)
    }

    @Test func waitUntilStableSettlesOnUnchangingFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-stable-\(UUID().uuidString).bin")
        try Data(repeating: 7, count: 128).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await FolderWatcher.waitUntilStable(path: url.path))
    }
}
