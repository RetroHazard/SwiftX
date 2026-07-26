// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// JSON settings engine. Key names are PascalCase to stay compatible with the
// Windows ShareX config files, so backups/presets can be imported later.
// Structs start with the fields Phase 0/1 need and grow per phase.

import CoreGraphics
import Foundation

public enum SettingsPaths {
    /// Overridable for tests. Everything under root is addressed relative to it,
    /// so migrating the whole directory from the pre-rename "ShareX" name is safe.
    public static var root: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let new = appSupport.appendingPathComponent("SwiftX", isDirectory: true)
        let old = appSupport.appendingPathComponent("ShareX", isDirectory: true)
        if !FileManager.default.fileExists(atPath: new.path),
           FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: new)
        }
        return new
    }()

    /// Not migrated like root: history entries store absolute paths into the old
    /// folder, so existing screenshots stay put; new captures land here.
    public static var defaultScreenshotsFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftX", isDirectory: true)
    }
}

public protocol SettingsFile: Codable {
    static var fileName: String { get }
    init()
}

public extension SettingsFile {
    static var fileURL: URL {
        SettingsPaths.root.appendingPathComponent(fileName)
    }

    /// Missing or unreadable file falls back to defaults; unknown JSON keys are ignored.
    static func load() -> Self {
        loadRaw()
    }

    func save() throws {
        try saveRaw()
    }

    /// Plain JSON decode with no secret handling. Types that keep secrets in the
    /// Keychain build their `load()` on top of this.
    static func loadRaw() -> Self {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        return value
    }

    /// Plain JSON encode with no secret handling.
    func saveRaw() throws {
        try FileManager.default.createDirectory(at: SettingsPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
    }
}

/// Shared machinery for the config types that keep some fields in the Keychain
/// instead of on disk. A type lists its secret fields as `account -> key path`;
/// the two helpers below move values between those fields and `SecretStore`.
public protocol KeychainBackedSettings: SettingsFile {
    /// Stable Keychain account name -> the String field that holds the secret.
    static var secretKeyPaths: [String: WritableKeyPath<Self, String>] { get }
}

public extension KeychainBackedSettings {
    /// Namespaces the Keychain account by file so two config types can reuse a
    /// field name without colliding.
    private static func account(_ key: String) -> String { "\(fileName)/\(key)" }

    /// Load from JSON, then overlay any secrets held in the Keychain. A secret
    /// still sitting in the JSON (e.g. a freshly imported Windows config) is
    /// kept as-is and migrates to the Keychain on the next `save()`.
    static func loadApplyingSecrets() -> Self {
        var value = loadRaw()
        for (key, keyPath) in secretKeyPaths {
            if let secret = SecretStore.get(account(key)), !secret.isEmpty {
                value[keyPath: keyPath] = secret
            }
        }
        return value
    }

    /// Move each secret into the Keychain, then write JSON with those fields
    /// blanked. The plaintext is dropped from disk ONLY when the Keychain
    /// accepted the write, so a locked/unavailable Keychain degrades to the old
    /// behavior instead of losing credentials. An empty field is left alone
    /// rather than deleted, so a Keychain that failed to load at startup can't
    /// cause a later save to wipe a valid secret.
    func saveMigratingSecrets() throws {
        var copy = self
        for (key, keyPath) in Self.secretKeyPaths {
            let value = copy[keyPath: keyPath]
            guard !value.isEmpty else { continue }
            if SecretStore.set(value, for: Self.account(key)) {
                copy[keyPath: keyPath] = ""
            }
        }
        try copy.saveRaw()
    }
}

/// One entry in the quick task menu. Field names match the C# QuickTaskInfo
/// JSON shape; an entry with no after-capture tasks renders as a separator.
public struct QuickTaskPreset: Codable, Equatable, Sendable {
    public var name = ""
    public var afterCaptureTasks: AfterCaptureTasks = []
    public var afterUploadTasks: AfterUploadTasks = []

    public var isValid: Bool { !afterCaptureTasks.isEmpty }

    public var displayName: String {
        if !name.isEmpty { return name }
        var result = afterCaptureTasks.friendlyString
        if afterCaptureTasks.contains(.uploadImageToHost), !afterUploadTasks.isEmpty {
            result += ", " + afterUploadTasks.friendlyString
        }
        return result
    }

    public init(name: String = "", afterCaptureTasks: AfterCaptureTasks = [],
                afterUploadTasks: AfterUploadTasks = []) {
        self.name = name
        self.afterCaptureTasks = afterCaptureTasks
        self.afterUploadTasks = afterUploadTasks
    }

    /// C# QuickTaskInfo.DefaultPresets, including its separator entry.
    public static let defaultPresets: [QuickTaskPreset] = [
        QuickTaskPreset(name: "Save, Upload, Copy URL",
                        afterCaptureTasks: [.saveImageToFile, .uploadImageToHost],
                        afterUploadTasks: [.copyURLToClipboard]),
        QuickTaskPreset(name: "Save, Copy image",
                        afterCaptureTasks: [.saveImageToFile, .copyImageToClipboard]),
        QuickTaskPreset(name: "Save, Copy image file",
                        afterCaptureTasks: [.saveImageToFile, .copyFileToClipboard]),
        QuickTaskPreset(name: "Annotate, Save, Upload, Copy URL",
                        afterCaptureTasks: [.annotateImage, .saveImageToFile, .uploadImageToHost],
                        afterUploadTasks: [.copyURLToClipboard]),
        QuickTaskPreset(),
        QuickTaskPreset(name: "Upload, Copy URL",
                        afterCaptureTasks: [.uploadImageToHost],
                        afterUploadTasks: [.copyURLToClipboard]),
        QuickTaskPreset(name: "Save", afterCaptureTasks: [.saveImageToFile]),
        QuickTaskPreset(name: "Copy image", afterCaptureTasks: [.copyImageToClipboard]),
        QuickTaskPreset(name: "Annotate", afterCaptureTasks: [.annotateImage])
    ]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case afterCaptureTasks = "AfterCaptureTasks"
        case afterUploadTasks = "AfterUploadTasks"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        afterCaptureTasks = try c.decodeIfPresent(AfterCaptureTasks.self, forKey: .afterCaptureTasks) ?? []
        afterUploadTasks = try c.decodeIfPresent(AfterUploadTasks.self, forKey: .afterUploadTasks) ?? []
    }
}

public struct ApplicationConfig: SettingsFile {
    public static let fileName = "ApplicationConfig.json"

