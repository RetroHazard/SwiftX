// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Windows ShareX .sxb mapping tests. Fixture shapes are taken from a real
// ShareX 21.0.0 backup (ApplicationConfig.json / UploadersConfig.json /
// HotkeysConfig.json inside the zip).

import Foundation
import Testing
@testable import SharedKit
@testable import UploadKit

struct ShareXBackupImportTests {
    private func json(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: - Hotkeys

    @Test func windowsKeyCombosMap() {
        let combo = ShareXBackupImport.keyCombo(fromWindowsKeys: "D4, Shift, Control", win: false)
        #expect(combo?.key == "4")
        #expect(combo?.modifiers.sorted() == ["control", "shift"])

        let letter = ShareXBackupImport.keyCombo(fromWindowsKeys: "S, Alt", win: false)
        #expect(letter?.key == "s")
        #expect(letter?.modifiers == ["option"])

        // Win flag maps to command
        let win = ShareXBackupImport.keyCombo(fromWindowsKeys: "A, Shift", win: true)
        #expect(win?.modifiers.sorted() == ["command", "shift"])

        // function keys may stay unmodified; other bare keys may not
        #expect(ShareXBackupImport.keyCombo(fromWindowsKeys: "F5", win: false)?.key == "f5")
        #expect(ShareXBackupImport.keyCombo(fromWindowsKeys: "A", win: false) == nil)

        // PrintScreen has no macOS equivalent
        #expect(ShareXBackupImport.keyCombo(fromWindowsKeys: "PrintScreen, Control", win: false) == nil)

        // OEM punctuation names
        #expect(ShareXBackupImport.keyCombo(fromWindowsKeys: "OemMinus, Control", win: false)?.key == "-")
        #expect(ShareXBackupImport.keyCombo(fromWindowsKeys: "Oemtilde, Control", win: false)?.key == "`")
    }

    @Test func hotkeyListImportsMappableEntriesAndCountsSkips() throws {
        let config = try json("""
        {
          "Hotkeys": [
            { "TaskSettings": { "Job": "RectangleRegion" },
              "HotkeyInfo": { "Hotkey": "D4, Shift, Control", "Win": false } },
            { "TaskSettings": { "Job": "PrintScreen" },
              "HotkeyInfo": { "Hotkey": "PrintScreen", "Win": false } },
            { "TaskSettings": { "Job": "NotARealJob" },
              "HotkeyInfo": { "Hotkey": "D5, Control", "Win": false } },
            { "TaskSettings": { "Job": "None" },
              "HotkeyInfo": { "Hotkey": "D6, Control", "Win": false } }
          ]
        }
        """)
        let (imported, skipped) = ShareXBackupImport.hotkeys(fromWindows: config)
        #expect(imported.count == 1)
        #expect(imported.first?.taskType == "RectangleRegion")
        #expect(imported.first?.key == "4")
        #expect(skipped == 1) // PrintScreen binding; unknown/None jobs don't count
    }

    // MARK: - ApplicationConfig

    @Test func applicationConfigMapsSharedKeys() throws {
        let windows = try json("""
        {
          "TrayLeftClickAction": "RectangleRegion",
          "TrayIconProgressEnabled": false,
          "RecentTasksShowInTrayMenu": false,
          "RecentTasksMaxCount": 15,
          "UploadLimit": 3,
          "MaxUploadFailRetry": 2,
          "DisableUpload": true,
          "ShowMultiUploadWarning": false,
          "ShowLargeFileSizeWarning": 100,
          "DisableHotkeysOnFullscreen": true,
          "HotkeyRepeatLimit": 1000,
          "SaveImageSubFolderPattern": "%y/%mo",
          "TaskViewMode": "ThumbnailView",
          "UseCustomScreenshotsPath": true,
          "CustomScreenshotsPath": "D:\\\\Users\\\\Someone\\\\Documents\\\\ShareX",
          "ActionsToolbarList": ["RectangleRegion", "BorderlessWindow", "OCR"],
          "QuickTaskPresets": [
            { "Name": "Save only", "AfterCaptureTasks": "SaveImageToFile", "AfterUploadTasks": "None" }
          ]
        }
        """)
        var config = ApplicationConfig()
        ShareXBackupImport.applicationConfig(fromWindows: windows, onto: &config)

        #expect(config.trayLeftClickAction == "RectangleRegion")
        #expect(!config.trayIconProgressEnabled)
        #expect(!config.recentTasksShowInTrayMenu)
        #expect(config.recentTasksMaxCount == 15)
        #expect(config.uploadLimit == 3)
        #expect(config.maxUploadFailRetry == 2)
        #expect(config.disableUpload)
        #expect(!config.showMultiUploadWarning)
        // Windows stores an MB threshold; any non-zero maps to the toggle
        #expect(config.showLargeFileSizeWarning)
        #expect(config.disableHotkeysOnFullscreen)
        #expect(config.hotkeyRepeatLimit == 1000)
        #expect(config.saveImageSubFolderPattern == "%y/%mo")
        #expect(config.taskViewMode == "ThumbnailView")
        // Windows path: never imported
        #expect(!config.useCustomScreenshotsPath)
        #expect(config.customScreenshotsPath.isEmpty)
        // unknown/Windows-only toolbar actions are dropped
        #expect(config.actionsToolbarList == ["RectangleRegion", "OCR"])
        #expect(config.quickTaskPresets.count == 1)
        #expect(config.quickTaskPresets.first?.afterCaptureTasks == [.saveImageToFile])
    }

    @Test func unknownTrayActionFallsBackToDefault() throws {
        let windows = try json("""
        { "TrayLeftClickAction": "SomeWindowsOnlyAction" }
        """)
        var config = ApplicationConfig()
        ShareXBackupImport.applicationConfig(fromWindows: windows, onto: &config)
        #expect(config.trayLeftClickAction == "ToggleTrayMenu")
    }

    // MARK: - TaskSettings

    @Test func taskSettingsMapNestedSections() throws {
        let defaults = try json("""
        {
          "AfterCaptureJob": "SaveImageToFile, UploadImageToHost",
          "AfterUploadJob": "CopyURLToClipboard, OpenURL",
          "ImageDestination": "CustomImageUploader",
          "TextDestination": "CustomTextUploader",
          "FileDestination": "AmazonS3",
          "URLShortenerDestination": "BITLY",
          "URLSharingServiceDestination": "Email",
          "GeneralSettings": {
            "PlaySoundAfterCapture": false,
            "PlaySoundAfterUpload": false,
            "ShowToastNotificationAfterTaskCompleted": false
          },
          "ImageSettings": {
            "ImageFormat": "JPEG",
            "ImageJPEGQuality": 85,
            "ImageAutoUseJPEG": false,
            "ImageAutoJPEGQuality": false,
            "FileExistAction": "Ask",
            "ThumbnailWidth": 320,
            "ThumbnailHeight": 0
          },
          "CaptureSettings": {
            "ShowCursor": false,
            "ScreenshotDelay": 2.5,
            "FFmpegOptions": { "FPS": 60, "GIFFPS": 10 }
          },
          "UploadSettings": {
            "NameFormatPattern": "%pn-%y%mo%d",
            "FileUploadUseNamePattern": true,
            "UseCustomTimeZone": true,
            "CustomTimeZone": { "Id": "UTC" }
          },
          "AdvancedSettings": {
            "EarlyCopyURL": true,
            "AutoClearClipboard": true
          }
        }
        """)
        var task = TaskSettings()
        ShareXBackupImport.taskSettings(fromWindows: defaults, onto: &task)

        #expect(task.afterCaptureJob == [.saveImageToFile, .uploadImageToHost])
        #expect(task.afterUploadJob == [.copyURLToClipboard, .openURL])
        #expect(task.imageDestination == "CustomImageUploader")
        #expect(task.textDestination == "CustomTextUploader")
        #expect(task.fileDestination == "AmazonS3")
        #expect(task.urlShortenerDestination == "BITLY")
        #expect(!task.playSoundAfterCapture)
        #expect(!task.playSoundAfterUpload)
        #expect(!task.showToastNotificationAfterTaskCompleted)
        #expect(task.imageFormat == "JPEG")
        #expect(task.imageJPEGQuality == 85)
        #expect(!task.imageAutoUseJPEG)
        // legacy bool-typed ImageAutoJPEGQuality must not import as 0/1
        #expect(task.imageAutoJPEGQuality == 90)
        #expect(task.fileExistAction == "Ask")
        #expect(task.thumbnailWidth == 320)
        #expect(task.thumbnailHeight == 0)
        #expect(!task.showCursor)
        #expect(task.screenshotDelay == 2.5)
        #expect(task.screenRecordFPS == 60)
        #expect(task.gifFPS == 10)
        #expect(task.nameFormatPattern == "%pn-%y%mo%d")
        #expect(task.fileUploadUseNamePattern)
        #expect(task.useCustomTimeZone)
        #expect(task.customTimeZoneIdentifier == "UTC")
        #expect(task.earlyCopyURL)
        #expect(task.autoClearClipboard)
    }

    // MARK: - UploadersConfig

    @Test func uploadersConfigMapsHostsAndSkipsNulls() throws {
        let windows = try json("""
        {
          "AmazonS3Settings": {
            "AccessKeyID": "AKIAEXAMPLE",
            "SecretAccessKey": "secret",
            "Endpoint": "s3.amazonaws.com",
            "Region": null,
            "Bucket": "my-bucket",
            "ObjectPrefix": "ShareX/%y/%mo"
          },
          "CheveretoUploader": { "UploadURL": "https://img.example/api/1/upload", "APIKey": "chv-key" },
          "CheveretoDirectURL": false,
          "VgymeUserKey": "vgy",
          "PuushAPIKey": "puush",
          "PomfUploader": { "UploadURL": "https://pomf.example/upload.php", "ResultURL": "https://a.pomf.example/" },
          "PushbulletSettings": { "UserAPIKey": "pb-key", "CurrentDevice": null, "DeviceList": null },
          "B2ApplicationKeyId": "b2id",
          "OwnCloudHost": "https://cloud.example",
          "SeafileAPIURL": null,
          "KuttSettings": { "Host": "https://kutt.example", "APIKey": "kutt-key", "Reuse": true },
          "YourlsAPIURL": "http://yoursite.com/yourls-api.php"
        }
        """)
        var config = UploadersConfig()
        ShareXBackupImport.uploadersConfig(fromWindows: windows, onto: &config)

        #expect(config.amazonS3.accessKeyID == "AKIAEXAMPLE")
        #expect(config.amazonS3.secretAccessKey == "secret")
        #expect(config.amazonS3.bucket == "my-bucket")
        // null Region keeps the default; AWS endpoints are implied by Region
        #expect(config.amazonS3.region == "us-east-1")
        #expect(config.amazonS3.endpoint.isEmpty)
        #expect(config.chevereto.uploadURL == "https://img.example/api/1/upload")
        #expect(config.chevereto.apiKey == "chv-key")
        #expect(!config.cheveretoDirectURL)
        #expect(config.vgymeUserKey == "vgy")
        #expect(config.puushAPIKey == "puush")
        #expect(config.pomf.uploadURL == "https://pomf.example/upload.php")
        #expect(config.pushbulletAPIKey == "pb-key")
        #expect(config.b2ApplicationKeyId == "b2id")
        #expect(config.ownCloudHost == "https://cloud.example")
        #expect(config.seafileAPIURL.isEmpty)
        #expect(config.kutt.host == "https://kutt.example")
        #expect(config.kutt.apiKey == "kutt-key")
        #expect(config.kutt.reuse)
        #expect(config.yourlsAPIURL == "http://yoursite.com/yourls-api.php")
    }

    @Test func customUploadersDecodeFromBackupList() throws {
        let windows = try json("""
        {
          "CustomUploadersList": [
            {
              "Version": "14.1.0",
              "Name": "RetroHazard Image Host",
              "DestinationType": "None",
              "RequestMethod": "POST",
              "RequestURL": "https://www.example.jp/static/upload.php",
              "Body": "MultipartFormData",
              "Arguments": { "secret": "example" },
              "FileFormName": "sharex",
              "URL": null,
              "ThumbnailURL": null,
              "DeletionURL": null,
              "ErrorMessage": null
            },
            {
              "Version": "12.0.0",
              "Name": "Legacy",
              "RequestURL": "https://legacy.example/up",
              "URL": "$json:url$"
            }
          ]
        }
        """)
        let items = ShareXBackupImport.customUploaders(fromWindows: windows)
        #expect(items.count == 2)
        #expect(items[0].name == "RetroHazard Image Host")
        #expect(items[0].fileFormName == "sharex")
        #expect(items[0].url.isEmpty)
        // pre-13.7.1 syntax migrates during backup import too
        #expect(items[1].url == "{json:url}")
    }

    @Test func windowsPathDetection() {
        #expect(ShareXBackupImport.isWindowsPath("D:\\Users\\Someone"))
        #expect(ShareXBackupImport.isWindowsPath("\\\\server\\share"))
        #expect(!ShareXBackupImport.isWindowsPath("/Users/someone/Pictures"))
        #expect(!ShareXBackupImport.isWindowsPath("~/Pictures/SwiftX"))
    }
}
