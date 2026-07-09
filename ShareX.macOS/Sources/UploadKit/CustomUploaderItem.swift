// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// .sxcu custom uploader definition - field names match the JSON schema written
// by Windows ShareX so community uploader files import unchanged.

import Foundation
import SharedKit

public struct CustomUploaderItem: Codable, Equatable {
    public var version: String = ""
    public var name: String = ""
    public var destinationType: String = ""
    public var requestMethod: String = "POST"
    public var requestURL: String = ""
    public var parameters: [String: String] = [:]
    public var headers: [String: String] = [:]
    public var body: BodyType = .multipartFormData
    public var arguments: [String: String] = [:]
    public var fileFormName: String = ""
    public var data: String = ""
    public var url: String = ""
    public var thumbnailURL: String = ""
    public var deletionURL: String = ""
    public var errorMessage: String = ""

    public enum BodyType: String, Codable, CaseIterable {
        case none = "None"
        case multipartFormData = "MultipartFormData"
        case formURLEncoded = "FormURLEncoded"
        case json = "JSON"
        case xml = "XML"
        case binary = "Binary"
    }

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version = "Version"
        case name = "Name"
        case destinationType = "DestinationType"
        case requestMethod = "RequestMethod"
        case requestURL = "RequestURL"
        case parameters = "Parameters"
        case headers = "Headers"
        case body = "Body"
        case arguments = "Arguments"
        case fileFormName = "FileFormName"
        case data = "Data"
        case url = "URL"
        case thumbnailURL = "ThumbnailURL"
        case deletionURL = "DeletionURL"
        case errorMessage = "ErrorMessage"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        destinationType = try c.decodeIfPresent(String.self, forKey: .destinationType) ?? ""
        requestMethod = try c.decodeIfPresent(String.self, forKey: .requestMethod) ?? "POST"
        requestURL = try c.decodeIfPresent(String.self, forKey: .requestURL) ?? ""
        parameters = try c.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        body = try c.decodeIfPresent(BodyType.self, forKey: .body) ?? .multipartFormData
        arguments = try c.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:]
        fileFormName = try c.decodeIfPresent(String.self, forKey: .fileFormName) ?? ""
        data = try c.decodeIfPresent(String.self, forKey: .data) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL) ?? ""
        deletionURL = try c.decodeIfPresent(String.self, forKey: .deletionURL) ?? ""
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
    }

    /// Display name: explicit Name, else the request URL's host.
    public var displayName: String {
        if !name.isEmpty { return name }
        return URL(string: requestURL)?.host ?? requestURL
    }

    // MARK: - Legacy syntax migration (C# CheckBackwardCompatibility)

    /// Files written before ShareX 13.7.1 use `$function$` delimiters.
    /// Converts them to the modern `{function}` form, escaping literal braces.
    /// Files without a Version are left alone (hand-written modern files).
    public mutating func migrateLegacySyntaxIfNeeded() {
        guard !version.isEmpty, Self.compareVersion(version, "13.7.1") <= 0 else { return }

        requestURL = Self.migrateOldSyntax(requestURL)
        parameters = parameters.mapValues(Self.migrateOldSyntax)
        headers = headers.mapValues(Self.migrateOldSyntax)
        arguments = arguments.mapValues(Self.migrateOldSyntax)
        // C# only substitutes the two known variables inside Data
        data = data
            .replacingOccurrences(of: "$input$", with: "{input}", options: .caseInsensitive)
            .replacingOccurrences(of: "$filename$", with: "{filename}", options: .caseInsensitive)
        url = Self.migrateOldSyntax(url)
        thumbnailURL = Self.migrateOldSyntax(thumbnailURL)
        deletionURL = Self.migrateOldSyntax(deletionURL)
        errorMessage = Self.migrateOldSyntax(errorMessage)
    }

    /// Port of C# CustomUploaderItem.MigrateOldSyntax: `$` toggles between
    /// `{` and `}`, `\x` escape pairs are dropped, literal braces get escaped.
    static func migrateOldSyntax(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var result = ""
        var open = true
        var skipNext = false
        for character in input {
            if skipNext {
                skipNext = false
                continue
            }
            switch character {
            case "$":
                result.append(open ? "{" : "}")
                open.toggle()
            case "\\":
                skipNext = true
            case "{", "}":
                result.append("\\")
                result.append(character)
            default:
                result.append(character)
            }
        }
        return result
    }

    /// Numeric dotted-version comparison ("13.7.0" < "13.7.1" < "14.0").
    static func compareVersion(_ lhs: String, _ rhs: String) -> Int {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

/// .sxcu files live in Application Support/ShareX/CustomUploaders/,
/// same layout as Windows ShareX.
public enum CustomUploaderStore {
    public static var directory: URL {
        SettingsPaths.root.appendingPathComponent("CustomUploaders", isDirectory: true)
    }

    public static func list(in directory: URL = directory) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".sxcu") || $0.hasSuffix(".json") }.sorted()
    }

    public static func load(named name: String, in directory: URL = directory) -> CustomUploaderItem? {
        guard !name.isEmpty,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              var item = try? JSONDecoder().decode(CustomUploaderItem.self, from: data) else { return nil }
        item.migrateLegacySyntaxIfNeeded()
        return item
    }

    /// Copies a .sxcu file into the store, validating it decodes. Returns the stored file name.
    @discardableResult
    public static func importFile(from source: URL) throws -> String {
        let data = try Data(contentsOf: source)
        _ = try JSONDecoder().decode(CustomUploaderItem.self, from: data) // validate before storing
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        try data.write(to: destination, options: .atomic)
        return source.lastPathComponent
    }

    /// Writes an uploader back to its .sxcu file (Windows-compatible JSON).
    public static func save(_ item: CustomUploaderItem, as fileName: String, in directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(item).write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    /// Creates a new .sxcu with a unique file name and returns that name.
    @discardableResult
    public static func create(named baseName: String, from template: CustomUploaderItem = CustomUploaderItem(),
                              in directory: URL = directory) throws -> String {
        let existing = Set(list(in: directory))
        var fileName = baseName + ".sxcu"
        var counter = 2
        while existing.contains(fileName) {
            fileName = "\(baseName) \(counter).sxcu"
            counter += 1
        }
        var item = template
        if item.name.isEmpty { item.name = baseName }
        try save(item, as: fileName, in: directory)
        return fileName
    }

    public static func delete(named name: String, in directory: URL = directory) throws {
        guard !name.isEmpty else { return }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    /// Renames an uploader's file to match a new display name; returns the
    /// file name actually used (unique-ified on collision).
    public static func rename(_ fileName: String, toBaseName baseName: String, in directory: URL = directory) throws -> String {
        let sanitized = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty, sanitized + ".sxcu" != fileName else { return fileName }
        let existing = Set(list(in: directory)).subtracting([fileName])
        var target = sanitized + ".sxcu"
        var counter = 2
        while existing.contains(target) {
            target = "\(sanitized) \(counter).sxcu"
            counter += 1
        }
        try FileManager.default.moveItem(at: directory.appendingPathComponent(fileName),
                                         to: directory.appendingPathComponent(target))
        return target
    }
}
