// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

// Serialized: tests swap the global SettingsPaths.root
@Suite(.serialized)
struct SettingsTests {
    private func withTempRoot(_ body: (URL) throws -> Void) rethrows {
        let original = SettingsPaths.root
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXTests-\(UUID().uuidString)", isDirectory: true)
        SettingsPaths.root = temp
        defer {
            SettingsPaths.root = original
            try? FileManager.default.removeItem(at: temp)
        }
        try body(temp)
    }

    @Test func loadReturnsDefaultsWhenFileMissing() {
        withTempRoot { _ in
            let config = ApplicationConfig.load()
            #expect(!config.useCustomScreenshotsPath)
            #expect(config.saveImageSubFolderPattern == "%y-%mo")
        }
    }

    @Test func saveLoadRoundTrip() throws {
        try withTempRoot { _ in
            var config = ApplicationConfig()
            config.useCustomScreenshotsPath = true
            config.customScreenshotsPath = "/tmp/shots"
            try config.save()

            let loaded = ApplicationConfig.load()
            #expect(loaded.useCustomScreenshotsPath)
            #expect(loaded.customScreenshotsPath == "/tmp/shots")
            #expect(loaded.screenshotsFolder.path == "/tmp/shots")
        }
    }

    @Test func savedJSONUsesPascalCaseKeysForWindowsCompatibility() throws {
        try withTempRoot { _ in
            try ApplicationConfig().save()
            let json = try String(contentsOf: ApplicationConfig.fileURL, encoding: .utf8)
            #expect(json.contains("\"UseCustomScreenshotsPath\""))
            #expect(json.contains("\"SaveImageSubFolderPattern\""))
        }
    }

    @Test func settingsBackupRoundTrips() throws {
        try withTempRoot { root in
            var task = TaskSettings()
            task.nameFormatPattern = "backup-test-%y"
            try task.save()
            var hotkeys = HotkeySettings()
            hotkeys.hotkeys = [HotkeyConfig(.printScreen, key: "3", modifiers: ["command"])]
            try hotkeys.save()

            let zip = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftx-backup-test-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: zip) }
            try SettingsBackup.export(to: zip)
            #expect(FileManager.default.fileExists(atPath: zip.path))

            // wipe the settings root, then restore from the archive
            try FileManager.default.removeItem(at: root)
            try SettingsBackup.restore(from: zip)
            #expect(TaskSettings.load().nameFormatPattern == "backup-test-%y")
            #expect(HotkeySettings.load().hotkeys.first?.key == "3")
        }
    }

    @Test func unknownAndMissingKeysAreTolerated() throws {
        try withTempRoot { temp in
            // Simulates loading a config written by Windows ShareX with many more fields
            let json = """
            {
              "CustomScreenshotsPath": "/tmp/x",
              "UseCustomScreenshotsPath": true,
              "SomeWindowsOnlyField": {"Nested": [1, 2, 3]},
              "Language": "en"
            }
            """
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            try json.write(to: ApplicationConfig.fileURL, atomically: true, encoding: .utf8)

            let config = ApplicationConfig.load()
            #expect(config.customScreenshotsPath == "/tmp/x")
            #expect(config.useCustomScreenshotsPath)
            #expect(config.saveImageSubFolderPattern == "%y-%mo") // missing key -> default
        }
    }

    @Test func corruptFileFallsBackToDefaults() throws {
        try withTempRoot { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            try "not json {{{".write(to: ApplicationConfig.fileURL, atomically: true, encoding: .utf8)
            let config = ApplicationConfig.load()
            #expect(!config.useCustomScreenshotsPath)
        }
    }

    @Test func taskSettingsDefaults() {
        withTempRoot { _ in
            let settings = TaskSettings.load()
            #expect(settings.nameFormatPattern == "%y-%mo-%d_%h-%mi-%s")
        }
    }

    @Test func hotkeySettingsRoundTrip() throws {
        try withTempRoot { _ in
            var settings = HotkeySettings()
            settings.hotkeys = [HotkeyConfig(taskType: "RectangleRegion")]
            try settings.save()
            #expect(HotkeySettings.load().hotkeys == [HotkeyConfig(taskType: "RectangleRegion")])
        }
    }
}
