// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import UploadKit
import SharedKit

struct SimpleHostRequestTests {
    let file = UploadFile(data: Data("png".utf8), fileName: "shot.png", mimeType: "image/png")

    @Test func uguuNeedsNoConfig() throws {
        let request = try SimpleHostUploader.request(file: file, destination: .uguu, config: UploadersConfig(), boundary: "B")
        #expect(request.url?.absoluteString == "https://uguu.se/upload.php?output=text")
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"files[]\"; filename=\"shot.png\""))
        #expect(body.contains("Content-Type: image/png"))
        #expect(body.hasSuffix("--B--\r\n"))
    }

    @Test func sulSendsKeyAndWizardFields() throws {
        var config = UploadersConfig()
        config.sulAPIKey = "sk"
        let request = try SimpleHostUploader.request(file: file, destination: .sul, config: config, boundary: "B")
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"key\"\r\n\r\nsk"))
        #expect(body.contains("name=\"wizard\"\r\n\r\ntrue"))
        #expect(body.contains("name=\"file\"; filename=\"shot.png\""))
    }

    @Test func streamableUsesBasicAuth() throws {
        var config = UploadersConfig()
        config.streamableUsername = "user"
        config.streamablePassword = "pass"
        let request = try SimpleHostUploader.request(file: file, destination: .streamable, config: config)
        let expected = "Basic " + Data("user:pass".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test func cheveretoFixesPrefixAndSendsKey() throws {
        var config = UploadersConfig()
        config.chevereto.uploadURL = "img.example/api/1/upload"
        config.chevereto.apiKey = "ck"
        let request = try SimpleHostUploader.request(file: file, destination: .chevereto, config: config, boundary: "B")
        #expect(request.url?.absoluteString == "https://img.example/api/1/upload")
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"key\"\r\n\r\nck"))
        #expect(body.contains("name=\"source\"; filename=\"shot.png\""))
    }

    @Test func missingCredentialsThrow() {
        for destination in [SimpleHostDestination.pomf, .sul, .lobfile, .puush, .chevereto, .streamable] {
            #expect(throws: UploadError.self, "\(destination)") {
                try SimpleHostUploader.request(file: file, destination: destination, config: UploadersConfig())
            }
        }
    }
}

struct SimpleHostResponseTests {
    let config = UploadersConfig()

    @Test func parsesUguuPlainText() throws {
        let result = try SimpleHostUploader.parseResponse(Data("https://a.uguu.se/xyz.png\n".utf8), destination: .uguu, config: config)
        #expect(result.url == "https://a.uguu.se/xyz.png")
    }

    @Test func parsesPomfAndPrependsResultURL() throws {
        var config = UploadersConfig()
        config.pomf.resultURL = "files.example"
        let json = #"{"success":true,"files":[{"url":"abc.png"}]}"#
        let result = try SimpleHostUploader.parseResponse(Data(json.utf8), destination: .pomf, config: config)
        #expect(result.url == "https://files.example/abc.png")

        let absolute = #"{"success":true,"files":[{"url":"https://cdn.example/abc.png"}]}"#
        let result2 = try SimpleHostUploader.parseResponse(Data(absolute.utf8), destination: .pomf, config: config)
        #expect(result2.url == "https://cdn.example/abc.png")
    }

    @Test func parsesVgymeWithDeletionURL() throws {
        let json = #"{"error":false,"image":"https://vgy.me/u/x.png","delete":"https://vgy.me/delete/k"}"#
        let result = try SimpleHostUploader.parseResponse(Data(json.utf8), destination: .vgyme, config: config)
        #expect(result.url == "https://vgy.me/u/x.png")
        #expect(result.deletionURL == "https://vgy.me/delete/k")
    }

    @Test func assemblesSulURL() throws {
        var config = UploadersConfig()
        config.sulAPIKey = "sk"
        let json = #"{"protocol":"https://","domain":"s-ul.eu","filename":"AbCd","extension":".png"}"#
        let result = try SimpleHostUploader.parseResponse(Data(json.utf8), destination: .sul, config: config)
        #expect(result.url == "https://s-ul.eu/AbCd.png")
        #expect(result.deletionURL == "https://s-ul.eu/delete.php?key=sk&file=AbCd")
    }

    @Test func parsesPuushCSV() throws {
        let result = try SimpleHostUploader.parseResponse(Data("0,https://puu.sh/x.png,123,456".utf8), destination: .puush, config: config)
        #expect(result.url == "https://puu.sh/x.png")
        #expect(throws: UploadError.self) {
            try SimpleHostUploader.parseResponse(Data("-1".utf8), destination: .puush, config: config)
        }
    }

    @Test func cheveretoHonorsDirectURLSetting() throws {
        let json = #"{"image":{"url":"https://i.example/x.png","url_viewer":"https://i.example/view/x","thumb":{"url":"https://i.example/t/x.png"}}}"#
        var config = UploadersConfig()
        let direct = try SimpleHostUploader.parseResponse(Data(json.utf8), destination: .chevereto, config: config)
        #expect(direct.url == "https://i.example/x.png")
        #expect(direct.thumbnailURL == "https://i.example/t/x.png")
        config.cheveretoDirectURL = false
        let viewer = try SimpleHostUploader.parseResponse(Data(json.utf8), destination: .chevereto, config: config)
        #expect(viewer.url == "https://i.example/view/x")
    }

    @Test func parsesStreamableShortcode() throws {
        let result = try SimpleHostUploader.parseResponse(Data(#"{"shortcode":"abc12"}"#.utf8), destination: .streamable, config: config)
        #expect(result.url == "https://streamable.com/abc12")
    }

    @Test func parsesLobFileAndRejectsFailure() throws {
        let ok = try SimpleHostUploader.parseResponse(Data(#"{"success":true,"url":"https://lobfile.com/x"}"#.utf8), destination: .lobfile, config: config)
        #expect(ok.url == "https://lobfile.com/x")
        #expect(throws: UploadError.self) {
            try SimpleHostUploader.parseResponse(Data(#"{"success":false,"error":"bad key"}"#.utf8), destination: .lobfile, config: config)
        }
    }

    @Test func rawValuesMatchCSharpEnums() {
        #expect(SimpleHostDestination(rawValue: "Lithiio") == .lobfile)
        #expect(SimpleHostDestination(rawValue: "Vgyme") == .vgyme)
        #expect(SimpleHostDestination(rawValue: "Sul") == .sul)
    }
}