    public var useCustomScreenshotsPath = false
    public var customScreenshotsPath = ""
    public var saveImageSubFolderPattern = "%y-%mo"
    /// C# TaskViewMode enum name: "ListView" or "ThumbnailView".
    public var taskViewMode = "ListView"
    /// One automatic retry after a failed upload (C# ApplicationSettings key).
    public var retryUpload = true
    /// AI image analysis (macOS-only keys; C# nests these per provider in
    /// AIOptions - one OpenAI-compatible endpoint covers OpenAI, OpenRouter
    /// and Gemini's compatibility API here).
    public var aiBaseURL = "https://api.openai.com/v1"
    public var aiAPIKey = ""
    public var aiModel = "gpt-5-mini"
    public var aiPrompt = "What is in this image?"
    // Upload guards (C# ApplicationSettings keys).
    /// Maximum simultaneous uploads; further tasks queue.
    public var uploadLimit = 5
    /// Retries after a failed upload when RetryUpload is on.
    public var maxUploadFailRetry = 1
    /// Master switch: upload tasks no-op while set.
    public var disableUpload = false
    /// Confirm before uploading more than 10 files at once.
    public var showMultiUploadWarning = true
    /// Confirm before uploading files larger than 100 MB.
    public var showLargeFileSizeWarning = true

    // Tray & shell (C# ApplicationSettings keys).
    public var recentTasksShowInTrayMenu = true
    public var recentTasksMaxCount = 10
    /// HotkeyType raw value run on a left click; "ToggleTrayMenu" keeps the
    /// menu-on-click default (C# TrayLeftClickAction).
    public var trayLeftClickAction = "ToggleTrayMenu"
    /// Draw upload progress onto the status icon (C# TrayIconProgressEnabled).
    public var trayIconProgressEnabled = true
    public var disableHotkeysOnFullscreen = false
    /// Minimum milliseconds between repeats of the same hotkey (0 = off).
    public var hotkeyRepeatLimit = 500
    /// HotkeyType raw values shown in the actions toolbar (C# ActionsToolbarList).
    public var actionsToolbarList = ActionsToolbarDefaults.list
    public var actionsToolbarLockPosition = false
    public var actionsToolbarRunAtStartup = false

    /// Quick task menu entries (C# ApplicationSettings.QuickTaskPresets).
    public var quickTaskPresets = QuickTaskPreset.defaultPresets
    /// Auto capture region as a C# Rectangle string "X, Y, Width, Height";
    /// empty = not configured (C# ApplicationSettings.AutoCaptureRegion).
    public var autoCaptureRegion = ""
    /// Seconds between auto captures (C# AutoCaptureRepeatTime).
    public var autoCaptureRepeatTime: Double = 60
    /// Skip the timer tick while uploads are in flight (C# AutoCaptureWaitUpload).
    public var autoCaptureWaitUpload = true

