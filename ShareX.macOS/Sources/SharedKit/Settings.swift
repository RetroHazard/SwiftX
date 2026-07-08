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
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useCustomScreenshotsPath = try c.decodeIfPresent(Bool.self, forKey: .useCustomScreenshotsPath) ?? false
        customScreenshotsPath = try c.decodeIfPresent(String.self, forKey: .customScreenshotsPath) ?? ""
        saveImageSubFolderPattern = try c.decodeIfPresent(String.self, forKey: .saveImageSubFolderPattern) ?? "%y-%mo"
    }
}

public struct TaskSettings: SettingsFile {
    public static let fileName = "TaskSettings.json"

    public var nameFormatPattern = "%y-%mo-%d_%h-%mi-%s"
    public var nameFormatPatternActiveWindow = "%pn_%y-%mo-%d_%h-%mi-%s"
    public var afterCaptureJob: AfterCaptureTasks = [.copyImageToClipboard, .saveImageToFile]
    public var afterUploadJob: AfterUploadTasks = [.copyURLToClipboard]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case nameFormatPattern = "NameFormatPattern"
        case nameFormatPatternActiveWindow = "NameFormatPatternActiveWindow"
        case afterCaptureJob = "AfterCaptureJob"
        case afterUploadJob = "AfterUploadJob"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameFormatPattern = try c.decodeIfPresent(String.self, forKey: .nameFormatPattern) ?? "%y-%mo-%d_%h-%mi-%s"
        nameFormatPatternActiveWindow = try c.decodeIfPresent(String.self, forKey: .nameFormatPatternActiveWindow) ?? "%pn_%y-%mo-%d_%h-%mi-%s"
        afterCaptureJob = try c.decodeIfPresent(AfterCaptureTasks.self, forKey: .afterCaptureJob) ?? [.copyImageToClipboard, .saveImageToFile]
        afterUploadJob = try c.decodeIfPresent(AfterUploadTasks.self, forKey: .afterUploadJob) ?? [.copyURLToClipboard]
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

    // Populated in Phase 3 when the upload engine lands
    public init() {}
    public init(from decoder: Decoder) throws {}
    public func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: CodingKeys.self)
    }

    enum CodingKeys: CodingKey {}
}
