// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import SharedKit

/// Phase 14 upload/shell keys (C# TaskSettings + ApplicationSettings names).
struct UploadSettingsTests {
    @Test func taskFieldsDefaultWhenAbsent() throws {
        let settings = try JSONDecoder().decode(TaskSettings.self, from: Data("{}".utf8))
        #expect(settings.clipboardContentFormat == "$result")
        #expect(settings.openURLFormat == "$result")
        #expect(settings.balloonTipContentFormat == "$result")
        #expect(!settings.earlyCopyURL)
        #expect(!settings.urlRegexReplace)
        #expect(!settings.resultForceHTTPS)
        #expect(settings.autoShortenURLLength == 0)
        #expect(!settings.clipboardUploadURLContents)
        #expect(!settings.clipboardUploadShortenURL)
        #expect(!settings.clipboardUploadShareURL)
        #expect(!settings.clipboardUploadAutoIndexFolder)
        #expect(!settings.autoClearClipboard)
        #expect(!settings.fileUploadUseNamePattern)
        #expect(!settings.fileUploadReplaceProblematicCharacters)
        #expect(!settings.useCustomTimeZone)
        #expect(settings.showToastNotificationAfterTaskCompleted)
        #expect(!settings.disableNotificationsOnFullscreen)
        #expect(!settings.useCustomCaptureSound)
        #expect(!settings.useCustomTaskCompletedSound)
        #expect(!settings.useCustomErrorSound)
    }

    @Test func taskFieldsRoundTripWithCSharpKeys() throws {
        var settings = TaskSettings()
        settings.clipboardContentFormat = "![]($result)"
        settings.earlyCopyURL = true
        settings.urlRegexReplace = true
        settings.urlRegexReplacePattern = "a"
        settings.urlRegexReplaceReplacement = "b"
        settings.resultForceHTTPS = true
        settings.autoShortenURLLength = 60
        settings.clipboardUploadURLContents = true
        settings.autoClearClipboard = true
        settings.fileUploadUseNamePattern = true
        settings.useCustomTimeZone = true
        settings.customTimeZoneIdentifier = "Asia/Tokyo"
        settings.showToastNotificationAfterTaskCompleted = false
        settings.useCustomErrorSound = true
        settings.customErrorSoundPath = "/tmp/err.aiff"

        let data = try JSONEncoder().encode(settings)
        let json = try #require(String(data: data, encoding: .utf8))
        for key in ["ClipboardContentFormat", "OpenURLFormat", "BalloonTipContentFormat",
                    "EarlyCopyURL", "URLRegexReplace", "URLRegexReplacePattern",
                    "URLRegexReplaceReplacement", "ResultForceHTTPS", "AutoShortenURLLength",
                    "ClipboardUploadURLContents", "ClipboardUploadShortenURL",
                    "ClipboardUploadShareURL", "ClipboardUploadAutoIndexFolder",
                    "AutoClearClipboard", "FileUploadUseNamePattern",
                    "FileUploadReplaceProblematicCharacters", "UseCustomTimeZone",
                    "CustomTimeZoneIdentifier", "ShowToastNotificationAfterTaskCompleted",
                    "DisableNotificationsOnFullscreen", "UseCustomCaptureSound",
                    "UseCustomErrorSound", "CustomErrorSoundPath"] {
            #expect(json.contains("\"\(key)\""), "missing \(key)")
        }

        let reloaded = try JSONDecoder().decode(TaskSettings.self, from: data)
        #expect(reloaded.clipboardContentFormat == "![]($result)")
        #expect(reloaded.earlyCopyURL)
        #expect(reloaded.urlRegexReplace)
        #expect(reloaded.urlRegexReplacePattern == "a")
        #expect(reloaded.urlRegexReplaceReplacement == "b")
        #expect(reloaded.resultForceHTTPS)
        #expect(reloaded.autoShortenURLLength == 60)
        #expect(reloaded.clipboardUploadURLContents)
        #expect(reloaded.autoClearClipboard)
        #expect(reloaded.fileUploadUseNamePattern)
        #expect(reloaded.useCustomTimeZone)
        #expect(reloaded.customTimeZoneIdentifier == "Asia/Tokyo")
        #expect(!reloaded.showToastNotificationAfterTaskCompleted)
        #expect(reloaded.useCustomErrorSound)
        #expect(reloaded.customErrorSoundPath == "/tmp/err.aiff")
    }

    @Test func applicationFieldsDefaultWhenAbsent() throws {
        let config = try JSONDecoder().decode(ApplicationConfig.self, from: Data("{}".utf8))
        #expect(config.uploadLimit == 5)
        #expect(config.maxUploadFailRetry == 1)
        #expect(!config.disableUpload)
        #expect(config.showMultiUploadWarning)
        #expect(config.showLargeFileSizeWarning)
        #expect(config.recentTasksShowInTrayMenu)
        #expect(config.recentTasksMaxCount == 10)
        #expect(config.trayLeftClickAction == "ToggleTrayMenu")
        #expect(config.trayIconProgressEnabled)
        #expect(!config.disableHotkeysOnFullscreen)
        #expect(config.hotkeyRepeatLimit == 500)
        #expect(config.actionsToolbarList == ActionsToolbarDefaults.list)
        #expect(!config.actionsToolbarLockPosition)
        #expect(!config.actionsToolbarRunAtStartup)
    }

    @Test func applicationFieldsRoundTripWithCSharpKeys() throws {
        var config = ApplicationConfig()
        config.uploadLimit = 2
        config.maxUploadFailRetry = 3
        config.disableUpload = true
        config.showMultiUploadWarning = false
        config.recentTasksMaxCount = 20
        config.trayLeftClickAction = "RectangleRegion"
        config.disableHotkeysOnFullscreen = true
        config.hotkeyRepeatLimit = 250
        config.actionsToolbarList = ["RectangleRegion", "OpenHistory"]
        config.actionsToolbarLockPosition = true

        let data = try JSONEncoder().encode(config)
        let json = try #require(String(data: data, encoding: .utf8))
        for key in ["UploadLimit", "MaxUploadFailRetry", "DisableUpload", "ShowMultiUploadWarning",
                    "ShowLargeFileSizeWarning", "RecentTasksShowInTrayMenu", "RecentTasksMaxCount",
                    "TrayLeftClickAction", "TrayIconProgressEnabled", "DisableHotkeysOnFullscreen",
                    "HotkeyRepeatLimit", "ActionsToolbarList", "ActionsToolbarLockPosition",
                    "ActionsToolbarRunAtStartup"] {
            #expect(json.contains("\"\(key)\""), "missing \(key)")
        }

        let reloaded = try JSONDecoder().decode(ApplicationConfig.self, from: data)
        #expect(reloaded.uploadLimit == 2)
        #expect(reloaded.maxUploadFailRetry == 3)
        #expect(reloaded.disableUpload)
        #expect(!reloaded.showMultiUploadWarning)
        #expect(reloaded.recentTasksMaxCount == 20)
        #expect(reloaded.trayLeftClickAction == "RectangleRegion")
        #expect(reloaded.disableHotkeysOnFullscreen)
        #expect(reloaded.hotkeyRepeatLimit == 250)
        #expect(reloaded.actionsToolbarList == ["RectangleRegion", "OpenHistory"])
        #expect(reloaded.actionsToolbarLockPosition)
    }
}