    public var screenshotsFolder: URL {
        if useCustomScreenshotsPath, !customScreenshotsPath.isEmpty {
            return URL(fileURLWithPath: (customScreenshotsPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return SettingsPaths.defaultScreenshotsFolder
    }

    public init() {}

    enum CodingKeys: String, CodingKey {
        case useCustomScreenshotsPath = "UseCustomScreenshotsPath"
        case customScreenshotsPath = "CustomScreenshotsPath"
        case saveImageSubFolderPattern = "SaveImageSubFolderPattern"
        case taskViewMode = "TaskViewMode"
        case retryUpload = "RetryUpload"
        case aiBaseURL = "AIBaseURL"
        case aiAPIKey = "AIAPIKey"
        case aiModel = "AIModel"
        case aiPrompt = "AIPrompt"
        case uploadLimit = "UploadLimit"
        case maxUploadFailRetry = "MaxUploadFailRetry"
        case disableUpload = "DisableUpload"
        case showMultiUploadWarning = "ShowMultiUploadWarning"
        case showLargeFileSizeWarning = "ShowLargeFileSizeWarning"
        case recentTasksShowInTrayMenu = "RecentTasksShowInTrayMenu"
        case recentTasksMaxCount = "RecentTasksMaxCount"
        case trayLeftClickAction = "TrayLeftClickAction"
        case trayIconProgressEnabled = "TrayIconProgressEnabled"
        case disableHotkeysOnFullscreen = "DisableHotkeysOnFullscreen"
        case hotkeyRepeatLimit = "HotkeyRepeatLimit"
        case actionsToolbarList = "ActionsToolbarList"
        case actionsToolbarLockPosition = "ActionsToolbarLockPosition"
        case actionsToolbarRunAtStartup = "ActionsToolbarRunAtStartup"
        case quickTaskPresets = "QuickTaskPresets"
        case autoCaptureRegion = "AutoCaptureRegion"
        case autoCaptureRepeatTime = "AutoCaptureRepeatTime"
        case autoCaptureWaitUpload = "AutoCaptureWaitUpload"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useCustomScreenshotsPath = try c.decodeIfPresent(Bool.self, forKey: .useCustomScreenshotsPath) ?? false
        customScreenshotsPath = try c.decodeIfPresent(String.self, forKey: .customScreenshotsPath) ?? ""
        saveImageSubFolderPattern = try c.decodeIfPresent(String.self, forKey: .saveImageSubFolderPattern) ?? "%y-%mo"
        taskViewMode = try c.decodeIfPresent(String.self, forKey: .taskViewMode) ?? "ListView"
        retryUpload = try c.decodeIfPresent(Bool.self, forKey: .retryUpload) ?? true
        aiBaseURL = try c.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? "https://api.openai.com/v1"
        aiAPIKey = try c.decodeIfPresent(String.self, forKey: .aiAPIKey) ?? ""
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? "gpt-5-mini"
        aiPrompt = try c.decodeIfPresent(String.self, forKey: .aiPrompt) ?? "What is in this image?"
        uploadLimit = try c.decodeIfPresent(Int.self, forKey: .uploadLimit) ?? 5
        maxUploadFailRetry = try c.decodeIfPresent(Int.self, forKey: .maxUploadFailRetry) ?? 1
        disableUpload = try c.decodeIfPresent(Bool.self, forKey: .disableUpload) ?? false
        showMultiUploadWarning = try c.decodeIfPresent(Bool.self, forKey: .showMultiUploadWarning) ?? true
        showLargeFileSizeWarning = try c.decodeIfPresent(Bool.self, forKey: .showLargeFileSizeWarning) ?? true
        recentTasksShowInTrayMenu = try c.decodeIfPresent(Bool.self, forKey: .recentTasksShowInTrayMenu) ?? true
        recentTasksMaxCount = try c.decodeIfPresent(Int.self, forKey: .recentTasksMaxCount) ?? 10
        trayLeftClickAction = try c.decodeIfPresent(String.self, forKey: .trayLeftClickAction) ?? "ToggleTrayMenu"
        trayIconProgressEnabled = try c.decodeIfPresent(Bool.self, forKey: .trayIconProgressEnabled) ?? true
        disableHotkeysOnFullscreen = try c.decodeIfPresent(Bool.self, forKey: .disableHotkeysOnFullscreen) ?? false
        hotkeyRepeatLimit = try c.decodeIfPresent(Int.self, forKey: .hotkeyRepeatLimit) ?? 500
        actionsToolbarList = try c.decodeIfPresent([String].self, forKey: .actionsToolbarList)
            ?? ActionsToolbarDefaults.list
        actionsToolbarLockPosition = try c.decodeIfPresent(Bool.self, forKey: .actionsToolbarLockPosition) ?? false
        actionsToolbarRunAtStartup = try c.decodeIfPresent(Bool.self, forKey: .actionsToolbarRunAtStartup) ?? false
        quickTaskPresets = try c.decodeIfPresent([QuickTaskPreset].self, forKey: .quickTaskPresets)
            ?? QuickTaskPreset.defaultPresets
        autoCaptureRegion = try c.decodeIfPresent(String.self, forKey: .autoCaptureRegion) ?? ""
        autoCaptureRepeatTime = try c.decodeIfPresent(Double.self, forKey: .autoCaptureRepeatTime) ?? 60
        autoCaptureWaitUpload = try c.decodeIfPresent(Bool.self, forKey: .autoCaptureWaitUpload) ?? true
    }
}

extension ApplicationConfig: KeychainBackedSettings {
    /// The AI provider API key is the only secret in this file.
    public static let secretKeyPaths: [String: WritableKeyPath<ApplicationConfig, String>] = [
        "AIAPIKey": \.aiAPIKey
    ]

    public static func load() -> ApplicationConfig { loadApplyingSecrets() }
    public func save() throws { try saveMigratingSecrets() }
}

/// The pre-Phase-14 fixed actions-toolbar button set, now the default for the
/// configurable C# ActionsToolbarList.
public enum ActionsToolbarDefaults {
    public static let list = [
        "RectangleRegion", "ActiveWindow", "PrintScreen", "ScreenRecorder",
        "ScreenRecorderGIF", "ImageEditor", "ColorPicker", "OpenHistory"
    ]
}

/// C# System.Drawing.Rectangle TypeConverter format: "X, Y, Width, Height".
public enum CSharpRect {
    public static func parse(_ string: String) -> CGRect? {
        let parts = string.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    public static func string(from rect: CGRect) -> String {
        [rect.origin.x, rect.origin.y, rect.width, rect.height]
            .map { String(Int($0.rounded())) }.joined(separator: ", ")
    }
}

public struct TaskSettings: SettingsFile {
    public static let fileName = "TaskSettings.json"

    public var nameFormatPattern = "%y-%mo-%d_%h-%mi-%s"
    public var nameFormatPatternActiveWindow = "%pn_%y-%mo-%d_%h-%mi-%s"
    public var afterCaptureJob: AfterCaptureTasks = [.copyImageToClipboard, .saveImageToFile]
    public var afterUploadJob: AfterUploadTasks = [.copyURLToClipboard]
    /// C# ImageDestination enum name; string keeps unknown values loadable.
    public var imageDestination = "CustomImageUploader"
    /// C# UrlShortenerType enum name.
    public var urlShortenerDestination = "ISGD"
    /// C# URLSharingServices enum name.
    public var urlSharingServiceDestination = "Email"
    /// Seconds to wait before a screenshot fires (C# ScreenshotDelay, decimal).
    public var screenshotDelay: Double = 0
    /// Include the pointer in screenshots (C# ShowCursor).
    public var showCursor = true
    public var screenRecordFPS = 30
    public var gifFPS = 15
    /// "H264" or "HEVC" (macOS-only key; C# keeps codec inside FFmpegOptions).
    public var screenRecordCodec = "H264"
    /// Include the pointer in recordings (C# ScreenRecordShowCursor).
    public var screenRecordShowCursor = true
    /// Countdown before recording starts (C# ScreenRecordStartDelay, seconds).
    public var screenRecordStartDelay: Double = 0
    /// Auto-stop after ScreenRecordDuration seconds (C# ScreenRecordFixedDuration).
    public var screenRecordFixedDuration = false
    public var screenRecordDuration: Double = 3
    /// Ask before discarding a recording (C# ScreenRecordAskConfirmationOnAbort).
    public var screenRecordAskConfirmationOnAbort = false
    /// Two-pass ffmpeg encode for VP9/VP8 (C# ScreenRecordTwoPassEncoding).
    public var screenRecordTwoPassEncoding = false
    /// Record system audio into MP4/MOV recordings (macOS-only keys; C# keeps
    /// audio sources inside FFmpegOptions).
    public var screenRecordSystemAudio = false
    /// Record the microphone (needs macOS 15+ and mic permission).
    public var screenRecordMicrophone = false
    /// When non-empty, replaces the preset ffmpeg output arguments for
    /// transcoded formats (C# FFmpegOptions.UseCustomCommands equivalent).
    public var screenRecordCustomFFmpegArgs = ""

    // Image output. Key names and defaults match C# TaskSettingsImage.
    /// C# EImageFormat enum name: PNG/JPEG/GIF/BMP/TIFF.
    public var imageFormat = "PNG"
    public var imageJPEGQuality = 90
    /// Captures whose longest side exceeds ImageAutoUseJPEGSize pixels save as JPEG regardless of format.
    public var imageAutoUseJPEG = true
    public var imageAutoUseJPEGSize = 2048
    /// JPEG quality when the auto-JPEG rule kicks in (C# ImageAutoJPEGQuality).
    public var imageAutoJPEGQuality = 90
    /// C# PNGBitDepth enum name: Default/Bit32/Bit24.
    public var imagePNGBitDepth = "Default"
    /// C# GIFQuality enum name: Default/Bit8/Bit4/Grayscale.
    public var imageGIFQuality = "Default"
    /// C# FileExistAction enum name: Ask/Overwrite/UniqueName/Cancel.
    /// Defaults to UniqueName (SwiftX's historical auto-numbering; C# defaults to Ask).
    public var fileExistAction = "UniqueName"
    /// Open the effects editor with the capture instead of applying silently.
    public var showImageEffectsWindowAfterCapture = false
    /// Apply the effects task only to region captures (C# ImageEffectOnlyRegionCapture).
    public var imageEffectOnlyRegionCapture = false
    /// Pick a random preset per capture instead of the selected one.
    public var useRandomImageEffect = false
    public var thumbnailWidth = 200
    public var thumbnailHeight = 0
    /// Appended to the file name (before the extension).
    public var thumbnailName = "-thumbnail"
    /// Only save the thumbnail when the image is larger than the thumbnail box.
    public var thumbnailCheckSize = false

    // URL post-processing (C# TaskSettingsUpload / TaskSettingsAdvanced keys).
    /// $result template for what lands on the clipboard (e.g. "![]($result)").
    public var clipboardContentFormat = "$result"
    /// $result template for the URL opened in the browser.
    public var openURLFormat = "$result"
    /// $result template for the completion banner body.
    public var balloonTipContentFormat = "$result"
    /// Copy the raw URL the moment the upload finishes, before shortening.
    public var earlyCopyURL = false
    public var urlRegexReplace = false
    public var urlRegexReplacePattern = ""
    public var urlRegexReplaceReplacement = ""
    public var resultForceHTTPS = false
    /// Shorten automatically when the URL is longer than this (0 = off).
    public var autoShortenURLLength = 0

    // Clipboard upload intelligence (C# TaskSettingsUpload keys).
    /// Clipboard URL: download its contents and upload that file.
    public var clipboardUploadURLContents = false
    /// Clipboard URL: shorten it instead of uploading the text.
    public var clipboardUploadShortenURL = false
    /// Clipboard URL: open the sharing service instead of uploading.
    public var clipboardUploadShareURL = false
    /// Clipboard folder: upload a generated folder index instead of the text.
    public var clipboardUploadAutoIndexFolder = false
    /// Clear the clipboard after a clipboard upload is dispatched.
    public var autoClearClipboard = false

    // File upload naming (C# TaskSettingsUpload keys).
    /// Rename uploaded files with the name pattern instead of their own name.
    public var fileUploadUseNamePattern = false
    /// Replace URL-hostile characters in upload names (spaces -> underscores).
    public var fileUploadReplaceProblematicCharacters = false
    public var useCustomTimeZone = false
    /// TimeZone identifier ("UTC", "America/New_York"); C# stores a full
    /// TimeZoneInfo, which has no macOS equivalent, hence the macOS-only key.
    public var customTimeZoneIdentifier = "UTC"

    /// Actions: external programs run on the captured file (C# ExternalPrograms).
    public var externalPrograms: [ExternalProgramSettings] = []

    public var playSoundAfterCapture = true
    public var playSoundAfterUpload = true
    // Notification granularity (C# TaskSettingsGeneral keys).
    /// Master banner switch; sounds still follow the PlaySound keys.
    public var showToastNotificationAfterTaskCompleted = true
    public var disableNotificationsOnFullscreen = false
    public var useCustomCaptureSound = false
    public var customCaptureSoundPath = ""
    public var useCustomTaskCompletedSound = false
    public var customTaskCompletedSoundPath = ""
    public var useCustomErrorSound = false
    public var customErrorSoundPath = ""

    /// Watch folders: upload files that appear in monitored directories.
    public var watchFolderEnabled = false
    public var watchFolderList: [WatchFolderSettings] = []

    public var scrollingCapture = ScrollingCaptureOptions()

    // ponytail: C# nests these under CaptureSettings; flattened like the other task keys
    /// CustomRegion capture rect, C# Rectangle string "X, Y, Width, Height" (cocoa coordinates here).
    public var captureCustomRegion = ""
    /// CustomWindow capture: window title (or app name) substring to match.
    public var captureCustomWindow = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case nameFormatPattern = "NameFormatPattern"
        case nameFormatPatternActiveWindow = "NameFormatPatternActiveWindow"
        case afterCaptureJob = "AfterCaptureJob"
        case afterUploadJob = "AfterUploadJob"
        case imageDestination = "ImageDestination"
        case urlShortenerDestination = "URLShortenerDestination"
        case urlSharingServiceDestination = "URLSharingServiceDestination"
        case screenshotDelay = "ScreenshotDelay"
        case showCursor = "ShowCursor"
        case screenRecordFPS = "ScreenRecordFPS"
        case gifFPS = "GIFFPS"
        case screenRecordCodec = "ScreenRecordCodec"
        case screenRecordShowCursor = "ScreenRecordShowCursor"
        case screenRecordStartDelay = "ScreenRecordStartDelay"
        case screenRecordFixedDuration = "ScreenRecordFixedDuration"
        case screenRecordDuration = "ScreenRecordDuration"
        case screenRecordAskConfirmationOnAbort = "ScreenRecordAskConfirmationOnAbort"
        case screenRecordTwoPassEncoding = "ScreenRecordTwoPassEncoding"
        case screenRecordSystemAudio = "ScreenRecordSystemAudio"
        case screenRecordMicrophone = "ScreenRecordMicrophone"
        case screenRecordCustomFFmpegArgs = "ScreenRecordCustomFFmpegArgs"
        case imageFormat = "ImageFormat"
        case imageJPEGQuality = "ImageJPEGQuality"
        case imageAutoUseJPEG = "ImageAutoUseJPEG"
        case imageAutoUseJPEGSize = "ImageAutoUseJPEGSize"
        case imageAutoJPEGQuality = "ImageAutoJPEGQuality"
        case imagePNGBitDepth = "ImagePNGBitDepth"
        case imageGIFQuality = "ImageGIFQuality"
        case fileExistAction = "FileExistAction"
        case showImageEffectsWindowAfterCapture = "ShowImageEffectsWindowAfterCapture"
        case imageEffectOnlyRegionCapture = "ImageEffectOnlyRegionCapture"
        case useRandomImageEffect = "UseRandomImageEffect"
        case thumbnailWidth = "ThumbnailWidth"
        case thumbnailHeight = "ThumbnailHeight"
        case thumbnailName = "ThumbnailName"
        case thumbnailCheckSize = "ThumbnailCheckSize"
        case clipboardContentFormat = "ClipboardContentFormat"
        case openURLFormat = "OpenURLFormat"
        case balloonTipContentFormat = "BalloonTipContentFormat"
        case earlyCopyURL = "EarlyCopyURL"
        case urlRegexReplace = "URLRegexReplace"
        case urlRegexReplacePattern = "URLRegexReplacePattern"
        case urlRegexReplaceReplacement = "URLRegexReplaceReplacement"
        case resultForceHTTPS = "ResultForceHTTPS"
        case autoShortenURLLength = "AutoShortenURLLength"
        case clipboardUploadURLContents = "ClipboardUploadURLContents"
        case clipboardUploadShortenURL = "ClipboardUploadShortenURL"
        case clipboardUploadShareURL = "ClipboardUploadShareURL"
        case clipboardUploadAutoIndexFolder = "ClipboardUploadAutoIndexFolder"
        case autoClearClipboard = "AutoClearClipboard"
        case fileUploadUseNamePattern = "FileUploadUseNamePattern"
        case fileUploadReplaceProblematicCharacters = "FileUploadReplaceProblematicCharacters"
        case useCustomTimeZone = "UseCustomTimeZone"
        case customTimeZoneIdentifier = "CustomTimeZoneIdentifier"
        case externalPrograms = "ExternalPrograms"
        case playSoundAfterCapture = "PlaySoundAfterCapture"
        case playSoundAfterUpload = "PlaySoundAfterUpload"
        case showToastNotificationAfterTaskCompleted = "ShowToastNotificationAfterTaskCompleted"
        case disableNotificationsOnFullscreen = "DisableNotificationsOnFullscreen"
        case useCustomCaptureSound = "UseCustomCaptureSound"
        case customCaptureSoundPath = "CustomCaptureSoundPath"
        case useCustomTaskCompletedSound = "UseCustomTaskCompletedSound"
        case customTaskCompletedSoundPath = "CustomTaskCompletedSoundPath"
        case useCustomErrorSound = "UseCustomErrorSound"
        case customErrorSoundPath = "CustomErrorSoundPath"
        case watchFolderEnabled = "WatchFolderEnabled"
        case watchFolderList = "WatchFolderList"
        case scrollingCapture = "ScrollingCaptureOptions"
        case captureCustomRegion = "CaptureCustomRegion"
        case captureCustomWindow = "CaptureCustomWindow"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameFormatPattern = try c.decodeIfPresent(String.self, forKey: .nameFormatPattern) ?? "%y-%mo-%d_%h-%mi-%s"
        nameFormatPatternActiveWindow = try c.decodeIfPresent(String.self, forKey: .nameFormatPatternActiveWindow) ?? "%pn_%y-%mo-%d_%h-%mi-%s"
        afterCaptureJob = try c.decodeIfPresent(AfterCaptureTasks.self, forKey: .afterCaptureJob) ?? [.copyImageToClipboard, .saveImageToFile]
        afterUploadJob = try c.decodeIfPresent(AfterUploadTasks.self, forKey: .afterUploadJob) ?? [.copyURLToClipboard]
        imageDestination = try c.decodeIfPresent(String.self, forKey: .imageDestination) ?? "CustomImageUploader"
        urlShortenerDestination = try c.decodeIfPresent(String.self, forKey: .urlShortenerDestination) ?? "ISGD"
        urlSharingServiceDestination = try c.decodeIfPresent(String.self, forKey: .urlSharingServiceDestination) ?? "Email"
        screenshotDelay = try c.decodeIfPresent(Double.self, forKey: .screenshotDelay) ?? 0
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? true
        screenRecordFPS = try c.decodeIfPresent(Int.self, forKey: .screenRecordFPS) ?? 30
        gifFPS = try c.decodeIfPresent(Int.self, forKey: .gifFPS) ?? 15
        screenRecordCodec = try c.decodeIfPresent(String.self, forKey: .screenRecordCodec) ?? "H264"
        screenRecordShowCursor = try c.decodeIfPresent(Bool.self, forKey: .screenRecordShowCursor) ?? true
        screenRecordStartDelay = try c.decodeIfPresent(Double.self, forKey: .screenRecordStartDelay) ?? 0
        screenRecordFixedDuration = try c.decodeIfPresent(Bool.self, forKey: .screenRecordFixedDuration) ?? false
        screenRecordDuration = try c.decodeIfPresent(Double.self, forKey: .screenRecordDuration) ?? 3
        screenRecordAskConfirmationOnAbort = try c.decodeIfPresent(Bool.self, forKey: .screenRecordAskConfirmationOnAbort) ?? false
        screenRecordTwoPassEncoding = try c.decodeIfPresent(Bool.self, forKey: .screenRecordTwoPassEncoding) ?? false
        screenRecordSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .screenRecordSystemAudio) ?? false
        screenRecordMicrophone = try c.decodeIfPresent(Bool.self, forKey: .screenRecordMicrophone) ?? false
        screenRecordCustomFFmpegArgs = try c.decodeIfPresent(String.self, forKey: .screenRecordCustomFFmpegArgs) ?? ""
        imageFormat = try c.decodeIfPresent(String.self, forKey: .imageFormat) ?? "PNG"
        imageJPEGQuality = try c.decodeIfPresent(Int.self, forKey: .imageJPEGQuality) ?? 90
        imageAutoUseJPEG = try c.decodeIfPresent(Bool.self, forKey: .imageAutoUseJPEG) ?? true
        imageAutoUseJPEGSize = try c.decodeIfPresent(Int.self, forKey: .imageAutoUseJPEGSize) ?? 2048
        imageAutoJPEGQuality = try c.decodeIfPresent(Int.self, forKey: .imageAutoJPEGQuality) ?? 90
        imagePNGBitDepth = try c.decodeIfPresent(String.self, forKey: .imagePNGBitDepth) ?? "Default"
        imageGIFQuality = try c.decodeIfPresent(String.self, forKey: .imageGIFQuality) ?? "Default"
        fileExistAction = try c.decodeIfPresent(String.self, forKey: .fileExistAction) ?? "UniqueName"
        showImageEffectsWindowAfterCapture = try c.decodeIfPresent(Bool.self, forKey: .showImageEffectsWindowAfterCapture) ?? false
        imageEffectOnlyRegionCapture = try c.decodeIfPresent(Bool.self, forKey: .imageEffectOnlyRegionCapture) ?? false
        useRandomImageEffect = try c.decodeIfPresent(Bool.self, forKey: .useRandomImageEffect) ?? false
        thumbnailWidth = try c.decodeIfPresent(Int.self, forKey: .thumbnailWidth) ?? 200
        thumbnailHeight = try c.decodeIfPresent(Int.self, forKey: .thumbnailHeight) ?? 0
        thumbnailName = try c.decodeIfPresent(String.self, forKey: .thumbnailName) ?? "-thumbnail"
        thumbnailCheckSize = try c.decodeIfPresent(Bool.self, forKey: .thumbnailCheckSize) ?? false
        clipboardContentFormat = try c.decodeIfPresent(String.self, forKey: .clipboardContentFormat) ?? "$result"
        openURLFormat = try c.decodeIfPresent(String.self, forKey: .openURLFormat) ?? "$result"
        balloonTipContentFormat = try c.decodeIfPresent(String.self, forKey: .balloonTipContentFormat) ?? "$result"
        earlyCopyURL = try c.decodeIfPresent(Bool.self, forKey: .earlyCopyURL) ?? false
        urlRegexReplace = try c.decodeIfPresent(Bool.self, forKey: .urlRegexReplace) ?? false
        urlRegexReplacePattern = try c.decodeIfPresent(String.self, forKey: .urlRegexReplacePattern) ?? ""
        urlRegexReplaceReplacement = try c.decodeIfPresent(String.self, forKey: .urlRegexReplaceReplacement) ?? ""
        resultForceHTTPS = try c.decodeIfPresent(Bool.self, forKey: .resultForceHTTPS) ?? false
        autoShortenURLLength = try c.decodeIfPresent(Int.self, forKey: .autoShortenURLLength) ?? 0
        clipboardUploadURLContents = try c.decodeIfPresent(Bool.self, forKey: .clipboardUploadURLContents) ?? false
        clipboardUploadShortenURL = try c.decodeIfPresent(Bool.self, forKey: .clipboardUploadShortenURL) ?? false
        clipboardUploadShareURL = try c.decodeIfPresent(Bool.self, forKey: .clipboardUploadShareURL) ?? false
        clipboardUploadAutoIndexFolder = try c.decodeIfPresent(Bool.self, forKey: .clipboardUploadAutoIndexFolder) ?? false
        autoClearClipboard = try c.decodeIfPresent(Bool.self, forKey: .autoClearClipboard) ?? false
        fileUploadUseNamePattern = try c.decodeIfPresent(Bool.self, forKey: .fileUploadUseNamePattern) ?? false
        fileUploadReplaceProblematicCharacters = try c.decodeIfPresent(Bool.self, forKey: .fileUploadReplaceProblematicCharacters) ?? false
        useCustomTimeZone = try c.decodeIfPresent(Bool.self, forKey: .useCustomTimeZone) ?? false
        customTimeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .customTimeZoneIdentifier) ?? "UTC"
        externalPrograms = try c.decodeIfPresent([ExternalProgramSettings].self, forKey: .externalPrograms) ?? []
        playSoundAfterCapture = try c.decodeIfPresent(Bool.self, forKey: .playSoundAfterCapture) ?? true
        playSoundAfterUpload = try c.decodeIfPresent(Bool.self, forKey: .playSoundAfterUpload) ?? true
        showToastNotificationAfterTaskCompleted = try c.decodeIfPresent(Bool.self, forKey: .showToastNotificationAfterTaskCompleted) ?? true
        disableNotificationsOnFullscreen = try c.decodeIfPresent(Bool.self, forKey: .disableNotificationsOnFullscreen) ?? false
        useCustomCaptureSound = try c.decodeIfPresent(Bool.self, forKey: .useCustomCaptureSound) ?? false
        customCaptureSoundPath = try c.decodeIfPresent(String.self, forKey: .customCaptureSoundPath) ?? ""
        useCustomTaskCompletedSound = try c.decodeIfPresent(Bool.self, forKey: .useCustomTaskCompletedSound) ?? false
        customTaskCompletedSoundPath = try c.decodeIfPresent(String.self, forKey: .customTaskCompletedSoundPath) ?? ""
        useCustomErrorSound = try c.decodeIfPresent(Bool.self, forKey: .useCustomErrorSound) ?? false
        customErrorSoundPath = try c.decodeIfPresent(String.self, forKey: .customErrorSoundPath) ?? ""
        watchFolderEnabled = try c.decodeIfPresent(Bool.self, forKey: .watchFolderEnabled) ?? false
        watchFolderList = try c.decodeIfPresent([WatchFolderSettings].self, forKey: .watchFolderList) ?? []
        scrollingCapture = try c.decodeIfPresent(ScrollingCaptureOptions.self, forKey: .scrollingCapture)
            ?? ScrollingCaptureOptions()
        captureCustomRegion = try c.decodeIfPresent(String.self, forKey: .captureCustomRegion) ?? ""
        captureCustomWindow = try c.decodeIfPresent(String.self, forKey: .captureCustomWindow) ?? ""
    }
}

/// C# ScrollingCaptureOptions. The scroll method is always a synthetic mouse
/// wheel on macOS (the other C# methods are Windows message based).
public struct ScrollingCaptureOptions: Codable, Equatable, Sendable {
    /// Milliseconds to wait before the first shot.
    public var startDelay = 300
    /// Send Home before starting so the capture begins at the top.
    public var autoScrollTop = false
    /// Milliseconds between scroll steps.
    public var scrollDelay = 300
    /// Wheel lines per scroll step.
    public var scrollAmount = 2
    /// Detect and trim a fixed bottom edge (sticky footers, scrollbars).
    public var autoIgnoreBottomEdge = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case startDelay = "StartDelay"
        case autoScrollTop = "AutoScrollTop"
        case scrollDelay = "ScrollDelay"
        case scrollAmount = "ScrollAmount"
        case autoIgnoreBottomEdge = "AutoIgnoreBottomEdge"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDelay = try c.decodeIfPresent(Int.self, forKey: .startDelay) ?? 300
        autoScrollTop = try c.decodeIfPresent(Bool.self, forKey: .autoScrollTop) ?? false
        scrollDelay = try c.decodeIfPresent(Int.self, forKey: .scrollDelay) ?? 300
        scrollAmount = try c.decodeIfPresent(Int.self, forKey: .scrollAmount) ?? 2
        autoIgnoreBottomEdge = try c.decodeIfPresent(Bool.self, forKey: .autoIgnoreBottomEdge) ?? true
    }
}

