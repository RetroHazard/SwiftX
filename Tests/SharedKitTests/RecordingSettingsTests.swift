// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct RecordingSettingsTests {
    @Test func recordingFieldsDefaultWhenAbsent() throws {
        let settings = try JSONDecoder().decode(TaskSettings.self, from: Data("{}".utf8))
        #expect(settings.screenRecordFPS == 30)
        #expect(settings.gifFPS == 15)
        #expect(settings.screenRecordCodec == "H264")
        #expect(settings.screenRecordShowCursor)
        #expect(settings.screenRecordStartDelay == 0)
        #expect(!settings.screenRecordFixedDuration)
        #expect(settings.screenRecordDuration == 3)
        #expect(!settings.screenRecordAskConfirmationOnAbort)
        #expect(!settings.screenRecordTwoPassEncoding)
    }

    @Test func sessionFieldsRoundTripWithCSharpKeys() throws {
        var settings = TaskSettings()
        settings.screenRecordShowCursor = false
        settings.screenRecordStartDelay = 3
        settings.screenRecordFixedDuration = true
        settings.screenRecordDuration = 12.5
        settings.screenRecordAskConfirmationOnAbort = true
        settings.screenRecordTwoPassEncoding = true

        let data = try JSONEncoder().encode(settings)
        let json = try #require(String(data: data, encoding: .utf8))
        for key in ["ScreenRecordShowCursor", "ScreenRecordStartDelay", "ScreenRecordFixedDuration",
                    "ScreenRecordDuration", "ScreenRecordAskConfirmationOnAbort",
                    "ScreenRecordTwoPassEncoding"] {
            #expect(json.contains("\"\(key)\""))
        }

        let reloaded = try JSONDecoder().decode(TaskSettings.self, from: data)
        #expect(!reloaded.screenRecordShowCursor)
        #expect(reloaded.screenRecordStartDelay == 3)
        #expect(reloaded.screenRecordFixedDuration)
        #expect(reloaded.screenRecordDuration == 12.5)
        #expect(reloaded.screenRecordAskConfirmationOnAbort)
        #expect(reloaded.screenRecordTwoPassEncoding)
    }

    @Test func recordingFieldsRoundTripWithPascalCaseKeys() throws {
        var settings = TaskSettings()
        settings.screenRecordFPS = 60
        settings.gifFPS = 10
        settings.screenRecordCodec = "HEVC"

        let data = try JSONEncoder().encode(settings)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"ScreenRecordFPS\":60"))
        #expect(json.contains("\"GIFFPS\":10"))

        let reloaded = try JSONDecoder().decode(TaskSettings.self, from: data)
        #expect(reloaded.screenRecordFPS == 60)
        #expect(reloaded.gifFPS == 10)
        #expect(reloaded.screenRecordCodec == "HEVC")
    }
}
