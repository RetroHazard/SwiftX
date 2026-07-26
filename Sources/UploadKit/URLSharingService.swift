// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// URL sharing services. Raw values match the C# URLSharingServices enum names.
// All of these open a pre-filled share page in the browser (Email uses mailto:).
// StumbleUpon/Delicious are dead upstream; Pushbullet and custom sharing land
// with their destinations.

import Foundation

public enum URLSharingService: String, Codable, CaseIterable {
    case email = "Email"
    case facebook = "Facebook"
    case reddit = "Reddit"
    case pinterest = "Pinterest"
    case tumblr = "Tumblr"
    case linkedIn = "LinkedIn"
    case vk = "VK"
    case googleLens = "GoogleImageSearch"
    case bingVisualSearch = "BingVisualSearch"

    public var displayName: String {
        switch self {
        case .email: return "Email"
        case .facebook: return "Facebook"
        case .reddit: return "Reddit"
        case .pinterest: return "Pinterest"
        case .tumblr: return "Tumblr"
        case .linkedIn: return "LinkedIn"
        case .vk: return "VK"
        case .googleLens: return "Google Lens"
        case .bingVisualSearch: return "Bing Visual Search"
        }
    }

    /// The URL to open in the default browser for sharing `url`.
    public func shareURL(for url: String) -> URL? {
        let encoded = URLShortener.queryEncode(url)
        switch self {
        case .email:
            return URL(string: "mailto:?body=\(encoded)")
        case .facebook:
            return URL(string: "https://www.facebook.com/sharer/sharer.php?u=\(encoded)")
        case .reddit:
            return URL(string: "https://www.reddit.com/submit?url=\(encoded)")
        case .pinterest:
            return URL(string: "https://pinterest.com/pin/create/button/?url=\(encoded)&media=\(encoded)")
        case .tumblr:
            return URL(string: "https://www.tumblr.com/share?v=3&u=\(encoded)")
        case .linkedIn:
            return URL(string: "https://www.linkedin.com/shareArticle?url=\(encoded)")
        case .vk:
            return URL(string: "https://vk.com/share.php?url=\(encoded)")
        case .googleLens:
            return URL(string: "https://lens.google.com/uploadbyurl?url=\(encoded)")
        case .bingVisualSearch:
            return URL(string: "https://www.bing.com/images/search?view=detailv2&iss=sbi&q=imgurl:\(encoded)")
        }
    }
}