/// One monitored directory. Field names match the C# WatchFolderSettings JSON.
public struct WatchFolderSettings: Codable, Equatable, Sendable {
    public var folderPath = ""
    /// Glob for file names ("*.png"); empty matches everything.
    public var filter = ""
    public var includeSubdirectories = false
    public var moveFilesToScreenshotsFolder = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case folderPath = "FolderPath"
        case filter = "Filter"
        case includeSubdirectories = "IncludeSubdirectories"
        case moveFilesToScreenshotsFolder = "MoveFilesToScreenshotsFolder"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folderPath = try c.decodeIfPresent(String.self, forKey: .folderPath) ?? ""
        filter = try c.decodeIfPresent(String.self, forKey: .filter) ?? ""
        includeSubdirectories = try c.decodeIfPresent(Bool.self, forKey: .includeSubdirectories) ?? false
        moveFilesToScreenshotsFolder = try c.decodeIfPresent(Bool.self, forKey: .moveFilesToScreenshotsFolder) ?? false
    }
}

public struct HotkeySettings: SettingsFile {
    public static let fileName = "HotkeysConfig.json"

    // Empty until defaults are seeded on first launch or the user records hotkeys
    public var hotkeys: [HotkeyConfig] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case hotkeys = "Hotkeys"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeys = try c.decodeIfPresent([HotkeyConfig].self, forKey: .hotkeys) ?? []
    }
}

