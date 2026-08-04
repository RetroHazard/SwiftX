// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// URL shorteners. Raw values match the C# UrlShortenerType enum names.
// Upstream services verified dead (turl.ca, qr.net, 2.gp, Firebase Dynamic
// Links, nl.cm) are intentionally not ported.

import Foundation
import SharedKit

public enum URLShortenerType: String, Codable, CaseIterable {
    case bitly = "BITLY"
    case isgd = "ISGD"
    case vgd = "VGD"
    case tinyURL = "TINYURL"
    case vurl = "VURL"
    case polr = "Polr"
    case kutt = "Kutt"
    case yourls = "YOURLS"
    case zws = "ZeroWidthShortener"

    public var displayName: String {
        switch self {
        case .bitly: return "bit.ly"
        case .isgd: return "is.gd"
        case .vgd: return "v.gd"
        case .tinyURL: return "TinyURL"
        case .vurl: return "vurl.com"
        case .polr: return L10n.t("upload.service.polr_self_hosted")
        case .kutt: return "Kutt"
        case .yourls: return L10n.t("upload.service.yourls_self_hosted")
        case .zws: return "Zero Width Shortener"
        }
    }
}

public enum URLShortenerError: LocalizedError {
    case requestFailed(String)
    case emptyResponse
    case missingConfig(String)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return L10n.t("upload.error.shortener_failed", message)
        case .emptyResponse: return L10n.t("upload.error.shortener_empty_response")
        case .missingConfig(let what): return L10n.t("upload.error.shortener_not_configured", what)
        }
    }
}

