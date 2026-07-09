// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import UploadKit
import SharedKit

struct ShortenerRequestTests {
    let longURL = "https://example.com/a b"

    func json(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func bitlyBuildsAuthorizedJSONPost() throws {
        var config = UploadersConfig()
        config.bitlyAccessToken = "tok123"
        config.bitlyDomain = "short.example"
        let request = try URLShortener.request(for: longURL, type: .bitly, config: config)
        #expect(request.url?.absoluteString == "https://api-ssl.bitly.com/v4/shorten")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok123")
        let body = try json(request)
        #expect(body["long_url"] as? String == longURL)
        #expect(body["domain"] as? String == "short.example")
    }

    @Test func bitlyWithoutTokenThrows() {
        #expect(throws: URLShortenerError.self) {
            try URLShortener.request(for: longURL, type: .bitly, config: UploadersConfig())
        }
    }

    @Test func kuttSendsAPIKeyHeaderAndTarget() throws {
        var config = UploadersConfig()
        config.kutt.apiKey = "key1"
        let request = try URLShortener.request(for: longURL, type: .kutt, config: config)
        #expect(request.url?.absoluteString == "https://kutt.it/api/v2/links")
        #expect(request.value(forHTTPHeaderField: "X-API-KEY") == "key1")
        let body = try json(request)
        #expect(body["target"] as? String == longURL)
        #expect(body["reuse"] as? Bool == false)
    }

    @Test func polrBuildsGETQuery() throws {
        var config = UploadersConfig()
        config.polrAPIHostname = "polr.example/api/v2/action/shorten"
        config.polrAPIKey = "k"
        let request = try URLShortener.request(for: "https://example.com", type: .polr, config: config)
        #expect(request.url?.absoluteString
                == "https://polr.example/api/v2/action/shorten?key=k&url=https%3A%2F%2Fexample.com")
    }

    @Test func yourlsRequiresAuth() throws {
        var config = UploadersConfig()
        config.yourlsAPIURL = "https://y.example/yourls-api.php"
        #expect(throws: URLShortenerError.self) {
            try URLShortener.request(for: longURL, type: .yourls, config: config)
        }
        config.yourlsSignature = "sig"
        let request = try URLShortener.request(for: "https://example.com", type: .yourls, config: config)
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains("action=shorturl"))
        #expect(body.contains("signature=sig"))
        #expect(body.contains("format=simple"))
    }

    @Test func zwsDefaultsEndpointAndOmitsAuthWithoutToken() throws {
        let request = try URLShortener.request(for: longURL, type: .zws, config: UploadersConfig())
        #expect(request.url?.absoluteString == "https://api.zws.im")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func keylessTypesStayGET() throws {
        for type in [URLShortenerType.isgd, .vgd, .tinyURL, .vurl] {
            let request = try URLShortener.request(for: longURL, type: type, config: UploadersConfig())
            #expect(request.httpBody == nil)
        }
    }
}

struct ShortenerResponseTests {
    @Test func parsesJSONLinkResponses() throws {
        let data = Data(#"{"id":"x","link":"https://kutt.it/abc"}"#.utf8)
        #expect(try URLShortener.parseResponse(data, type: .kutt) == "https://kutt.it/abc")
        #expect(try URLShortener.parseResponse(data, type: .bitly) == "https://kutt.it/abc")
    }

    @Test func parsesZWSVariants() throws {
        #expect(try URLShortener.parseResponse(Data(#"{"url":"https://zws.im/x"}"#.utf8), type: .zws) == "https://zws.im/x")
        #expect(try URLShortener.parseResponse(Data(#"{"short":"abc"}"#.utf8), type: .zws) == "https://zws.im/abc")
    }

    @Test func plainTextMustBeAURL() throws {
        #expect(try URLShortener.parseResponse(Data("https://is.gd/x\n".utf8), type: .isgd) == "https://is.gd/x")
        #expect(throws: URLShortenerError.self) {
            try URLShortener.parseResponse(Data("Invalid URL".utf8), type: .vurl)
        }
    }
}

struct URLSharingServiceTests {
    @Test func buildsEncodedShareURLs() {
        let url = "https://example.com/a b"
        #expect(URLSharingService.reddit.shareURL(for: url)?.absoluteString
                == "https://www.reddit.com/submit?url=https%3A%2F%2Fexample.com%2Fa%20b")
        #expect(URLSharingService.email.shareURL(for: url)?.absoluteString
                == "mailto:?body=https%3A%2F%2Fexample.com%2Fa%20b")
        for service in URLSharingService.allCases {
            #expect(service.shareURL(for: url) != nil)
        }
    }

    @Test func rawValuesMatchCSharpEnum() {
        #expect(URLSharingService(rawValue: "GoogleImageSearch") == .googleLens)
        #expect(URLSharingService(rawValue: "BingVisualSearch") == .bingVisualSearch)
        #expect(URLShortenerType(rawValue: "ZeroWidthShortener") == .zws)
        #expect(URLShortenerType(rawValue: "BITLY") == .bitly)
    }
}