public struct HotkeyConfig: Codable, Equatable {
    /// HotkeyType raw value; stored as a string so unknown/future values still load.
    public var taskType: String
    public var key: String?
    public var modifiers: [String]

    public init(taskType: String, key: String? = nil, modifiers: [String] = []) {
        self.taskType = taskType
        self.key = key
        self.modifiers = modifiers
    }

    public init(_ type: HotkeyType, key: String, modifiers: [String]) {
        self.init(taskType: type.rawValue, key: key, modifiers: modifiers)
    }

    public var type: HotkeyType? { HotkeyType(rawValue: taskType) }
    public var combo: KeyCombo? { key.map { KeyCombo(key: $0, modifiers: modifiers) } }

    enum CodingKeys: String, CodingKey {
        case taskType = "TaskType"
        case key = "Key"
        case modifiers = "Modifiers"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskType = try c.decodeIfPresent(String.self, forKey: .taskType) ?? HotkeyType.none.rawValue
        key = try c.decodeIfPresent(String.self, forKey: .key)
        modifiers = try c.decodeIfPresent([String].self, forKey: .modifiers) ?? []
    }
}

public struct UploadersConfig: SettingsFile {
    public static let fileName = "UploadersConfig.json"

    /// File name of the active .sxcu in CustomUploaders/.
    public var activeCustomUploader = ""
    public var amazonS3 = AmazonS3Settings()

