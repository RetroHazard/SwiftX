// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Keyless URL shorteners. Raw values match the C# UrlShortenerType enum names.

import Foundation

public enum URLShortenerType: String, Codable, CaseIterable {
    case isgd = "ISGD"
    case vgd = "VGD"
    case tinyURL = "TINYURL"

    public var displayName: String {
        switch self {
        case .isgd: return "is.gd"
        case .vgd: return "v.gd"
        case .tinyURL: return "TinyURL"
        }
    }
}

public enum URLShortenerError: LocalizedError {
    case requestFailed(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return "URL shortener failed: \(message)"
        case .emptyResponse: return "URL shortener returned an empty response."
        }
    }
}

public enum URLShortener {
    /// All three services take a GET and answer with the short URL as plain text.
    public static func apiURL(for longURL: String, type: URLShortenerType) -> URL? {
        let encoded = longURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? longURL
        switch type {
        case .isgd:
            return URL(string: "https://is.gd/create.php?format=simple&url=\(encoded)")
        case .vgd:
            return URL(string: "https://v.gd/create.php?format=simple&url=\(encoded)")
        case .tinyURL:
            return URL(string: "https://tinyurl.com/api-create.php?url=\(encoded)")
        }
    }

    public static func shorten(_ longURL: String, type: URLShortenerType) async throws -> String {
        guard let url = apiURL(for: longURL, type: type) else {
            throw URLShortenerError.requestFailed("invalid URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (200..<300).contains(status) else {
            throw URLShortenerError.requestFailed("HTTP \(status): \(text.prefix(200))")
        }
        guard text.hasPrefix("http") else {
            throw text.isEmpty ? URLShortenerError.emptyResponse : URLShortenerError.requestFailed(text)
        }
        return text
    }
}
