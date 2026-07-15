// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation

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
        let subfolderParser = NameParser(.filePath)
        subfolderParser.date = date
        var folder = config.screenshotsFolder
        let subfolder = subfolderParser.parse(config.saveImageSubFolderPattern)
        if !subfolder.isEmpty {
            folder.appendPathComponent(subfolder, isDirectory: true)
        }

        let nameParser = NameParser(.fileName)
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

        var candidate = folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name)_\(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
