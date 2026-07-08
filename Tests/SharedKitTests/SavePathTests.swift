// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
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

    @Test func emptyParsedNameFallsBack() {
        withTempFolder { folder in
            var task = TaskSettings()
            task.nameFormatPattern = "%width" // empty when width unset
            let url = SavePath.screenshotURL(config: makeConfig(in: folder), task: task)
            #expect(url.lastPathComponent == "ShareX.png")
        }
    }
}
