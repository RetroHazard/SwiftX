// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Imports Windows ShareX settings backups (.sxb). A .sxb is a plain zip of
// ApplicationConfig.json, HotkeysConfig.json, UploadersConfig.json and
// History.db. The Windows JSON nests task settings under
// ApplicationConfig.DefaultTaskSettings and stores hotkeys as C# Keys enum
// strings, so this maps field-by-field instead of decoding SwiftX's types
// directly. Values with no macOS equivalent (Windows paths, window positions,
// Windows-only features) are skipped; everything imported merges into the
// existing SwiftX settings rather than replacing them wholesale.

import Foundation
import SharedKit

public enum ShareXBackupImport {
    /// What an import touched, for the completion notification.
    public struct Summary {
        public var importedUploaders: [String] = []
        public var importedHotkeys = 0
        public var skippedHotkeys = 0
        public var appliedSettings = false
        public var appliedUploadersConfig = false
        /// Path of the backup's History.db inside the staging folder, when
        /// present. The caller imports it (HistoryKit) before staging is removed.
        public var historyDatabase: URL?
    }

    /// Applies an extracted Windows .sxb at `directory` onto the current
    /// settings. Caller extracts the zip first (SettingsBackup.extract) and
    /// reloads settings / re-registers hotkeys afterwards.
    public static func apply(extractedAt directory: URL) throws -> Summary {
        var summary = Summary()

        if let data = try? Data(contentsOf: directory.appendingPathComponent("ApplicationConfig.json")),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var config = ApplicationConfig.load()
            applicationConfig(fromWindows: json, onto: &config)
            try config.save()

            var task = TaskSettings.load()
            if let defaults = json["DefaultTaskSettings"] as? [String: Any] {
                taskSettings(fromWindows: defaults, onto: &task)
            }
            try task.save()
            summary.appliedSettings = true
        }

        if let data = try? Data(contentsOf: directory.appendingPathComponent("UploadersConfig.json")),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var config = UploadersConfig.load()
            uploadersConfig(fromWindows: json, onto: &config)

            // CustomUploadersList entries are full .sxcu payloads inline; write
            // each into the store and resolve the Windows selected indexes
            // (image/text/file) to the stored file names.
            let items = customUploaders(fromWindows: json)
            var fileNames: [String] = []
            for item in items {
                let base = item.displayName.isEmpty ? "Imported Uploader" : item.displayName
                if let name = try? CustomUploaderStore.create(named: base, from: item) {
                    fileNames.append(name)
                    summary.importedUploaders.append(name)
                } else {
                    fileNames.append("")
                }
            }
            func selected(_ key: String) -> String {
                guard let index = json[key] as? Int, fileNames.indices.contains(index) else { return "" }
                return fileNames[index]
            }
            let image = selected("CustomImageUploaderSelected")
            if !image.isEmpty { config.activeCustomUploader = image }
            let text = selected("CustomTextUploaderSelected")
            if !text.isEmpty, text != config.activeCustomUploader { config.activeTextCustomUploader = text }
            let file = selected("CustomFileUploaderSelected")
            if !file.isEmpty, file != config.activeCustomUploader { config.activeFileCustomUploader = file }

