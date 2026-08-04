// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Simple file hosts: one multipart POST with a file field, then parse the
// response. Raw values match the C# ImageDestination/FileDestination enum
// names. transfer.sh is not ported — its public instance is dead (2026-07).

import Foundation
import SharedKit

public enum SimpleHostDestination: String, Codable, CaseIterable {
    case uguu = "Uguu"
    case pomf = "Pomf"
    case vgyme = "Vgyme"
    case sul = "Sul"
    case lobfile = "Lithiio"
    case puush = "Puush"
    case chevereto = "Chevereto"
    case streamable = "Streamable"

    public var displayName: String {
        switch self {
        case .uguu: return "Uguu"
        case .pomf: return L10n.t("upload.service.pomf_clone")
        case .vgyme: return "vgy.me"
        case .sul: return "s-ul"
        case .lobfile: return "LobFile"
        case .puush: return "Puush"
        case .chevereto: return L10n.t("upload.service.chevereto_self_hosted")
        case .streamable: return "Streamable"
        }
    }
}

public enum SimpleHostUploader {
    /// C# sends its user agent as a form value on some hosts.
    static let clientName = "SwiftX-macOS"

    /// Builds the multipart request without sending it, so tests run offline.
    public static func request(file: UploadFile, destination: SimpleHostDestination,
                               config: UploadersConfig, boundary: String = "----SwiftXBoundary\(UUID().uuidString)") throws -> URLRequest {
        let urlString: String
        var fields: [(String, String)] = []
        let fileField: String
        var headers: [String: String] = [:]

        switch destination {
        case .uguu:
            urlString = "https://uguu.se/upload.php?output=text"
            fileField = "files[]"
        case .pomf:
            guard !config.pomf.uploadURL.isEmpty else { throw UploadError.missingRequestURL }
            urlString = config.pomf.uploadURL
            fileField = "files[]"
        case .vgyme:
            urlString = "https://vgy.me/upload"
            fileField = "file"
            if !config.vgymeUserKey.isEmpty { fields.append(("userkey", config.vgymeUserKey)) }
        case .sul:
            guard !config.sulAPIKey.isEmpty else { throw UploadError.missingRequestURL }
            urlString = "https://s-ul.eu/api/v1/upload"
            fileField = "file"
            fields = [("wizard", "true"), ("key", config.sulAPIKey), ("client", "sharex-native")]
        case .lobfile:
            guard !config.lithiio.userAPIKey.isEmpty else { throw UploadError.missingRequestURL }
            urlString = "https://lobfile.com/api/v3/upload"
            fileField = "file"
            fields = [("api_key", config.lithiio.userAPIKey)]
        case .puush:
            guard !config.puushAPIKey.isEmpty else { throw UploadError.missingRequestURL }
            urlString = "https://puush.me/api/up"
            fileField = "f"
            fields = [("k", config.puushAPIKey), ("z", clientName)]
        case .chevereto:
            guard !config.chevereto.uploadURL.isEmpty, !config.chevereto.apiKey.isEmpty else {
                throw UploadError.missingRequestURL
            }
            urlString = URLShortener.fixPrefix(config.chevereto.uploadURL)
            fileField = "source"
            fields = [("key", config.chevereto.apiKey), ("format", "json")]
        case .streamable:
            guard !config.streamableUsername.isEmpty, !config.streamablePassword.isEmpty else {
                throw UploadError.missingRequestURL
            }
            urlString = "https://api.streamable.com/upload"
            fileField = "file"
            let credentials = Data("\(config.streamableUsername):\(config.streamablePassword)".utf8).base64EncodedString()
            headers["Authorization"] = "Basic \(credentials)"
        }

        guard let url = URL(string: urlString) else { throw UploadError.invalidRequestURL(urlString) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = multipartBody(fields: fields, fileField: fileField, file: file, boundary: boundary)
        return request
    }

    static func multipartBody(fields: [(String, String)], fileField: String,
                              file: UploadFile, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(file.fileName)\"\r\n")
        append("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Extracts URLs from a 2xx response body.
    public static func parseResponse(_ data: Data, destination: SimpleHostDestination,
                                     config: UploadersConfig) throws -> UploadResult {
        // C#'s Json.NET matches keys case-insensitively; these APIs are lowercase.
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch destination {
        case .uguu:
            guard text.hasPrefix("http") else { throw UploadError.emptyResult }
            return UploadResult(url: text)

        case .pomf:
            guard let files = json?["files"] as? [[String: Any]],
                  var url = files.first?["url"] as? String, !url.isEmpty else {
                throw UploadError.emptyResult
            }
            if !url.contains("://"), !config.pomf.resultURL.isEmpty {
                let base = URLShortener.fixPrefix(config.pomf.resultURL)
                url = base.hasSuffix("/") ? base + url : base + "/" + url
            }
            return UploadResult(url: url)

        case .vgyme:
            guard json?["error"] as? Bool != true, let url = json?["image"] as? String else {
                throw UploadError.emptyResult
            }
            return UploadResult(url: url, deletionURL: json?["delete"] as? String ?? "")

        case .sul:
            guard let proto = json?["protocol"] as? String,
                  let domain = json?["domain"] as? String,
                  let name = json?["filename"] as? String else {
                throw UploadError.httpError(statusCode: 0, message: json?["error"] as? String ?? L10n.t("upload.error.host_generic", "s-ul"))
            }
            let ext = json?["extension"] as? String ?? ""
            return UploadResult(url: proto + domain + "/" + name + ext,
                                deletionURL: "https://s-ul.eu/delete.php?key=\(config.sulAPIKey)&file=\(name)")

        case .lobfile:
            guard json?["success"] as? Bool == true, let url = json?["url"] as? String else {
                throw UploadError.httpError(statusCode: 0, message: json?["error"] as? String ?? L10n.t("upload.error.host_generic", "LobFile"))
            }
            return UploadResult(url: url)

        case .puush:
            // response is "status,url,id,size"; negative status is an error code
            let values = text.components(separatedBy: ",")
            guard let status = values.first.flatMap(Int.init), status >= 0, values.count > 1 else {
                let message: String
                switch values.first.flatMap(Int.init) ?? -2 {
                case -1: message = L10n.t("upload.error.puush.auth_failure")
                case -3: message = L10n.t("upload.error.puush.checksum")
                case -4: message = L10n.t("upload.error.puush.storage_full")
                default: message = L10n.t("upload.error.puush.connection")
                }
                throw UploadError.httpError(statusCode: 0, message: "Puush: \(message)")
            }
            return UploadResult(url: values[1])

        case .chevereto:
            guard let image = json?["image"] as? [String: Any] else { throw UploadError.emptyResult }
            let direct = image["url"] as? String ?? ""
            let viewer = image["url_viewer"] as? String ?? ""
            let url = config.cheveretoDirectURL ? direct : viewer
            let thumb = (image["thumb"] as? [String: Any])?["url"] as? String ?? ""
            guard !url.isEmpty else { throw UploadError.emptyResult }
            return UploadResult(url: url, thumbnailURL: thumb)

        case .streamable:
            // ponytail: C# polls /videos/{shortcode} for transcode progress and a
            // direct mp4 URL; the page URL works as soon as transcoding finishes
            guard let shortcode = json?["shortcode"] as? String, !shortcode.isEmpty else {
                throw UploadError.emptyResult
            }
            return UploadResult(url: "https://streamable.com/" + shortcode)
        }
    }

    public static func upload(file: UploadFile, destination: SimpleHostDestination,
                              config: UploadersConfig) async throws -> UploadResult {
        let request = try request(file: file, destination: destination, config: config)
        let (data, response) = try await UploadHTTP.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.httpError(statusCode: status, message: String(message.prefix(200)))
        }
        return try parseResponse(data, destination: destination, config: config)
    }
}