public enum URLShortener {
    static func queryEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }

    /// Prepend https:// when the user typed a bare host (C# URLHelpers.FixPrefix).
    static func fixPrefix(_ host: String) -> String {
        host.contains("://") ? host : "https://" + host
    }

    public static func apiURL(for longURL: String, type: URLShortenerType) -> URL? {
        let encoded = queryEncode(longURL)
        switch type {
        case .isgd:
            return URL(string: "https://is.gd/create.php?format=simple&url=\(encoded)")
        case .vgd:
            return URL(string: "https://v.gd/create.php?format=simple&url=\(encoded)")
        case .tinyURL:
            return URL(string: "https://tinyurl.com/api-create.php?url=\(encoded)")
        case .vurl:
            return URL(string: "https://vurl.com/api.php?url=\(encoded)")
        default:
            return nil // key-based services need a full URLRequest
        }
    }

    /// Builds the HTTP request without sending it, so tests can check it offline.
    public static func request(for longURL: String, type: URLShortenerType, config: UploadersConfig) throws -> URLRequest {
        func jsonPost(_ url: URL, body: [String: Any], bearer: String? = nil) throws -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request
        }

        switch type {
        case .isgd, .vgd, .tinyURL, .vurl:
            guard let url = apiURL(for: longURL, type: type) else {
                throw URLShortenerError.requestFailed(L10n.t("upload.error.invalid_url"))
            }
            return URLRequest(url: url)

        case .bitly:
            // ponytail: C# runs a full OAuth2 flow with registered app keys we don't
            // have; bit.ly issues personal access tokens directly (Settings → API)
            guard !config.bitlyAccessToken.isEmpty else { throw URLShortenerError.missingConfig(L10n.t("upload.error.config.bitly_token")) }
            var body: [String: Any] = ["long_url": longURL]
            if !config.bitlyDomain.isEmpty { body["domain"] = config.bitlyDomain }
            return try jsonPost(URL(string: "https://api-ssl.bitly.com/v4/shorten")!,
                                body: body, bearer: config.bitlyAccessToken)

        case .polr:
            guard !config.polrAPIHostname.isEmpty, !config.polrAPIKey.isEmpty else {
                throw URLShortenerError.missingConfig(L10n.t("upload.error.config.polr"))
            }
            let host = fixPrefix(config.polrAPIHostname)
            var query = config.polrUseAPIv1
                ? "apikey=\(queryEncode(config.polrAPIKey))&action=shorten&url=\(queryEncode(longURL))"
                : "key=\(queryEncode(config.polrAPIKey))&url=\(queryEncode(longURL))"
            if config.polrIsSecret && !config.polrUseAPIv1 { query += "&is_secret=true" }
            guard let url = URL(string: "\(host)?\(query)") else {
                throw URLShortenerError.requestFailed(L10n.t("upload.error.invalid_service_url", "Polr"))
            }
            return URLRequest(url: url)

        case .kutt:
            guard !config.kutt.apiKey.isEmpty else { throw URLShortenerError.missingConfig(L10n.t("upload.error.config.kutt")) }
            let host = config.kutt.host.isEmpty ? "https://kutt.it" : fixPrefix(config.kutt.host)
            var body: [String: Any] = ["target": longURL, "reuse": config.kutt.reuse]
            if !config.kutt.password.isEmpty { body["password"] = config.kutt.password }
            if !config.kutt.domain.isEmpty { body["domain"] = config.kutt.domain }
            var request = try jsonPost(URL(string: host + "/api/v2/links")!, body: body)
            request.setValue(config.kutt.apiKey, forHTTPHeaderField: "X-API-KEY")
            return request

        case .yourls:
            guard !config.yourlsAPIURL.isEmpty else { throw URLShortenerError.missingConfig(L10n.t("upload.error.config.yourls_url")) }
            var params = "action=shorturl&format=simple&url=\(queryEncode(longURL))"
            if !config.yourlsSignature.isEmpty {
                params += "&signature=\(queryEncode(config.yourlsSignature))"
            } else if !config.yourlsUsername.isEmpty, !config.yourlsPassword.isEmpty {
                params += "&username=\(queryEncode(config.yourlsUsername))&password=\(queryEncode(config.yourlsPassword))"
            } else {
                throw URLShortenerError.missingConfig(L10n.t("upload.error.config.yourls_credentials"))
            }
            guard let url = URL(string: fixPrefix(config.yourlsAPIURL)) else {
                throw URLShortenerError.requestFailed(L10n.t("upload.error.invalid_service_url", "YOURLS"))
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = params.data(using: .utf8)
            return request

        case .zws:
            let endpoint = config.zeroWidthShortenerURL.isEmpty ? "https://api.zws.im" : fixPrefix(config.zeroWidthShortenerURL)
            guard let url = URL(string: endpoint) else {
                throw URLShortenerError.requestFailed(L10n.t("upload.error.invalid_service_url", "ZWS"))
            }
            let token = config.zeroWidthShortenerToken
            return try jsonPost(url, body: ["url": longURL], bearer: token.isEmpty ? nil : token)
        }
    }

    /// Extracts the short URL from a 2xx response body.
    public static func parseResponse(_ data: Data, type: URLShortenerType) throws -> String {
        switch type {
        case .bitly, .kutt:
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let link = json?["link"] as? String, !link.isEmpty else {
                throw URLShortenerError.emptyResponse
            }
            return link
        case .zws:
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let url = json?["url"] as? String, !url.isEmpty { return url }
            guard let short = json?["short"] as? String, !short.isEmpty else {
                throw URLShortenerError.emptyResponse
            }
            return "https://zws.im/" + short
        case .isgd, .vgd, .tinyURL, .vurl, .polr, .yourls:
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.hasPrefix("http") else {
                throw text.isEmpty ? URLShortenerError.emptyResponse : URLShortenerError.requestFailed(text)
            }
            return text
        }
    }

    public static func shorten(_ longURL: String, type: URLShortenerType,
                               config: UploadersConfig = UploadersConfig.load()) async throws -> String {
        let request = try request(for: longURL, type: type, config: config)
        let (data, response) = try await UploadHTTP.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw URLShortenerError.requestFailed("HTTP \(status): \(text.prefix(200))")
        }
        return try parseResponse(data, type: type)
    }
}
