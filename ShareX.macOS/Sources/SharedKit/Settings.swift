// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// JSON settings engine. Key names are PascalCase to stay compatible with the
// Windows ShareX config files, so backups/presets can be imported later.
// Structs start with the fields Phase 0/1 need and grow per phase.

import Foundation

public enum SettingsPaths {
    /// Overridable for tests.
    public static var root: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ShareX", isDirectory: true)

    public static var defaultScreenshotsFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShareX", isDirectory: true)
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
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        return value
    }

    func save() throws {
        try FileManager.default.createDirectory(at: SettingsPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
    }
}

public struct ApplicationConfig: SettingsFile {
    public static let fileName = "ApplicationConfig.json"

    public var useCustomScreenshotsPath = false
    public var customScreenshotsPath = ""
    public var saveImageSubFolderPattern = "%y-%mo"
    /// C# TaskViewMode enum name: "ListView" or "ThumbnailView".
    public var taskViewMode = "ListView"

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
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useCustomScreenshotsPath = try c.decodeIfPresent(Bool.self, forKey: .useCustomScreenshotsPath) ?? false
        customScreenshotsPath = try c.decodeIfPresent(String.self, forKey: .customScreenshotsPath) ?? ""
        saveImageSubFolderPattern = try c.decodeIfPresent(String.self, forKey: .saveImageSubFolderPattern) ?? "%y-%mo"
        taskViewMode = try c.decodeIfPresent(String.self, forKey: .taskViewMode) ?? "ListView"
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
    public var screenRecordFPS = 30
    public var gifFPS = 15
    /// "H264" or "HEVC" (macOS-only key; C# keeps codec inside FFmpegOptions).
    public var screenRecordCodec = "H264"

    public init() {}

    enum CodingKeys: String, CodingKey {
        case nameFormatPattern = "NameFormatPattern"
        case nameFormatPatternActiveWindow = "NameFormatPatternActiveWindow"
        case afterCaptureJob = "AfterCaptureJob"
        case afterUploadJob = "AfterUploadJob"
        case imageDestination = "ImageDestination"
        case urlShortenerDestination = "URLShortenerDestination"
        case screenRecordFPS = "ScreenRecordFPS"
        case gifFPS = "GIFFPS"
        case screenRecordCodec = "ScreenRecordCodec"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameFormatPattern = try c.decodeIfPresent(String.self, forKey: .nameFormatPattern) ?? "%y-%mo-%d_%h-%mi-%s"
        nameFormatPatternActiveWindow = try c.decodeIfPresent(String.self, forKey: .nameFormatPatternActiveWindow) ?? "%pn_%y-%mo-%d_%h-%mi-%s"
        afterCaptureJob = try c.decodeIfPresent(AfterCaptureTasks.self, forKey: .afterCaptureJob) ?? [.copyImageToClipboard, .saveImageToFile]
        afterUploadJob = try c.decodeIfPresent(AfterUploadTasks.self, forKey: .afterUploadJob) ?? [.copyURLToClipboard]
        imageDestination = try c.decodeIfPresent(String.self, forKey: .imageDestination) ?? "CustomImageUploader"
        urlShortenerDestination = try c.decodeIfPresent(String.self, forKey: .urlShortenerDestination) ?? "ISGD"
        screenRecordFPS = try c.decodeIfPresent(Int.self, forKey: .screenRecordFPS) ?? 30
        gifFPS = try c.decodeIfPresent(Int.self, forKey: .gifFPS) ?? 15
        screenRecordCodec = try c.decodeIfPresent(String.self, forKey: .screenRecordCodec) ?? "H264"
    }
}

public struct HotkeySettings: SettingsFile {
    public static let fileName = "HotkeysConfig.json"

    // Populated in Phase 2 when the hotkey engine lands
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

    public init() {}

    enum CodingKeys: String, CodingKey {
        case activeCustomUploader = "ActiveCustomUploader"
        case amazonS3 = "AmazonS3Settings"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeCustomUploader = try c.decodeIfPresent(String.self, forKey: .activeCustomUploader) ?? ""
        amazonS3 = try c.decodeIfPresent(AmazonS3Settings.self, forKey: .amazonS3) ?? AmazonS3Settings()
    }
}

/// Field names match the C# AmazonS3Settings JSON shape.
public struct AmazonS3Settings: Codable, Equatable {
    public var accessKeyID = ""
    public var secretAccessKey = ""
    public var region = "us-east-1"
    public var bucket = ""
    public var objectPrefix = "ShareX/%y/%mo"
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
        objectPrefix = try c.decodeIfPresent(String.self, forKey: .objectPrefix) ?? "ShareX/%y/%mo"
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
    }
}
