// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Pure URL post-processing steps from the C# after-upload pipeline
// (TaskSettingsUpload / TaskSettingsAdvanced). Kept UI-free so they are
// directly testable; UploadCoordinator orchestrates the order.

import Foundation

public enum ResultURL {
    /// C# $result templates (ClipboardContentFormat, OpenURLFormat,
    /// BalloonTipContentFormat): "![]($result)" -> "![](https://...)".
    /// An empty template passes the result through unchanged.
    public static func format(_ template: String, result: String) -> String {
        template.isEmpty ? result : template.replacingOccurrences(of: "$result", with: result)
    }

    /// C# URLRegexReplace. Invalid patterns leave the URL untouched (C# would
    /// throw the task into error; a bad user regex shouldn't eat the upload).
    public static func regexReplaced(_ url: String, pattern: String, replacement: String) -> String {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else { return url }
        let range = NSRange(url.startIndex..., in: url)
        return regex.stringByReplacingMatches(in: url, range: range, withTemplate: replacement)
    }

    /// C# ResultForceHTTPS: rewrites the scheme only, never other "http" text.
    public static func forcedHTTPS(_ url: String) -> String {
        guard url.lowercased().hasPrefix("http://") else { return url }
        return "https://" + url.dropFirst("http://".count)
    }

    /// C# FileUploadReplaceProblematicCharacters: spaces become underscores;
    /// anything outside [A-Za-z0-9._-] is dropped. The extension separator
    /// survives because '.' is kept.
    public static func problematicCharactersReplaced(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let underscored = name.replacingOccurrences(of: " ", with: "_")
        return String(underscored.unicodeScalars.filter { allowed.contains($0) })
    }
}

public extension NameParser {
    /// Parser honoring the task's UseCustomTimeZone setting (C# wires
    /// TaskSettingsUpload.CustomTimeZone into every name parse).
    static func forTask(_ type: NameParserType, settings: TaskSettings) -> NameParser {
        let parser = NameParser(type)
        if settings.useCustomTimeZone,
           let zone = TimeZone(identifier: settings.customTimeZoneIdentifier) {
            parser.customTimeZone = zone
        }
        return parser
    }
}
