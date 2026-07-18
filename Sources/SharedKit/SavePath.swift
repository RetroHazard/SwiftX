// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation

/// What to do when the destination file already exists. Raw values match the
/// C# FileExistAction enum names stored in TaskSettings.json.
public enum FileExistAction: String, CaseIterable, Sendable {
    case ask = "Ask"
    case overwrite = "Overwrite"
    case uniqueName = "UniqueName"
    case cancel = "Cancel"
}

public enum SavePath {
    /// Builds the destination file URL for a screenshot:
    /// screenshots folder / parsed subfolder pattern / parsed filename pattern + extension.
    /// Appends _1, _2, ... if the file already exists.
    public static func screenshotURL(
        config: ApplicationConfig,
        task: TaskSettings,
        windowTitle: String? = nil,
        processName: String? = nil,
        width: Int = 0,
        height: Int = 0,
        fileExtension: String = "png",
        date: Date? = nil
    ) -> URL {
        uniqueURL(screenshotBaseURL(
            config: config, task: task, windowTitle: windowTitle, processName: processName,
            width: width, height: height, fileExtension: fileExtension, date: date
        ))
    }

    /// Like `screenshotURL` but without collision handling: returns the URL
    /// the name patterns produce, existing file or not. Callers implementing
    /// FileExistAction resolve collisions themselves (`uniqueURL`, overwrite,
    /// cancel, or an Ask dialog).
    public static func screenshotBaseURL(
        config: ApplicationConfig,
        task: TaskSettings,
        windowTitle: String? = nil,
        processName: String? = nil,
        width: Int = 0,
        height: Int = 0,
        fileExtension: String = "png",
        date: Date? = nil
    ) -> URL {
        let subfolderParser = NameParser.forTask(.filePath, settings: task)
        subfolderParser.date = date
        var folder = config.screenshotsFolder
        let subfolder = subfolderParser.parse(config.saveImageSubFolderPattern)
        if !subfolder.isEmpty {
            folder.appendPathComponent(subfolder, isDirectory: true)
        }

        let nameParser = NameParser.forTask(.fileName, settings: task)
        nameParser.date = date
        nameParser.windowText = windowTitle
        nameParser.processName = processName
        nameParser.imageWidth = width
        nameParser.imageHeight = height
        let pattern = processName != nil ? task.nameFormatPatternActiveWindow : task.nameFormatPattern
        var name = nameParser.parse(pattern)
        if name.isEmpty {
            name = "SwiftX"
        }

        return folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
    }

    /// Appends _1, _2, ... to the file name until it doesn't collide.
    public static func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        var counter = 1
        var candidate = url
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name)_\(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }

    /// Non-interactive part of FileExistAction: returns the URL to write to,
    /// or nil to skip the save. `.ask` must be resolved to one of the other
    /// actions by the caller (it needs UI) before calling this.
    public static func resolvedURL(_ url: URL, onExisting action: FileExistAction) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        switch action {
        case .overwrite: return url
        case .cancel: return nil
        case .uniqueName, .ask: return uniqueURL(url)
        }
    }
}
