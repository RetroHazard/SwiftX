// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// JSON settings engine. Key names are PascalCase to stay compatible with the
// Windows ShareX config files, so backups/presets can be imported later.
// Structs start with the fields Phase 0/1 need and grow per phase.

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
    /// One automatic retry after a failed upload (C# ApplicationSettings key).
    public var retryUpload = true
    /// AI image analysis (macOS-only keys; C# nests these per provider in
    /// AIOptions - one OpenAI-compatible endpoint covers OpenAI, OpenRouter
    /// and Gemini's compatibility API here).
    public var aiBaseURL = "https://api.openai.com/v1"
    public var aiAPIKey = ""
    public var aiModel = "gpt-5-mini"
    public var aiPrompt = "What is in this image?"

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
    public var screenRecordFPS = 30
    public var gifFPS = 15
    /// "H264" or "HEVC" (macOS-only key; C# keeps codec inside FFmpegOptions).
    public var screenRecordCodec = "H264"
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
    /// Captures larger than ImageAutoUseJPEGSize save as JPEG regardless of format.
    public var imageAutoUseJPEG = true
    public var imageAutoUseJPEGSize = 2048
    public var thumbnailWidth = 200
    public var thumbnailHeight = 0
    /// Appended to the file name (before the extension).
    public var thumbnailName = "-thumbnail"
    /// Only save the thumbnail when the image is larger than the thumbnail box.
    public var thumbnailCheckSize = false

    /// Actions: external programs run on the captured file (C# ExternalPrograms).
    public var externalPrograms: [ExternalProgramSettings] = []

    public var playSoundAfterCapture = true
    public var playSoundAfterUpload = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case nameFormatPattern = "NameFormatPattern"
        case nameFormatPatternActiveWindow = "NameFormatPatternActiveWindow"
        case afterCaptureJob = "AfterCaptureJob"
        case afterUploadJob = "AfterUploadJob"
        case imageDestination = "ImageDestination"
        case urlShortenerDestination = "URLShortenerDestination"
        case urlSharingServiceDestination = "URLSharingServiceDestination"
        case screenRecordFPS = "ScreenRecordFPS"
        case gifFPS = "GIFFPS"
        case screenRecordCodec = "ScreenRecordCodec"
        case screenRecordSystemAudio = "ScreenRecordSystemAudio"
        case screenRecordMicrophone = "ScreenRecordMicrophone"
        case screenRecordCustomFFmpegArgs = "ScreenRecordCustomFFmpegArgs"
        case imageFormat = "ImageFormat"
        case imageJPEGQuality = "ImageJPEGQuality"
        case imageAutoUseJPEG = "ImageAutoUseJPEG"
        case imageAutoUseJPEGSize = "ImageAutoUseJPEGSize"
        case thumbnailWidth = "ThumbnailWidth"
        case thumbnailHeight = "ThumbnailHeight"
        case thumbnailName = "ThumbnailName"
        case thumbnailCheckSize = "ThumbnailCheckSize"
        case externalPrograms = "ExternalPrograms"
        case playSoundAfterCapture = "PlaySoundAfterCapture"
        case playSoundAfterUpload = "PlaySoundAfterUpload"
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
        screenRecordFPS = try c.decodeIfPresent(Int.self, forKey: .screenRecordFPS) ?? 30
        gifFPS = try c.decodeIfPresent(Int.self, forKey: .gifFPS) ?? 15
        screenRecordCodec = try c.decodeIfPresent(String.self, forKey: .screenRecordCodec) ?? "H264"
        screenRecordSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .screenRecordSystemAudio) ?? false
        screenRecordMicrophone = try c.decodeIfPresent(Bool.self, forKey: .screenRecordMicrophone) ?? false
        screenRecordCustomFFmpegArgs = try c.decodeIfPresent(String.self, forKey: .screenRecordCustomFFmpegArgs) ?? ""
        imageFormat = try c.decodeIfPresent(String.self, forKey: .imageFormat) ?? "PNG"
        imageJPEGQuality = try c.decodeIfPresent(Int.self, forKey: .imageJPEGQuality) ?? 90
        imageAutoUseJPEG = try c.decodeIfPresent(Bool.self, forKey: .imageAutoUseJPEG) ?? true
        imageAutoUseJPEGSize = try c.decodeIfPresent(Int.self, forKey: .imageAutoUseJPEGSize) ?? 2048
        thumbnailWidth = try c.decodeIfPresent(Int.self, forKey: .thumbnailWidth) ?? 200
        thumbnailHeight = try c.decodeIfPresent(Int.self, forKey: .thumbnailHeight) ?? 0
        thumbnailName = try c.decodeIfPresent(String.self, forKey: .thumbnailName) ?? "-thumbnail"
        thumbnailCheckSize = try c.decodeIfPresent(Bool.self, forKey: .thumbnailCheckSize) ?? false
        externalPrograms = try c.decodeIfPresent([ExternalProgramSettings].self, forKey: .externalPrograms) ?? []
        playSoundAfterCapture = try c.decodeIfPresent(Bool.self, forKey: .playSoundAfterCapture) ?? true
        playSoundAfterUpload = try c.decodeIfPresent(Bool.self, forKey: .playSoundAfterUpload) ?? true
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
    }
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
