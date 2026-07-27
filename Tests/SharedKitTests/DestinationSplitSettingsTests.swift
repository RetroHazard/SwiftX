// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Per-type destination split (image/text/file), per-type custom uploaders and
// the hideable tray menu items — key names stay C#-compatible where C# has
// the concept (TextDestination/FileDestination), macOS-only otherwise.

import Foundation
import Testing
@testable import SharedKit

struct DestinationSplitSettingsTests {
    @Test func taskSettingsDefaultAndDecodeDestinations() throws {
        let defaults = try JSONDecoder().decode(TaskSettings.self, from: Data("{}".utf8))
        #expect(defaults.imageDestination == "CustomImageUploader")
        #expect(defaults.textDestination == "CustomTextUploader")
        #expect(defaults.fileDestination == "CustomFileUploader")

        let windowsShaped = """
        { "ImageDestination": "Imgur", "TextDestination": "Pastebin", "FileDestination": "Dropbox" }
        """
        let decoded = try JSONDecoder().decode(TaskSettings.self, from: Data(windowsShaped.utf8))
        #expect(decoded.imageDestination == "Imgur")
        #expect(decoded.textDestination == "Pastebin")
        #expect(decoded.fileDestination == "Dropbox")
    }

    @Test func taskSettingsEncodeUsesCSharpKeys() throws {
        var settings = TaskSettings()
        settings.textDestination = "AmazonS3"
        settings.fileDestination = "AmazonS3"
        let encoded = String(data: try JSONEncoder().encode(settings), encoding: .utf8) ?? ""
        #expect(encoded.contains("\"TextDestination\""))
        #expect(encoded.contains("\"FileDestination\""))
    }

    @Test func uploadersConfigPerTypeActiveUploaders() throws {
        let defaults = try JSONDecoder().decode(UploadersConfig.self, from: Data("{}".utf8))
        #expect(defaults.activeTextCustomUploader.isEmpty)
        #expect(defaults.activeFileCustomUploader.isEmpty)

        var config = UploadersConfig()
        config.activeCustomUploader = "img.sxcu"
        config.activeTextCustomUploader = "text.sxcu"
        config.activeFileCustomUploader = "file.sxcu"
        let encoded = String(data: try JSONEncoder().encode(config), encoding: .utf8) ?? ""
        #expect(encoded.contains("\"ActiveTextCustomUploader\""))
        #expect(encoded.contains("\"ActiveFileCustomUploader\""))

        let decoded = try JSONDecoder().decode(UploadersConfig.self,
                                               from: try JSONEncoder().encode(config))
        #expect(decoded.activeTextCustomUploader == "text.sxcu")
        #expect(decoded.activeFileCustomUploader == "file.sxcu")
    }

    @Test func trayMenuHiddenItemsRoundTrip() throws {
        var config = ApplicationConfig()
        #expect(config.trayMenuHiddenItems.isEmpty)
        config.trayMenuHiddenItems = ["Tools", "Recent"]
        let data = try JSONEncoder().encode(config)
        #expect(String(data: data, encoding: .utf8)?.contains("\"TrayMenuHiddenItems\"") == true)
        let decoded = try JSONDecoder().decode(ApplicationConfig.self, from: data)
        #expect(decoded.trayMenuHiddenItems == ["Tools", "Recent"])
    }

    @Test func windowsBackupDetectionSniffsDefaultTaskSettings() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SXBDetect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let config = temp.appendingPathComponent("ApplicationConfig.json")

        // no config at all -> not a Windows backup
        #expect(!SettingsBackup.isWindowsShareXBackup(extractedAt: temp))

        // SwiftX's own flat config -> native backup
        try Data(#"{ "TaskViewMode": "ListView" }"#.utf8).write(to: config)
        #expect(!SettingsBackup.isWindowsShareXBackup(extractedAt: temp))

        // Windows nests everything under DefaultTaskSettings
        try Data(#"{ "DefaultTaskSettings": { "Job": "None" }, "ShowTray": true }"#.utf8).write(to: config)
        #expect(SettingsBackup.isWindowsShareXBackup(extractedAt: temp))
    }
}