    // URL shorteners. Flat key names match the C# UploadersConfig, except
    // bit.ly: C# stores an OAuth2Info from an app-key flow we can't reuse,
    // so we store a user-generated personal access token instead.
    public var bitlyAccessToken = ""
    public var bitlyDomain = ""
    public var polrAPIHostname = ""
    public var polrAPIKey = ""
    public var polrIsSecret = false
    public var polrUseAPIv1 = false
    public var yourlsAPIURL = ""
    public var yourlsSignature = ""
    public var yourlsUsername = ""
    public var yourlsPassword = ""
    public var kutt = KuttSettings()
    public var zeroWidthShortenerURL = ""
    public var zeroWidthShortenerToken = ""

    // Simple file hosts. Key names match the C# UploadersConfig.
    public var pomf = PomfUploaderSettings()
    public var vgymeUserKey = ""
    public var sulAPIKey = ""
    public var lithiio = LithiioSettings()
    public var puushAPIKey = ""
    public var chevereto = CheveretoSettings()
    public var cheveretoDirectURL = true
    public var streamableUsername = ""
    public var streamablePassword = ""

    // Cloud storage + self-hosted destinations. Key names match the C# UploadersConfig,
    // except PushbulletAPIKey: C# nests an encrypted key we couldn't import anyway.
    public var b2ApplicationKeyId = ""
    public var b2ApplicationKey = ""
    public var b2BucketName = ""
    public var b2UploadPath = "SwiftX/%y/%mo"
    public var b2UseCustomUrl = false
    public var b2CustomUrl = ""
    public var azureStorageAccountName = ""
    public var azureStorageAccountAccessKey = ""
    public var azureStorageContainer = ""
    public var azureStorageEnvironment = "blob.core.windows.net"
    public var azureStorageCustomDomain = ""
    public var azureStorageUploadPath = ""
    public var azureStorageCacheControl = ""
    public var ownCloudHost = ""
    public var ownCloudUsername = ""
    public var ownCloudPassword = ""
    public var ownCloudPath = "/"
    public var ownCloudCreateShare = true
    public var seafileAPIURL = ""
    public var seafileAuthToken = ""
    public var seafileRepoID = ""
    public var seafilePath = "/"
    public var pushbulletAPIKey = ""

