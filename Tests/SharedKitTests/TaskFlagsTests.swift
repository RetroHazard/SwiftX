// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct TaskFlagsTests {
    @Test func encodesAsCSharpStyleNameString() throws {
        let tasks: AfterCaptureTasks = [.copyImageToClipboard, .saveImageToFile]
        let data = try JSONEncoder().encode(tasks)
        #expect(String(data: data, encoding: .utf8) == "\"CopyImageToClipboard, SaveImageToFile\"")
    }

    @Test func decodesWindowsShareXString() throws {
        let json = "\"CopyImageToClipboard, SaveImageToFile, UploadImageToHost\""
        let tasks = try JSONDecoder().decode(AfterCaptureTasks.self, from: json.data(using: .utf8)!)
        #expect(tasks == [.copyImageToClipboard, .saveImageToFile, .uploadImageToHost])
    }

    @Test func decodesIntegerFallback() throws {
        // 1<<5 | 1<<8 as raw Json.NET integer output
        let tasks = try JSONDecoder().decode(AfterCaptureTasks.self, from: "288".data(using: .utf8)!)
        #expect(tasks == [.copyImageToClipboard, .saveImageToFile])
    }

    @Test func unknownNamesAreIgnored() throws {
        let json = "\"CopyImageToClipboard, SomeWindowsOnlyTask\""
        let tasks = try JSONDecoder().decode(AfterCaptureTasks.self, from: json.data(using: .utf8)!)
        #expect(tasks == .copyImageToClipboard)
    }

    @Test func noneRoundTrips() throws {
        let data = try JSONEncoder().encode(AfterCaptureTasks())
        #expect(String(data: data, encoding: .utf8) == "\"None\"")
        let decoded = try JSONDecoder().decode(AfterCaptureTasks.self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test func bitValuesMatchCSharpEnum() {
        #expect(AfterCaptureTasks.showQuickTaskMenu.rawValue == 1)
        #expect(AfterCaptureTasks.copyImageToClipboard.rawValue == 1 << 5)
        #expect(AfterCaptureTasks.saveImageToFile.rawValue == 1 << 8)
        #expect(AfterCaptureTasks.deleteFile.rawValue == 1 << 21)
        #expect(AfterUploadTasks.copyURLToClipboard.rawValue == 1 << 3)
    }

    @Test func taskFlagTitlesReadLikeCSharpDescriptions() {
        #expect(taskFlagTitle("SaveImageToFile") == "Save image to file")
        #expect(taskFlagTitle("CopyURLToClipboard") == "Copy URL to clipboard")
        #expect(taskFlagTitle("DoOCR") == "Do OCR")
        #expect(taskFlagTitle("ShowQRCode") == "Show QR code")
    }

    @Test func quickTaskPresetRoundTripsCSharpJSON() throws {
        // Windows ShareX QuickTaskPresets entry shape
        let json = """
        {"Name": "Save, Upload", "AfterCaptureTasks": "SaveImageToFile, UploadImageToHost",
         "AfterUploadTasks": "CopyURLToClipboard"}
        """
        let preset = try JSONDecoder().decode(QuickTaskPreset.self, from: json.data(using: .utf8)!)
        #expect(preset.name == "Save, Upload")
        #expect(preset.afterCaptureTasks == [.saveImageToFile, .uploadImageToHost])
        #expect(preset.afterUploadTasks == [.copyURLToClipboard])
        #expect(preset.isValid)

        // separator entry: no tasks
        #expect(!QuickTaskPreset().isValid)

        // unnamed presets describe their flags, like C# ToString()
        let unnamed = QuickTaskPreset(afterCaptureTasks: [.uploadImageToHost],
                                      afterUploadTasks: [.copyURLToClipboard])
        #expect(unnamed.displayName == "Upload image to host, Copy URL to clipboard")
    }

    @Test func taskSettingsDefaultsAndDecode() throws {
        #expect(TaskSettings().afterCaptureJob == [.copyImageToClipboard, .saveImageToFile])

        let json = """
        {"AfterCaptureJob": "PinToScreen, SaveImageToFile", "AfterUploadJob": "CopyURLToClipboard, OpenURL"}
        """
        let settings = try JSONDecoder().decode(TaskSettings.self, from: json.data(using: .utf8)!)
        #expect(settings.afterCaptureJob == [.pinToScreen, .saveImageToFile])
        #expect(settings.afterUploadJob == [.copyURLToClipboard, .openURL])
    }
}
