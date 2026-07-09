// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
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
