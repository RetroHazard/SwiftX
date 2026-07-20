// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

/// Phase 13 capture & image-output keys (C# TaskSettings names).
struct CaptureSettingsTests {
    @Test func captureFieldsDefaultWhenAbsent() throws {
        let settings = try JSONDecoder().decode(TaskSettings.self, from: Data("{}".utf8))
        #expect(settings.screenshotDelay == 0)
        #expect(settings.showCursor)
        #expect(settings.imageAutoJPEGQuality == 90)
        #expect(settings.imagePNGBitDepth == "Default")
        #expect(settings.imageGIFQuality == "Default")
        #expect(settings.fileExistAction == "UniqueName")
        #expect(!settings.showImageEffectsWindowAfterCapture)
        #expect(!settings.imageEffectOnlyRegionCapture)
        #expect(!settings.useRandomImageEffect)
    }

    @Test func captureFieldsRoundTripWithCSharpKeys() throws {
        var settings = TaskSettings()
        settings.screenshotDelay = 2.5
        settings.showCursor = false
        settings.imageAutoJPEGQuality = 70
        settings.imagePNGBitDepth = "Bit24"
        settings.imageGIFQuality = "Grayscale"
        settings.fileExistAction = "Ask"
        settings.showImageEffectsWindowAfterCapture = true
        settings.imageEffectOnlyRegionCapture = true
        settings.useRandomImageEffect = true

        let data = try JSONEncoder().encode(settings)
        let json = try #require(String(data: data, encoding: .utf8))
        for key in ["ScreenshotDelay", "ShowCursor", "ImageAutoJPEGQuality", "ImagePNGBitDepth",
                    "ImageGIFQuality", "FileExistAction", "ShowImageEffectsWindowAfterCapture",
                    "ImageEffectOnlyRegionCapture", "UseRandomImageEffect"] {
            #expect(json.contains("\"\(key)\""))
        }

        let reloaded = try JSONDecoder().decode(TaskSettings.self, from: data)
        #expect(reloaded.screenshotDelay == 2.5)
        #expect(!reloaded.showCursor)
        #expect(reloaded.imageAutoJPEGQuality == 70)
        #expect(reloaded.imagePNGBitDepth == "Bit24")
        #expect(reloaded.imageGIFQuality == "Grayscale")
        #expect(reloaded.fileExistAction == "Ask")
        #expect(reloaded.showImageEffectsWindowAfterCapture)
        #expect(reloaded.imageEffectOnlyRegionCapture)
        #expect(reloaded.useRandomImageEffect)
    }

    /// A Windows TaskSettings.json with C# enum-name values decodes as-is.
    @Test func windowsEnumNamesDecode() throws {
        let json = """
        {"FileExistAction": "Overwrite", "ImagePNGBitDepth": "Bit32", "ImageGIFQuality": "Bit4"}
        """
        let settings = try JSONDecoder().decode(TaskSettings.self, from: Data(json.utf8))
        #expect(FileExistAction(rawValue: settings.fileExistAction) == .overwrite)
        #expect(settings.imagePNGBitDepth == "Bit32")
        #expect(settings.imageGIFQuality == "Bit4")
    }
}
