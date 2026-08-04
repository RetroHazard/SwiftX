// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Native settings backup (the C# .sxb equivalent, as a plain zip): settings
// files, hotkeys and custom uploaders. Keychain-held secrets (API keys, OAuth
// tokens) never live in these JSON files, so a backup can be shared without
// leaking credentials - the price is re-entering them after a restore.
// History.db is deliberately excluded: the store holds it open, and history
// has its own import tools.

import Foundation

public enum SettingsBackupError: LocalizedError {
    case toolFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .toolFailed(let status): return L10n.t("backup.tool_failed", status)
        }
    }
}

public enum SettingsBackup {
    /// Known settings artifacts. Restore only touches these names, so a
    /// hostile zip cannot drop arbitrary files into Application Support.
    public static let entries = [
        "ApplicationConfig.json", "TaskSettings.json", "HotkeysConfig.json",
        "UploadersConfig.json", "ImageEffects.json", "CustomUploaders"
    ]

    public static func export(to zipURL: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for name in entries {
            let source = SettingsPaths.root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(name))
            }
        }
        try? FileManager.default.removeItem(at: zipURL)
        try ditto(["-c", "-k", "--sequesterRsrc", staging.path, zipURL.path])
    }

    /// Replaces the known settings artifacts with the archive's copies.
    /// Callers reload settings and re-register hotkeys afterwards.
    public static func restore(from zipURL: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try extract(zipURL, to: staging)
        try FileManager.default.createDirectory(at: SettingsPaths.root, withIntermediateDirectories: true)
        for name in entries {
            let source = staging.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = SettingsPaths.root.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    /// Unzips an archive into `directory` (created if needed). Used for both
    /// native backups and Windows ShareX .sxb files, which are plain zips too.
    public static func extract(_ zipURL: URL, to directory: URL) throws {
        try ditto(["-x", "-k", zipURL.path, directory.path])
    }

    /// True when an extracted backup came from Windows ShareX rather than
    /// SwiftX: its ApplicationConfig.json nests everything the Mac app splits
    /// into TaskSettings.json under a DefaultTaskSettings object.
    public static func isWindowsShareXBackup(extractedAt directory: URL) -> Bool {
        let config = directory.appendingPathComponent("ApplicationConfig.json")
        guard let data = try? Data(contentsOf: config),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        return object["DefaultTaskSettings"] != nil
    }

    private static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SettingsBackupError.toolFailed(process.terminationStatus)
        }
    }
}