    // OAuth2 app credentials, keyed by OAuthProviderID raw value. Empty by
    // default: an absent/blank client ID keeps the host disabled (see
    // OAuthCredentials.swift). A dictionary keeps CodingKeys stable as hosts
    // are added.
    public var oauthApps: [String: OAuthAppCredentials] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case activeCustomUploader = "ActiveCustomUploader"
        case amazonS3 = "AmazonS3Settings"
        case bitlyAccessToken = "BitlyAccessToken"
        case bitlyDomain = "BitlyDomain"
        case polrAPIHostname = "PolrAPIHostname"
        case polrAPIKey = "PolrAPIKey"
        case polrIsSecret = "PolrIsSecret"
        case polrUseAPIv1 = "PolrUseAPIv1"
        case yourlsAPIURL = "YourlsAPIURL"
        case yourlsSignature = "YourlsSignature"
        case yourlsUsername = "YourlsUsername"
        case yourlsPassword = "YourlsPassword"
        case kutt = "KuttSettings"
        case zeroWidthShortenerURL = "ZeroWidthShortenerURL"
        case zeroWidthShortenerToken = "ZeroWidthShortenerToken"
        case pomf = "PomfUploader"
        case vgymeUserKey = "VgymeUserKey"
        case sulAPIKey = "SulAPIKey"
        case lithiio = "LithiioSettings"
        case puushAPIKey = "PuushAPIKey"
        case chevereto = "CheveretoUploader"
        case cheveretoDirectURL = "CheveretoDirectURL"
        case streamableUsername = "StreamableUsername"
        case streamablePassword = "StreamablePassword"
        case b2ApplicationKeyId = "B2ApplicationKeyId"
        case b2ApplicationKey = "B2ApplicationKey"
        case b2BucketName = "B2BucketName"
        case b2UploadPath = "B2UploadPath"
        case b2UseCustomUrl = "B2UseCustomUrl"
        case b2CustomUrl = "B2CustomUrl"
        case azureStorageAccountName = "AzureStorageAccountName"
        case azureStorageAccountAccessKey = "AzureStorageAccountAccessKey"
        case azureStorageContainer = "AzureStorageContainer"
        case azureStorageEnvironment = "AzureStorageEnvironment"
        case azureStorageCustomDomain = "AzureStorageCustomDomain"
        case azureStorageUploadPath = "AzureStorageUploadPath"
        case azureStorageCacheControl = "AzureStorageCacheControl"
        case ownCloudHost = "OwnCloudHost"
        case ownCloudUsername = "OwnCloudUsername"
        case ownCloudPassword = "OwnCloudPassword"
        case ownCloudPath = "OwnCloudPath"
        case ownCloudCreateShare = "OwnCloudCreateShare"
        case seafileAPIURL = "SeafileAPIURL"
        case seafileAuthToken = "SeafileAuthToken"
        case seafileRepoID = "SeafileRepoID"
        case seafilePath = "SeafilePath"
        case pushbulletAPIKey = "PushbulletAPIKey"
        case oauthApps = "OAuthApps"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeCustomUploader = try c.decodeIfPresent(String.self, forKey: .activeCustomUploader) ?? ""
        amazonS3 = try c.decodeIfPresent(AmazonS3Settings.self, forKey: .amazonS3) ?? AmazonS3Settings()
        bitlyAccessToken = try c.decodeIfPresent(String.self, forKey: .bitlyAccessToken) ?? ""
        bitlyDomain = try c.decodeIfPresent(String.self, forKey: .bitlyDomain) ?? ""
        polrAPIHostname = try c.decodeIfPresent(String.self, forKey: .polrAPIHostname) ?? ""
        polrAPIKey = try c.decodeIfPresent(String.self, forKey: .polrAPIKey) ?? ""
        polrIsSecret = try c.decodeIfPresent(Bool.self, forKey: .polrIsSecret) ?? false
        polrUseAPIv1 = try c.decodeIfPresent(Bool.self, forKey: .polrUseAPIv1) ?? false
        yourlsAPIURL = try c.decodeIfPresent(String.self, forKey: .yourlsAPIURL) ?? ""
        yourlsSignature = try c.decodeIfPresent(String.self, forKey: .yourlsSignature) ?? ""
        yourlsUsername = try c.decodeIfPresent(String.self, forKey: .yourlsUsername) ?? ""
        yourlsPassword = try c.decodeIfPresent(String.self, forKey: .yourlsPassword) ?? ""
        kutt = try c.decodeIfPresent(KuttSettings.self, forKey: .kutt) ?? KuttSettings()
        zeroWidthShortenerURL = try c.decodeIfPresent(String.self, forKey: .zeroWidthShortenerURL) ?? ""
        zeroWidthShortenerToken = try c.decodeIfPresent(String.self, forKey: .zeroWidthShortenerToken) ?? ""
        pomf = try c.decodeIfPresent(PomfUploaderSettings.self, forKey: .pomf) ?? PomfUploaderSettings()
        vgymeUserKey = try c.decodeIfPresent(String.self, forKey: .vgymeUserKey) ?? ""
        sulAPIKey = try c.decodeIfPresent(String.self, forKey: .sulAPIKey) ?? ""
        lithiio = try c.decodeIfPresent(LithiioSettings.self, forKey: .lithiio) ?? LithiioSettings()
        puushAPIKey = try c.decodeIfPresent(String.self, forKey: .puushAPIKey) ?? ""
        chevereto = try c.decodeIfPresent(CheveretoSettings.self, forKey: .chevereto) ?? CheveretoSettings()
        cheveretoDirectURL = try c.decodeIfPresent(Bool.self, forKey: .cheveretoDirectURL) ?? true
        streamableUsername = try c.decodeIfPresent(String.self, forKey: .streamableUsername) ?? ""
        streamablePassword = try c.decodeIfPresent(String.self, forKey: .streamablePassword) ?? ""
        b2ApplicationKeyId = try c.decodeIfPresent(String.self, forKey: .b2ApplicationKeyId) ?? ""
        b2ApplicationKey = try c.decodeIfPresent(String.self, forKey: .b2ApplicationKey) ?? ""
        b2BucketName = try c.decodeIfPresent(String.self, forKey: .b2BucketName) ?? ""
        b2UploadPath = try c.decodeIfPresent(String.self, forKey: .b2UploadPath) ?? "SwiftX/%y/%mo"
        b2UseCustomUrl = try c.decodeIfPresent(Bool.self, forKey: .b2UseCustomUrl) ?? false
        b2CustomUrl = try c.decodeIfPresent(String.self, forKey: .b2CustomUrl) ?? ""
        azureStorageAccountName = try c.decodeIfPresent(String.self, forKey: .azureStorageAccountName) ?? ""
        azureStorageAccountAccessKey = try c.decodeIfPresent(String.self, forKey: .azureStorageAccountAccessKey) ?? ""
        azureStorageContainer = try c.decodeIfPresent(String.self, forKey: .azureStorageContainer) ?? ""
        azureStorageEnvironment = try c.decodeIfPresent(String.self, forKey: .azureStorageEnvironment) ?? "blob.core.windows.net"
        azureStorageCustomDomain = try c.decodeIfPresent(String.self, forKey: .azureStorageCustomDomain) ?? ""
        azureStorageUploadPath = try c.decodeIfPresent(String.self, forKey: .azureStorageUploadPath) ?? ""
        azureStorageCacheControl = try c.decodeIfPresent(String.self, forKey: .azureStorageCacheControl) ?? ""
        ownCloudHost = try c.decodeIfPresent(String.self, forKey: .ownCloudHost) ?? ""
        ownCloudUsername = try c.decodeIfPresent(String.self, forKey: .ownCloudUsername) ?? ""
        ownCloudPassword = try c.decodeIfPresent(String.self, forKey: .ownCloudPassword) ?? ""
        ownCloudPath = try c.decodeIfPresent(String.self, forKey: .ownCloudPath) ?? "/"
        ownCloudCreateShare = try c.decodeIfPresent(Bool.self, forKey: .ownCloudCreateShare) ?? true
        seafileAPIURL = try c.decodeIfPresent(String.self, forKey: .seafileAPIURL) ?? ""
        seafileAuthToken = try c.decodeIfPresent(String.self, forKey: .seafileAuthToken) ?? ""
        seafileRepoID = try c.decodeIfPresent(String.self, forKey: .seafileRepoID) ?? ""
        seafilePath = try c.decodeIfPresent(String.self, forKey: .seafilePath) ?? "/"
        pushbulletAPIKey = try c.decodeIfPresent(String.self, forKey: .pushbulletAPIKey) ?? ""
        oauthApps = try c.decodeIfPresent([String: OAuthAppCredentials].self, forKey: .oauthApps) ?? [:]
    }
}

