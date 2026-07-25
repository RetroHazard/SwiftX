// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Hotkey vocabulary and key-combo model. HotkeyType raw values match the C#
// HotkeyType enum names so settings files and CLI verbs stay compatible.

import Foundation

/// Every action SwiftX can bind to a hotkey (or invoke from the CLI).
/// Raw values match C# HotkeyType names so Windows configs import cleanly.
public enum HotkeyType: String, Codable, CaseIterable {
    case none = "None"
    // Upload
    case fileUpload = "FileUpload"
    case folderUpload = "FolderUpload"
    case clipboardUpload = "ClipboardUpload"
    case clipboardUploadWithContentViewer = "ClipboardUploadWithContentViewer"
    case uploadText = "UploadText"
    case uploadURL = "UploadURL"
    case dragDropUpload = "DragDropUpload"
    case shortenURL = "ShortenURL"
    case stopUploads = "StopUploads"
    // Screen capture
    case printScreen = "PrintScreen"
    case activeWindow = "ActiveWindow"
    case customWindow = "CustomWindow"
    case activeMonitor = "ActiveMonitor"
    case rectangleRegion = "RectangleRegion"
    case rectangleLight = "RectangleLight"
    case rectangleTransparent = "RectangleTransparent"
    case customRegion = "CustomRegion"
    case lastRegion = "LastRegion"
    case scrollingCapture = "ScrollingCapture"
    case autoCapture = "AutoCapture"
    case startAutoCapture = "StartAutoCapture"
    case stopAutoCapture = "StopAutoCapture"
    // Screen record
    case screenRecorder = "ScreenRecorder"
    case screenRecorderActiveWindow = "ScreenRecorderActiveWindow"
    case screenRecorderCustomRegion = "ScreenRecorderCustomRegion"
    case startScreenRecorder = "StartScreenRecorder"
    case screenRecorderGIF = "ScreenRecorderGIF"
    case screenRecorderGIFActiveWindow = "ScreenRecorderGIFActiveWindow"
    case screenRecorderGIFCustomRegion = "ScreenRecorderGIFCustomRegion"
    case startScreenRecorderGIF = "StartScreenRecorderGIF"
    case stopScreenRecording = "StopScreenRecording"
    case pauseScreenRecording = "PauseScreenRecording"
    case abortScreenRecording = "AbortScreenRecording"
    // Tools
    case colorPicker = "ColorPicker"
    case screenColorPicker = "ScreenColorPicker"
    case ruler = "Ruler"
    case pinToScreen = "PinToScreen"
    case pinToScreenFromScreen = "PinToScreenFromScreen"
    case pinToScreenFromClipboard = "PinToScreenFromClipboard"
    case pinToScreenFromFile = "PinToScreenFromFile"
    case pinToScreenCloseAll = "PinToScreenCloseAll"
    case imageEditor = "ImageEditor"
    case imageBeautifier = "ImageBeautifier"
    case imageEffects = "ImageEffects"
    case imageViewer = "ImageViewer"
    // upstream v21 additions
    case backgroundRemover = "BackgroundRemover"
    case imageComparer = "ImageComparer"
    case imageCombiner = "ImageCombiner"
    case imageSplitter = "ImageSplitter"
    case imageThumbnailer = "ImageThumbnailer"
    case videoConverter = "VideoConverter"
    case videoThumbnailer = "VideoThumbnailer"
    case analyzeImage = "AnalyzeImage"
    case ocr = "OCR"
    case qrCode = "QRCode"
    case qrCodeDecodeFromScreen = "QRCodeDecodeFromScreen"
    case qrCodeScanRegion = "QRCodeScanRegion"
    case hashCheck = "HashCheck"
    case metadata = "Metadata"
    case stripMetadata = "StripMetadata"
    case indexFolder = "IndexFolder"
    case clipboardViewer = "ClipboardViewer"
    case inspectWindow = "InspectWindow"
    case monitorTest = "MonitorTest"
    // Other
    case disableHotkeys = "DisableHotkeys"
    case openMainWindow = "OpenMainWindow"
    case openScreenshotsFolder = "OpenScreenshotsFolder"
    case openHistory = "OpenHistory"
    case openImageHistory = "OpenImageHistory"
    case toggleActionsToolbar = "ToggleActionsToolbar"
    case toggleTrayMenu = "ToggleTrayMenu"
    case exitShareX = "ExitShareX"
    // Windows-only in C# (BorderlessWindow, ActiveWindowBorderless, ActiveWindowTopMost,
    // DNSChanger) are intentionally absent - see PARITY.md
}

/// A keyboard shortcut: key name + modifier names, serializable and Carbon-convertible.
public struct KeyCombo: Codable, Equatable {
    public var key: String // "4", "a", "f12", "space", ...
    public var modifiers: [String] // "control", "option", "shift", "command"

    public init(key: String, modifiers: [String]) {
        self.key = key
        self.modifiers = modifiers
    }

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case modifiers = "Modifiers"
    }

    /// Carbon virtual key code (kVK_ANSI_*), nil for unknown key names.
    public var carbonKeyCode: UInt32? {
        Self.keyCodes[key.lowercased()]
    }

    /// Inverse lookup for the hotkey recorder (NSEvent.keyCode uses the same codes).
    public static func keyName(forCarbonKeyCode code: UInt32) -> String? {
        keyCodes.first { $0.value == code }?.key
    }

    /// Carbon modifier mask (cmdKey/shiftKey/optionKey/controlKey).
    public var carbonModifiers: UInt32 {
        modifiers.reduce(0) { mask, name in
            switch name.lowercased() {
            case "command", "cmd": return mask | 0x0100
            case "shift": return mask | 0x0200
            case "option", "alt": return mask | 0x0800
            case "control", "ctrl": return mask | 0x1000
            default: return mask
            }
        }
    }

    /// macOS-conventional display, e.g. "⌃⇧4".
    public var displayString: String {
        var result = ""
        let lowered = modifiers.map { $0.lowercased() }
        if lowered.contains("control") || lowered.contains("ctrl") { result += "⌃" }
        if lowered.contains("option") || lowered.contains("alt") { result += "⌥" }
        if lowered.contains("shift") { result += "⇧" }
        if lowered.contains("command") || lowered.contains("cmd") { result += "⌘" }
        result += Self.displayNames[key.lowercased()] ?? key.uppercased()
        return result
    }

    private static let displayNames: [String: String] = [
        "space": "Space", "escape": "⎋", "return": "↩", "tab": "⇥", "delete": "⌫",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟"
    ]

    // Carbon ANSI virtual key codes (US layout positions)
    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "=": 24, "-": 27, "]": 30, "[": 33, "'": 39, ";": 41, "\\": 42, ",": 43, "/": 44, ".": 47,
        "`": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]
}