            try config.save()
            summary.appliedUploadersConfig = true
        }

        if let data = try? Data(contentsOf: directory.appendingPathComponent("HotkeysConfig.json")),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let (imported, skipped) = hotkeys(fromWindows: json)
            if !imported.isEmpty {
                var settings = HotkeySettings.load()
                // replace bindings for jobs the backup covers, keep the rest
                let importedTypes = Set(imported.map(\.taskType))
                settings.hotkeys.removeAll { importedTypes.contains($0.taskType) }
                settings.hotkeys.append(contentsOf: imported)
                try settings.save()
            }
            summary.importedHotkeys = imported.count
            summary.skippedHotkeys = skipped
        }

        let history = directory.appendingPathComponent("History.db")
        if FileManager.default.fileExists(atPath: history.path) {
            summary.historyDatabase = history
        }
        return summary
    }

    // MARK: - ApplicationConfig

    /// Copies the Windows ApplicationConfig keys that have a SwiftX equivalent.
    static func applicationConfig(fromWindows json: [String: Any], onto config: inout ApplicationConfig) {
        // Windows filesystem paths can never resolve on macOS, so the custom
        // screenshots folder only imports when it isn't a Windows-style path.
        if let use = json["UseCustomScreenshotsPath"] as? Bool,
           let path = json["CustomScreenshotsPath"] as? String,
           use, !path.isEmpty, !isWindowsPath(path) {
            config.useCustomScreenshotsPath = true
            config.customScreenshotsPath = path
        }
        string(json["SaveImageSubFolderPattern"]) { config.saveImageSubFolderPattern = $0 }
        string(json["TaskViewMode"]) { config.taskViewMode = $0 }
        bool(json["TrayIconProgressEnabled"]) { config.trayIconProgressEnabled = $0 }
        string(json["TrayLeftClickAction"]) { action in
            if action == "ToggleTrayMenu" || HotkeyType(rawValue: action) != nil {
                config.trayLeftClickAction = action
            }
        }
        bool(json["RecentTasksShowInTrayMenu"]) { config.recentTasksShowInTrayMenu = $0 }
        int(json["RecentTasksMaxCount"]) { config.recentTasksMaxCount = max(1, min(30, $0)) }
        int(json["UploadLimit"]) { config.uploadLimit = max(1, min(25, $0)) }
        int(json["MaxUploadFailRetry"]) { config.maxUploadFailRetry = max(0, min(10, $0)) }
        bool(json["DisableUpload"]) { config.disableUpload = $0 }
        bool(json["ShowMultiUploadWarning"]) { config.showMultiUploadWarning = $0 }
        // Windows stores a size threshold in MB; SwiftX keeps a fixed 100 MB
        // threshold behind a toggle, so any non-zero threshold maps to "on".
        int(json["ShowLargeFileSizeWarning"]) { config.showLargeFileSizeWarning = $0 > 0 }
        bool(json["DisableHotkeysOnFullscreen"]) { config.disableHotkeysOnFullscreen = $0 }
        int(json["HotkeyRepeatLimit"]) { config.hotkeyRepeatLimit = max(0, min(5000, $0)) }
        if let list = json["ActionsToolbarList"] as? [String] {
            let known = list.filter { HotkeyType(rawValue: $0) != nil }
            if !known.isEmpty { config.actionsToolbarList = known }
        }
        bool(json["ActionsToolbarLockPosition"]) { config.actionsToolbarLockPosition = $0 }
        bool(json["ActionsToolbarRunAtStartup"]) { config.actionsToolbarRunAtStartup = $0 }
        double(json["AutoCaptureRepeatTime"]) { config.autoCaptureRepeatTime = max(1, $0) }
        bool(json["AutoCaptureWaitUpload"]) { config.autoCaptureWaitUpload = $0 }
        if let presets = json["QuickTaskPresets"] as? [[String: Any]] {
            let decoded = presets.compactMap { object -> QuickTaskPreset? in
                guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
                return try? JSONDecoder().decode(QuickTaskPreset.self, from: data)
            }
            if !decoded.isEmpty { config.quickTaskPresets = decoded }
        }
    }

    // MARK: - TaskSettings (DefaultTaskSettings)

    /// Maps the Windows DefaultTaskSettings object (with its nested Image /
    /// Capture / Upload / General / Advanced sections) onto SwiftX's flat
    /// TaskSettings.
    static func taskSettings(fromWindows json: [String: Any], onto task: inout TaskSettings) {
        flags(json["AfterCaptureJob"]) { task.afterCaptureJob = AfterCaptureTasks(nameString: $0) }
        flags(json["AfterUploadJob"]) { task.afterUploadJob = AfterUploadTasks(nameString: $0) }
        string(json["ImageDestination"]) { task.imageDestination = $0 }
        string(json["TextDestination"]) { task.textDestination = $0 }
        string(json["FileDestination"]) { task.fileDestination = $0 }
        string(json["URLShortenerDestination"]) { task.urlShortenerDestination = $0 }
        string(json["URLSharingServiceDestination"]) { task.urlSharingServiceDestination = $0 }

        if let general = json["GeneralSettings"] as? [String: Any] {
            bool(general["PlaySoundAfterCapture"]) { task.playSoundAfterCapture = $0 }
            bool(general["PlaySoundAfterUpload"]) { task.playSoundAfterUpload = $0 }
            bool(general["ShowToastNotificationAfterTaskCompleted"]) {
                task.showToastNotificationAfterTaskCompleted = $0
            }
            bool(general["DisableNotificationsOnFullscreen"]) { task.disableNotificationsOnFullscreen = $0 }
        }

        if let image = json["ImageSettings"] as? [String: Any] {
            string(image["ImageFormat"]) { task.imageFormat = $0 }
            string(image["ImagePNGBitDepth"]) { task.imagePNGBitDepth = $0 }
            int(image["ImageJPEGQuality"]) { task.imageJPEGQuality = max(1, min(100, $0)) }
            string(image["ImageGIFQuality"]) { task.imageGIFQuality = $0 }
            bool(image["ImageAutoUseJPEG"]) { task.imageAutoUseJPEG = $0 }
            int(image["ImageAutoUseJPEGSize"]) { task.imageAutoUseJPEGSize = $0 }
            // old ShareX builds stored a bool here; only a real quality imports
            int(image["ImageAutoJPEGQuality"]) { task.imageAutoJPEGQuality = max(1, min(100, $0)) }
            string(image["FileExistAction"]) { task.fileExistAction = $0 }
            bool(image["ShowImageEffectsWindowAfterCapture"]) { task.showImageEffectsWindowAfterCapture = $0 }
            bool(image["ImageEffectOnlyRegionCapture"]) { task.imageEffectOnlyRegionCapture = $0 }
            int(image["ThumbnailWidth"]) { task.thumbnailWidth = $0 }
            int(image["ThumbnailHeight"]) { task.thumbnailHeight = $0 }
            string(image["ThumbnailName"]) { task.thumbnailName = $0 }
            bool(image["ThumbnailCheckSize"]) { task.thumbnailCheckSize = $0 }
        }

        if let capture = json["CaptureSettings"] as? [String: Any] {
            bool(capture["ShowCursor"]) { task.showCursor = $0 }
            double(capture["ScreenshotDelay"]) { task.screenshotDelay = max(0, $0) }
            string(capture["CaptureCustomWindow"]) { task.captureCustomWindow = $0 }
            if let ffmpeg = capture["FFmpegOptions"] as? [String: Any] {
                int(ffmpeg["FPS"]) { task.screenRecordFPS = max(1, min(120, $0)) }
                int(ffmpeg["GIFFPS"]) { task.gifFPS = max(1, min(60, $0)) }
            }
            bool(capture["ScreenRecordShowCursor"]) { task.screenRecordShowCursor = $0 }
            double(capture["ScreenRecordStartDelay"]) { task.screenRecordStartDelay = max(0, $0) }
            bool(capture["ScreenRecordFixedDuration"]) { task.screenRecordFixedDuration = $0 }
            double(capture["ScreenRecordDuration"]) { task.screenRecordDuration = max(0, $0) }
            bool(capture["ScreenRecordAskConfirmationOnAbort"]) { task.screenRecordAskConfirmationOnAbort = $0 }
            bool(capture["ScreenRecordTwoPassEncoding"]) { task.screenRecordTwoPassEncoding = $0 }
        }

        if let upload = json["UploadSettings"] as? [String: Any] {
            string(upload["NameFormatPattern"]) { task.nameFormatPattern = $0 }
            string(upload["NameFormatPatternActiveWindow"]) { task.nameFormatPatternActiveWindow = $0 }
            bool(upload["FileUploadUseNamePattern"]) { task.fileUploadUseNamePattern = $0 }
            bool(upload["FileUploadReplaceProblematicCharacters"]) {
                task.fileUploadReplaceProblematicCharacters = $0
            }
            bool(upload["URLRegexReplace"]) { task.urlRegexReplace = $0 }
            string(upload["URLRegexReplacePattern"]) { task.urlRegexReplacePattern = $0 }
            string(upload["URLRegexReplaceReplacement"]) { task.urlRegexReplaceReplacement = $0 }
            bool(upload["ClipboardUploadURLContents"]) { task.clipboardUploadURLContents = $0 }
            bool(upload["ClipboardUploadShortenURL"]) { task.clipboardUploadShortenURL = $0 }
            bool(upload["ClipboardUploadShareURL"]) { task.clipboardUploadShareURL = $0 }
            bool(upload["ClipboardUploadAutoIndexFolder"]) { task.clipboardUploadAutoIndexFolder = $0 }
            bool(upload["UseCustomTimeZone"]) { task.useCustomTimeZone = $0 }
            // C# serializes a full TimeZoneInfo; only its identifier maps here,
            // and Windows zone ids ("Tokyo Standard Time") won't all resolve.
            if let zone = upload["CustomTimeZone"] as? [String: Any],
               let id = zone["Id"] as? String, TimeZone(identifier: id) != nil {
                task.customTimeZoneIdentifier = id
            }
        }

        if let advanced = json["AdvancedSettings"] as? [String: Any] {
            bool(advanced["EarlyCopyURL"]) { task.earlyCopyURL = $0 }
            bool(advanced["AutoClearClipboard"]) { task.autoClearClipboard = $0 }
        }
    }

    // MARK: - UploadersConfig

    /// Copies the flat Windows UploadersConfig keys SwiftX understands.
    /// OAuth2 tokens (Imgur, Dropbox, …) are machine-bound on Windows and
    /// never import — those hosts need reconnecting through Settings.
    static func uploadersConfig(fromWindows json: [String: Any], onto config: inout UploadersConfig) {
        if let s3 = json["AmazonS3Settings"] as? [String: Any] {
            string(s3["AccessKeyID"]) { config.amazonS3.accessKeyID = $0 }
            string(s3["SecretAccessKey"]) { config.amazonS3.secretAccessKey = $0 }
            string(s3["Region"]) { config.amazonS3.region = $0 }
            string(s3["Bucket"]) { config.amazonS3.bucket = $0 }
            string(s3["ObjectPrefix"]) { config.amazonS3.objectPrefix = $0 }
            string(s3["Endpoint"]) { endpoint in
                // AWS regional endpoints are implied by Region on macOS; only
                // custom S3-compatible endpoints are worth carrying over.
                if !endpoint.lowercased().hasSuffix("amazonaws.com") {
                    config.amazonS3.endpoint = endpoint
                }
            }
        }
        if let chevereto = json["CheveretoUploader"] as? [String: Any] {
            string(chevereto["UploadURL"]) { config.chevereto.uploadURL = $0 }
            string(chevereto["APIKey"]) { config.chevereto.apiKey = $0 }
        }
        bool(json["CheveretoDirectURL"]) { config.cheveretoDirectURL = $0 }
        if let pomf = json["PomfUploader"] as? [String: Any] {
            string(pomf["UploadURL"]) { config.pomf.uploadURL = $0 }
            string(pomf["ResultURL"]) { config.pomf.resultURL = $0 }
        }
        if let lithiio = json["LithiioSettings"] as? [String: Any] {
            string(lithiio["UserAPIKey"]) { config.lithiio.userAPIKey = $0 }
        }
        if let kutt = json["KuttSettings"] as? [String: Any] {
            string(kutt["Host"]) { config.kutt.host = $0 }
            string(kutt["APIKey"]) { config.kutt.apiKey = $0 }
            string(kutt["Password"]) { config.kutt.password = $0 }
            bool(kutt["Reuse"]) { config.kutt.reuse = $0 }
            string(kutt["Domain"]) { config.kutt.domain = $0 }
        }
        if let pushbullet = json["PushbulletSettings"] as? [String: Any] {
            string(pushbullet["UserAPIKey"]) { config.pushbulletAPIKey = $0 }
        }
        string(json["VgymeUserKey"]) { config.vgymeUserKey = $0 }
        string(json["SulAPIKey"]) { config.sulAPIKey = $0 }
        string(json["PuushAPIKey"]) { config.puushAPIKey = $0 }
        string(json["StreamableUsername"]) { config.streamableUsername = $0 }
        string(json["StreamablePassword"]) { config.streamablePassword = $0 }
        string(json["B2ApplicationKeyId"]) { config.b2ApplicationKeyId = $0 }
        string(json["B2ApplicationKey"]) { config.b2ApplicationKey = $0 }
        string(json["B2BucketName"]) { config.b2BucketName = $0 }
        string(json["B2UploadPath"]) { config.b2UploadPath = $0 }
        bool(json["B2UseCustomUrl"]) { config.b2UseCustomUrl = $0 }
        string(json["B2CustomUrl"]) { config.b2CustomUrl = $0 }
        string(json["AzureStorageAccountName"]) { config.azureStorageAccountName = $0 }
        string(json["AzureStorageAccountAccessKey"]) { config.azureStorageAccountAccessKey = $0 }
        string(json["AzureStorageContainer"]) { config.azureStorageContainer = $0 }
        string(json["AzureStorageEnvironment"]) { config.azureStorageEnvironment = $0 }
        string(json["AzureStorageCustomDomain"]) { config.azureStorageCustomDomain = $0 }
        string(json["AzureStorageUploadPath"]) { config.azureStorageUploadPath = $0 }
        string(json["AzureStorageCacheControl"]) { config.azureStorageCacheControl = $0 }
        string(json["OwnCloudHost"]) { config.ownCloudHost = $0 }
        string(json["OwnCloudUsername"]) { config.ownCloudUsername = $0 }
        string(json["OwnCloudPassword"]) { config.ownCloudPassword = $0 }
        string(json["OwnCloudPath"]) { config.ownCloudPath = $0 }
        bool(json["OwnCloudCreateShare"]) { config.ownCloudCreateShare = $0 }
        string(json["SeafileAPIURL"]) { config.seafileAPIURL = $0 }
        string(json["SeafileAuthToken"]) { config.seafileAuthToken = $0 }
        string(json["SeafileRepoID"]) { config.seafileRepoID = $0 }
        string(json["SeafilePath"]) { config.seafilePath = $0 }
        string(json["BitlyDomain"]) { config.bitlyDomain = $0 }
        string(json["PolrAPIHostname"]) { config.polrAPIHostname = $0 }
        string(json["PolrAPIKey"]) { config.polrAPIKey = $0 }
        bool(json["PolrIsSecret"]) { config.polrIsSecret = $0 }
        bool(json["PolrUseAPIv1"]) { config.polrUseAPIv1 = $0 }
        string(json["YourlsAPIURL"]) { config.yourlsAPIURL = $0 }
        string(json["YourlsSignature"]) { config.yourlsSignature = $0 }
        string(json["YourlsUsername"]) { config.yourlsUsername = $0 }
        string(json["YourlsPassword"]) { config.yourlsPassword = $0 }
        string(json["ZeroWidthShortenerURL"]) { config.zeroWidthShortenerURL = $0 }
        string(json["ZeroWidthShortenerToken"]) { config.zeroWidthShortenerToken = $0 }
    }

    /// Decodes CustomUploadersList entries — each is a full .sxcu payload
    /// inline — applying the same legacy-syntax migration as file imports.
    static func customUploaders(fromWindows json: [String: Any]) -> [CustomUploaderItem] {
        guard let list = json["CustomUploadersList"] as? [[String: Any]] else { return [] }
        return list.compactMap { object in
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  var item = try? JSONDecoder().decode(CustomUploaderItem.self, from: data) else { return nil }
            item.migrateLegacySyntaxIfNeeded()
            return item
        }
    }

    // MARK: - Hotkeys

    /// Maps the Windows hotkey list. HotkeyInfo.Hotkey is a C# Keys flags
    /// string ("D4, Shift, Control"): first name is the key, the rest are
    /// modifiers, plus a separate Win flag (→ ⌘). Returns the mapped configs
    /// and how many bindings had no macOS equivalent (e.g. PrintScreen).
    static func hotkeys(fromWindows json: [String: Any]) -> (imported: [HotkeyConfig], skipped: Int) {
        guard let list = json["Hotkeys"] as? [[String: Any]] else { return ([], 0) }
        var imported: [HotkeyConfig] = []
        var skipped = 0
        for entry in list {
            guard let job = (entry["TaskSettings"] as? [String: Any])?["Job"] as? String,
                  job != "None", HotkeyType(rawValue: job) != nil else { continue }
            guard let hotkey = (entry["HotkeyInfo"] as? [String: Any])?["Hotkey"] as? String,
                  let combo = keyCombo(fromWindowsKeys: hotkey,
                                       win: (entry["HotkeyInfo"] as? [String: Any])?["Win"] as? Bool ?? false)
            else {
                skipped += 1
                continue
            }
            imported.append(HotkeyConfig(taskType: job, key: combo.key, modifiers: combo.modifiers))
        }
        return (imported, skipped)
    }

    /// "D4, Shift, Control" → KeyCombo(key: "4", modifiers: [shift, control]).
    /// Returns nil when the key has no macOS equivalent.
    static func keyCombo(fromWindowsKeys string: String, win: Bool) -> KeyCombo? {
        var key: String?
        var modifiers: [String] = []
        for part in string.components(separatedBy: ",") {
            let name = part.trimmingCharacters(in: .whitespaces)
            switch name {
            case "", "None": continue
            case "Control", "ControlKey", "LControlKey", "RControlKey": modifiers.append("control")
            case "Shift", "ShiftKey", "LShiftKey", "RShiftKey": modifiers.append("shift")
            case "Alt", "Menu", "LMenu", "RMenu": modifiers.append("option")
            case "LWin", "RWin": modifiers.append("command")
            default:
                guard key == nil, let mapped = macKeyName(forWindowsKey: name) else { return nil }
                key = mapped
            }
        }
        if win, !modifiers.contains("command") { modifiers.append("command") }
        guard let key else { return nil }
        // a bare unmodified key would swallow normal typing; C# allows it, but
        // only function keys are safe to carry over unmodified
        if modifiers.isEmpty, !key.hasPrefix("f") { return nil }
        return KeyCombo(key: key, modifiers: modifiers)
    }

    /// C# System.Windows.Forms.Keys enum name → SwiftX key name (Carbon table
    /// in KeyCombo). Nil = no macOS equivalent (PrintScreen, media keys, …).
    static func macKeyName(forWindowsKey name: String) -> String? {
        if name.count == 1, let letter = name.first, letter.isLetter, letter.isUppercase {
            return name.lowercased()
        }
        if name.hasPrefix("D"), name.count == 2, let digit = name.last, digit.isNumber {
            return String(digit)
        }
        if name.hasPrefix("NumPad"), let digit = name.last, digit.isNumber {
            return String(digit) // main-row digits; SwiftX has no numpad table
        }
        if name.hasPrefix("F"), let number = Int(name.dropFirst()), (1...12).contains(number) {
            return name.lowercased()
        }
        switch name {
        case "Space": return "space"
        case "Return", "Enter": return "return"
        case "Escape": return "escape"
        case "Tab": return "tab"
        case "Back": return "delete"
        case "Delete": return "forwarddelete"
        case "Home": return "home"
        case "End": return "end"
        case "PageUp", "Prior": return "pageup"
        case "PageDown", "Next": return "pagedown"
        case "Left": return "left"
        case "Right": return "right"
        case "Up": return "up"
        case "Down": return "down"
        case "Oemtilde": return "`"
        case "OemMinus": return "-"
        case "Oemplus": return "="
        case "OemOpenBrackets": return "["
        case "Oem6", "OemCloseBrackets": return "]"
        case "Oem1", "OemSemicolon": return ";"
        case "Oem7", "OemQuotes": return "'"
        case "Oemcomma": return ","
        case "OemPeriod": return "."
        case "OemQuestion": return "/"
        case "Oem5", "OemPipe", "OemBackslash": return "\\"
        default: return nil
        }
    }

    // MARK: - JSON helpers (Windows JSON is full of nulls)

    private static func string(_ value: Any?, _ apply: (String) -> Void) {
        if let string = value as? String, !string.isEmpty { apply(string) }
    }

    /// JSON true/false parses as a CFBoolean-backed NSNumber; plain numbers do
    /// not. `as? Bool` / `is Bool` can't tell 0/1 from false/true, so the type
    /// check goes through CoreFoundation.
    private static func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func bool(_ value: Any?, _ apply: (Bool) -> Void) {
        if isBoolean(value), let bool = value as? Bool { apply(bool) }
    }

    private static func int(_ value: Any?, _ apply: (Int) -> Void) {
        // reject genuine booleans so legacy bool-typed fields
        // (e.g. old ImageAutoJPEGQuality) don't import as 0/1
        if let number = value as? NSNumber, !isBoolean(value) { apply(number.intValue) }
    }

    private static func double(_ value: Any?, _ apply: (Double) -> Void) {
        if let number = value as? NSNumber, !isBoolean(value) { apply(number.doubleValue) }
    }

    private static func flags(_ value: Any?, _ apply: (String) -> Void) {
        if let string = value as? String { apply(string) }
    }

    static func isWindowsPath(_ path: String) -> Bool {
        path.contains(":\\") || path.contains("\\\\") || path.hasPrefix("\\")
    }
}