extension UploadersConfig: KeychainBackedSettings {
    /// Every persisted secret in this file: access secrets, host passwords and
    /// API tokens. Non-secret identifiers (access-key IDs, usernames, hostnames,
    /// bucket names) stay in the JSON. Keys are stable — renaming one orphans
    /// the stored secret — so they are chosen to read clearly in the Keychain.
    public static let secretKeyPaths: [String: WritableKeyPath<UploadersConfig, String>] = [
        "AmazonS3.SecretAccessKey": \.amazonS3.secretAccessKey,
        "BitlyAccessToken": \.bitlyAccessToken,
        "PolrAPIKey": \.polrAPIKey,
        "YourlsSignature": \.yourlsSignature,
        "YourlsPassword": \.yourlsPassword,
        "Kutt.APIKey": \.kutt.apiKey,
        "Kutt.Password": \.kutt.password,
        "ZeroWidthShortenerToken": \.zeroWidthShortenerToken,
        "VgymeUserKey": \.vgymeUserKey,
        "SulAPIKey": \.sulAPIKey,
        "Lithiio.UserAPIKey": \.lithiio.userAPIKey,
        "PuushAPIKey": \.puushAPIKey,
        "Chevereto.APIKey": \.chevereto.apiKey,
        "StreamablePassword": \.streamablePassword,
        "B2ApplicationKey": \.b2ApplicationKey,
        "AzureStorageAccountAccessKey": \.azureStorageAccountAccessKey,
        "OwnCloudPassword": \.ownCloudPassword,
        "SeafileAuthToken": \.seafileAuthToken,
        "PushbulletAPIKey": \.pushbulletAPIKey
    ]

    public static func load() -> UploadersConfig { loadApplyingSecrets() }
    public func save() throws { try saveMigratingSecrets() }
}

/// Field names match the C# PomfUploader JSON shape.
public struct PomfUploaderSettings: Codable, Equatable {
    public var uploadURL = ""
    /// Prepended when the API returns a relative file name.
    public var resultURL = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case uploadURL = "UploadURL"
        case resultURL = "ResultURL"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uploadURL = try c.decodeIfPresent(String.self, forKey: .uploadURL) ?? ""
        resultURL = try c.decodeIfPresent(String.self, forKey: .resultURL) ?? ""
    }
}

/// Field names match the C# LobFileSettings JSON shape (LithiioSettings key).
public struct LithiioSettings: Codable, Equatable {
    public var userAPIKey = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case userAPIKey = "UserAPIKey"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userAPIKey = try c.decodeIfPresent(String.self, forKey: .userAPIKey) ?? ""
    }
}

/// Field names match the C# CheveretoUploader JSON shape.
public struct CheveretoSettings: Codable, Equatable {
    public var uploadURL = ""
    public var apiKey = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case uploadURL = "UploadURL"
        case apiKey = "APIKey"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uploadURL = try c.decodeIfPresent(String.self, forKey: .uploadURL) ?? ""
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }
}

/// Field names match the C# KuttSettings JSON shape.
public struct KuttSettings: Codable, Equatable {
    public var host = "https://kutt.it"
    public var apiKey = ""
    public var password = ""
    public var reuse = false
    public var domain = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case host = "Host"
        case apiKey = "APIKey"
        case password = "Password"
        case reuse = "Reuse"
        case domain = "Domain"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? "https://kutt.it"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        reuse = try c.decodeIfPresent(Bool.self, forKey: .reuse) ?? false
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
    }
}

/// Field names match the C# AmazonS3Settings JSON shape.
public struct AmazonS3Settings: Codable, Equatable {
    public var accessKeyID = ""
    public var secretAccessKey = ""
    public var region = "us-east-1"
    public var bucket = ""
    public var objectPrefix = "SwiftX/%y/%mo"
    /// Custom endpoint host for S3-compatible services (empty = AWS).
    public var endpoint = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case accessKeyID = "AccessKeyID"
        case secretAccessKey = "SecretAccessKey"
        case region = "Region"
        case bucket = "Bucket"
        case objectPrefix = "ObjectPrefix"
        case endpoint = "Endpoint"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessKeyID = try c.decodeIfPresent(String.self, forKey: .accessKeyID) ?? ""
        secretAccessKey = try c.decodeIfPresent(String.self, forKey: .secretAccessKey) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? "us-east-1"
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        objectPrefix = try c.decodeIfPresent(String.self, forKey: .objectPrefix) ?? "SwiftX/%y/%mo"
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
    }
}
