// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// After-capture / after-upload task flags. Bit values and names mirror
// ShareX/Enums.cs exactly; JSON encodes as C#-style comma-separated names
// ("CopyImageToClipboard, SaveImageToFile") with an integer fallback.

import Foundation

public protocol NamedOptionSet: OptionSet, Codable, Sendable where RawValue == Int, Element == Self {
    static var flagNames: [(Self, String)] { get }
}

public extension NamedOptionSet {
    var nameString: String {
        let names = Self.flagNames.filter { contains($0.0) }.map(\.1)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    init(nameString: String) {
        var result = Self()
        for name in nameString.components(separatedBy: ",") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let flag = Self.flagNames.first(where: { $0.1 == trimmed }) {
                result.insert(flag.0)
            }
            // unknown names ignored: forward/Windows compatibility
        }
        self = result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self.init(nameString: string)
        } else if let raw = try? container.decode(Int.self) {
            self.init(rawValue: raw)
        } else {
            self.init()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(nameString)
    }
}

/// "SaveImageToFile" -> "Save image to file"; acronym runs stay upper ("DoOCR" -> "Do OCR").
/// Approximates the C# [Description] strings without a hand-written table.
public func taskFlagTitle(_ pascal: String) -> String {
    var words: [String] = []
    var current = ""
    let chars = Array(pascal)
    for (i, ch) in chars.enumerated() {
        if ch.isUppercase && !current.isEmpty {
            let prevIsLower = chars[i - 1].isLowercase
            let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
            if prevIsLower || (nextIsLower && current.count > 1 && current == current.uppercased()) {
                words.append(current)
                current = ""
            }
        }
        current.append(ch)
    }
    if !current.isEmpty { words.append(current) }
    return words.enumerated().map { i, word in
        if word == word.uppercased() && word.count > 1 { return word } // acronym
        return i == 0 ? word : word.lowercased()
    }.joined(separator: " ")
}

public extension NamedOptionSet {
    /// Human-readable flag list ("Save image to file, Upload image to host").
    var friendlyString: String {
        Self.flagNames.filter { contains($0.0) }.map { taskFlagTitle($0.1) }.joined(separator: ", ")
    }
}

public struct AfterCaptureTasks: NamedOptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let showQuickTaskMenu = AfterCaptureTasks(rawValue: 1)
    public static let showAfterCaptureWindow = AfterCaptureTasks(rawValue: 1 << 1)
    public static let beautifyImage = AfterCaptureTasks(rawValue: 1 << 2)
    public static let addImageEffects = AfterCaptureTasks(rawValue: 1 << 3)
    public static let annotateImage = AfterCaptureTasks(rawValue: 1 << 4)
    public static let copyImageToClipboard = AfterCaptureTasks(rawValue: 1 << 5)
    public static let pinToScreen = AfterCaptureTasks(rawValue: 1 << 6)
    public static let sendImageToPrinter = AfterCaptureTasks(rawValue: 1 << 7)
    public static let saveImageToFile = AfterCaptureTasks(rawValue: 1 << 8)
    public static let saveImageToFileWithDialog = AfterCaptureTasks(rawValue: 1 << 9)
    public static let saveThumbnailImageToFile = AfterCaptureTasks(rawValue: 1 << 10)
    public static let performActions = AfterCaptureTasks(rawValue: 1 << 11)
    public static let copyFileToClipboard = AfterCaptureTasks(rawValue: 1 << 12)
    public static let copyFilePathToClipboard = AfterCaptureTasks(rawValue: 1 << 13)
    public static let copyFolderPathToClipboard = AfterCaptureTasks(rawValue: 1 << 14)
    public static let showInExplorer = AfterCaptureTasks(rawValue: 1 << 15)
    public static let analyzeImage = AfterCaptureTasks(rawValue: 1 << 16)
    public static let scanQRCode = AfterCaptureTasks(rawValue: 1 << 17)
    public static let doOCR = AfterCaptureTasks(rawValue: 1 << 18)
    public static let showBeforeUploadWindow = AfterCaptureTasks(rawValue: 1 << 19)
    public static let uploadImageToHost = AfterCaptureTasks(rawValue: 1 << 20)
    public static let deleteFile = AfterCaptureTasks(rawValue: 1 << 21)

    public static let flagNames: [(AfterCaptureTasks, String)] = [
        (.showQuickTaskMenu, "ShowQuickTaskMenu"),
        (.showAfterCaptureWindow, "ShowAfterCaptureWindow"),
        (.beautifyImage, "BeautifyImage"),
        (.addImageEffects, "AddImageEffects"),
        (.annotateImage, "AnnotateImage"),
        (.copyImageToClipboard, "CopyImageToClipboard"),
        (.pinToScreen, "PinToScreen"),
        (.sendImageToPrinter, "SendImageToPrinter"),
        (.saveImageToFile, "SaveImageToFile"),
        (.saveImageToFileWithDialog, "SaveImageToFileWithDialog"),
        (.saveThumbnailImageToFile, "SaveThumbnailImageToFile"),
        (.performActions, "PerformActions"),
        (.copyFileToClipboard, "CopyFileToClipboard"),
        (.copyFilePathToClipboard, "CopyFilePathToClipboard"),
        (.copyFolderPathToClipboard, "CopyFolderPathToClipboard"),
        (.showInExplorer, "ShowInExplorer"),
        (.analyzeImage, "AnalyzeImage"),
        (.scanQRCode, "ScanQRCode"),
        (.doOCR, "DoOCR"),
        (.showBeforeUploadWindow, "ShowBeforeUploadWindow"),
        (.uploadImageToHost, "UploadImageToHost"),
        (.deleteFile, "DeleteFile")
    ]
}

public struct AfterUploadTasks: NamedOptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let showAfterUploadWindow = AfterUploadTasks(rawValue: 1)
    public static let useURLShortener = AfterUploadTasks(rawValue: 1 << 1)
    public static let shareURL = AfterUploadTasks(rawValue: 1 << 2)
    public static let copyURLToClipboard = AfterUploadTasks(rawValue: 1 << 3)
    public static let openURL = AfterUploadTasks(rawValue: 1 << 4)
    public static let showQRCode = AfterUploadTasks(rawValue: 1 << 5)

    public static let flagNames: [(AfterUploadTasks, String)] = [
        (.showAfterUploadWindow, "ShowAfterUploadWindow"),
        (.useURLShortener, "UseURLShortener"),
        (.shareURL, "ShareURL"),
        (.copyURLToClipboard, "CopyURLToClipboard"),
        (.openURL, "OpenURL"),
        (.showQRCode, "ShowQRCode")
    ]
}
