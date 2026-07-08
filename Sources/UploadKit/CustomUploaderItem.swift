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

    public enum BodyType: String, Codable {
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
}

/// .sxcu files live in Application Support/ShareX/CustomUploaders/,
/// same layout as Windows ShareX.
public enum CustomUploaderStore {
    public static var directory: URL {
        SettingsPaths.root.appendingPathComponent("CustomUploaders", isDirectory: true)
    }

    public static func list() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".sxcu") || $0.hasSuffix(".json") }.sorted()
    }

    public static func load(named name: String) -> CustomUploaderItem? {
        guard !name.isEmpty,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(CustomUploaderItem.self, from: data)
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
}
