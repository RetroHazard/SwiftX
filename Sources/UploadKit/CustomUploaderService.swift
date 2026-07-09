// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Executes a CustomUploaderItem: build URLRequest -> send -> parse result.
// buildRequest/parseResult are pure so the whole engine tests offline.

import Foundation
import SharedKit
import UniformTypeIdentifiers

public struct UploadFile {
    public let data: Data
    public let fileName: String
    public let mimeType: String

    public init(data: Data, fileName: String, mimeType: String? = nil) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
            ?? UTType(filenameExtension: (fileName as NSString).pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }
}

public struct UploadResult: Equatable {
    public var url: String = ""
    public var thumbnailURL: String = ""
    public var deletionURL: String = ""
}

public enum UploadError: LocalizedError {
    case missingRequestURL
    case invalidRequestURL(String)
    case httpError(statusCode: Int, message: String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .missingRequestURL:
            return "The custom uploader has no request URL."
        case .invalidRequestURL(let url):
            return "Invalid request URL: \(url)"
        case .httpError(let statusCode, let message):
            return "Upload failed (HTTP \(statusCode)): \(message)"
        case .emptyResult:
            return "The uploader returned no URL."
        }
    }
}

public enum CustomUploaderService {
    // MARK: - Request building (pure)

    public static func buildRequest(item: CustomUploaderItem, file: UploadFile) throws -> URLRequest {
        guard !item.requestURL.isEmpty else { throw UploadError.missingRequestURL }

        let parser = CustomUploaderSyntaxParser(fileName: file.fileName, input: file.fileName)

        parser.urlEncode = true
        let parsedURL = try parser.parse(item.requestURL)
        guard var components = URLComponents(string: parsedURL) else {
            throw UploadError.invalidRequestURL(parsedURL)
        }
        if !item.parameters.isEmpty {
            var query = components.queryItems ?? []
            for (key, value) in item.parameters.sorted(by: { $0.key < $1.key }) {
                query.append(URLQueryItem(name: key, value: try parser.parse(value)))
            }
            components.queryItems = query
        }
        parser.urlEncode = false

        guard let url = components.url else { throw UploadError.invalidRequestURL(parsedURL) }
        var request = URLRequest(url: url)
        request.httpMethod = item.requestMethod

        for (key, value) in item.headers {
            request.setValue(try parser.parse(value), forHTTPHeaderField: key)
        }

        switch item.body {
        case .none:
            break
        case .multipartFormData:
            let boundary = "----ShareXBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = try multipartBody(item: item, file: file, parser: parser, boundary: boundary)
        case .formURLEncoded:
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let pairs = try item.arguments.sorted(by: { $0.key < $1.key }).map { key, value in
                "\(CustomUploaderSyntaxParser.urlEncoded(key))=\(CustomUploaderSyntaxParser.urlEncoded(try parser.parse(value)))"
            }
            request.httpBody = pairs.joined(separator: "&").data(using: .utf8)
        case .json:
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = bodyData(item: item, file: file).data(using: .utf8)
        case .xml:
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = bodyData(item: item, file: file).data(using: .utf8)
        case .binary:
            request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
            request.httpBody = file.data
        }

        return request
    }

    /// JSON/XML bodies mirror C# GetData: NameParser for % macros, then a LITERAL
    /// case-insensitive replace of {input}/{filename} with encoded values.
    /// The full syntax parser never runs here - raw JSON braces must survive.
    static func bodyData(item: CustomUploaderItem, file: UploadFile) -> String {
        var result = NameParser(.text).parse(item.data)
        let encodedName = item.body == .json ? jsonEscaped(file.fileName) : xmlEscaped(file.fileName)
        result = result.replacingOccurrences(of: "{filename}", with: encodedName, options: .caseInsensitive)
        result = result.replacingOccurrences(of: "{input}", with: encodedName, options: .caseInsensitive)
        return result
    }

    private static func jsonEscaped(_ string: String) -> String {
        // JSON string content escaping (no surrounding quotes), like URLHelpers.JSONEncode
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let encoded = String(data: data, encoding: .utf8) else { return string }
        return String(encoded.dropFirst(2).dropLast(2)) // strip ["  and  "]
    }

    private static func xmlEscaped(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func multipartBody(item: CustomUploaderItem, file: UploadFile,
                              parser: CustomUploaderSyntaxParser, boundary: String) throws -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        for (key, value) in item.arguments.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append(try parser.parse(value))
            append("\r\n")
        }

        let formName = item.fileFormName.isEmpty ? "file" : item.fileFormName
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(formName)\"; filename=\"\(file.fileName)\"\r\n")
        append("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        append("\r\n--\(boundary)--\r\n")

        return body
    }

    // MARK: - Response parsing (pure)

    public static func parseResult(item: CustomUploaderItem, response: SyntaxResponse, file: UploadFile) throws -> UploadResult {
        let parser = CustomUploaderSyntaxParser(fileName: file.fileName, input: file.fileName, response: response)

        guard (200..<300).contains(response.statusCode) else {
            var message = ""
            if !item.errorMessage.isEmpty {
                message = (try? parser.parse(item.errorMessage)) ?? ""
            }
            if message.isEmpty {
                message = String(response.text.prefix(300))
            }
            throw UploadError.httpError(statusCode: response.statusCode, message: message)
        }

        var result = UploadResult()
        result.url = item.url.isEmpty
            ? response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : try parser.parse(item.url)
        if !item.thumbnailURL.isEmpty {
            result.thumbnailURL = try parser.parse(item.thumbnailURL)
        }
        if !item.deletionURL.isEmpty {
            result.deletionURL = try parser.parse(item.deletionURL)
        }

        guard !result.url.isEmpty else { throw UploadError.emptyResult }
        return result
    }

    // MARK: - Network glue

    public static func upload(file: UploadFile, with item: CustomUploaderItem) async throws -> UploadResult {
        let request = try buildRequest(item: item, file: file)
        let (data, urlResponse) = try await UploadHTTP.data(for: request)
        let http = urlResponse as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            headers[String(describing: key)] = String(describing: value)
        }
        let response = SyntaxResponse(
            statusCode: http?.statusCode ?? 0,
            text: String(data: data, encoding: .utf8) ?? "",
            url: urlResponse.url?.absoluteString ?? "",
            headers: headers
        )
        return try parseResult(item: item, response: response, file: file)
    }
}
