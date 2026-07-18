// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct SavePathTests {
    private func makeConfig(in folder: URL, subfolderPattern: String = "") -> ApplicationConfig {
        var config = ApplicationConfig()
        config.useCustomScreenshotsPath = true
        config.customScreenshotsPath = folder.path
        config.saveImageSubFolderPattern = subfolderPattern
        return config
    }

    private var fixedDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current // SavePath parses with local time like the app does
        return calendar.date(from: DateComponents(year: 2024, month: 3, day: 7, hour: 9, minute: 5, second: 3))!
    }

    private func withTempFolder(_ body: (URL) throws -> Void) rethrows {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    @Test func buildsPatternedPathWithSubfolder() {
        withTempFolder { folder in
            let url = SavePath.screenshotURL(
                config: makeConfig(in: folder, subfolderPattern: "%y-%mo"),
                task: TaskSettings(),
                date: fixedDate
            )
            #expect(url.path == folder.appendingPathComponent("2024-03/2024-03-07_09-05-03.png").path)
        }
    }

    @Test func activeWindowPatternUsesProcessName() {
        withTempFolder { folder in
            let url = SavePath.screenshotURL(
                config: makeConfig(in: folder),
                task: TaskSettings(),
                processName: "Safari",
                date: fixedDate
            )
            #expect(url.lastPathComponent == "Safari_2024-03-07_09-05-03.png")
        }
    }

    @Test func appendsCounterWhenFileExists() throws {
        try withTempFolder { folder in
            var task = TaskSettings()
            task.nameFormatPattern = "static-name"
            let config = makeConfig(in: folder)

            let first = SavePath.screenshotURL(config: config, task: task)
            #expect(first.lastPathComponent == "static-name.png")

            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: first)
            let second = SavePath.screenshotURL(config: config, task: task)
            #expect(second.lastPathComponent == "static-name_1.png")
        }
    }

    @Test func baseURLNeverAutoNumbers() throws {
        try withTempFolder { folder in
            var task = TaskSettings()
            task.nameFormatPattern = "static-name"
            let config = makeConfig(in: folder)

            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: folder.appendingPathComponent("static-name.png"))
            let base = SavePath.screenshotBaseURL(config: config, task: task)
            #expect(base.lastPathComponent == "static-name.png")
        }
    }

    @Test func uniqueURLSkipsExistingCounters() throws {
        try withTempFolder { folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("shot.png")
            #expect(SavePath.uniqueURL(url) == url) // free name passes through

            try Data().write(to: url)
            try Data().write(to: folder.appendingPathComponent("shot_1.png"))
            #expect(SavePath.uniqueURL(url).lastPathComponent == "shot_2.png")
        }
    }

    @Test func resolvedURLAppliesFileExistAction() throws {
        try withTempFolder { folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("shot.png")

            // no collision: every action returns the URL untouched
            #expect(SavePath.resolvedURL(url, onExisting: .cancel) == url)

            try Data().write(to: url)
            #expect(SavePath.resolvedURL(url, onExisting: .overwrite) == url)
            #expect(SavePath.resolvedURL(url, onExisting: .cancel) == nil)
            #expect(SavePath.resolvedURL(url, onExisting: .uniqueName)?.lastPathComponent == "shot_1.png")
            // .ask must be resolved by UI first; unresolved it behaves like uniqueName
            #expect(SavePath.resolvedURL(url, onExisting: .ask)?.lastPathComponent == "shot_1.png")
        }
    }

    @Test func emptyParsedNameFallsBack() {
        withTempFolder { folder in
            var task = TaskSettings()
            task.nameFormatPattern = "%width" // empty when width unset
            let url = SavePath.screenshotURL(config: makeConfig(in: folder), task: task)
            #expect(url.lastPathComponent == "SwiftX.png")
        }
    }
}
