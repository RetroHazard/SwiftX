// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import UploadKit
@testable import SharedKit

struct AmazonS3Tests {
    // AWS's published SigV4 test vector (docs: "Deriving the signing key")
    @Test func signingKeyMatchesAWSTestVector() {
        let key = AmazonS3Uploader.signingKey(
            secret: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            date: "20150830",
            region: "us-east-1",
            service: "iam"
        )
        #expect(key.hexString == "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9")
    }

    private var settings: AmazonS3Settings {
        var s = AmazonS3Settings()
        s.accessKeyID = "AKIDEXAMPLE"
        s.secretAccessKey = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        s.region = "us-east-1"
        s.bucket = "my-bucket"
        s.objectPrefix = "shots"
        return s
    }

    private var fixedDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2015, month: 8, day: 30, hour: 12, minute: 36))!
    }

    @Test func buildsSignedPutRequest() throws {
        let file = UploadFile(data: Data("IMG".utf8), fileName: "shot.png", mimeType: "image/png")
        let request = try AmazonS3Uploader.buildRequest(file: file, settings: settings, date: fixedDate)

        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://my-bucket.s3.us-east-1.amazonaws.com/shots/shot.png")
        #expect(request.value(forHTTPHeaderField: "x-amz-date") == "20150830T123600Z")
        #expect(request.value(forHTTPHeaderField: "x-amz-acl") == "public-read")

        let auth = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/s3/aws4_request,"))
        #expect(auth.contains("SignedHeaders=host;x-amz-acl;x-amz-content-sha256;x-amz-date,"))
        // signature is 64 hex chars
        let signature = auth.components(separatedBy: "Signature=").last ?? ""
        #expect(signature.count == 64)
        #expect(signature.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func signatureIsDeterministic() throws {
        let file = UploadFile(data: Data("IMG".utf8), fileName: "shot.png", mimeType: "image/png")
        let first = try AmazonS3Uploader.buildRequest(file: file, settings: settings, date: fixedDate)
        let second = try AmazonS3Uploader.buildRequest(file: file, settings: settings, date: fixedDate)
        #expect(first.value(forHTTPHeaderField: "Authorization") == second.value(forHTTPHeaderField: "Authorization"))
    }

    @Test func objectKeyParsesPrefixPatterns() {
        var s = settings
        s.objectPrefix = "ShareX/%y"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2024, month: 3, day: 7))!
        #expect(AmazonS3Uploader.objectKey(for: "a.png", settings: s, date: date) == "ShareX/2024/a.png")
    }

    @Test func specialCharactersInKeyAreEncoded() throws {
        let file = UploadFile(data: Data(), fileName: "my shot@2x.png", mimeType: "image/png")
        let request = try AmazonS3Uploader.buildRequest(file: file, settings: settings, date: fixedDate)
        #expect(request.url?.absoluteString.contains("my%20shot%402x.png") == true)
    }

    @Test func customEndpointUsedVerbatim() throws {
        var s = settings
        s.endpoint = "minio.internal.example:9000"
        let file = UploadFile(data: Data(), fileName: "a.png", mimeType: "image/png")
        let request = try AmazonS3Uploader.buildRequest(file: file, settings: s, date: fixedDate)
        #expect(request.url?.host == "minio.internal.example")
    }

    @Test func incompleteSettingsThrow() {
        let file = UploadFile(data: Data(), fileName: "a.png", mimeType: "image/png")
        #expect(throws: AmazonS3Error.self) {
            try AmazonS3Uploader.buildRequest(file: file, settings: AmazonS3Settings(), date: fixedDate)
        }
    }
}

struct URLShortenerTests {
    @Test func buildsAPIURLs() {
        #expect(URLShortener.apiURL(for: "https://example.com/a b", type: .isgd)?.absoluteString
                == "https://is.gd/create.php?format=simple&url=https%3A%2F%2Fexample.com%2Fa%20b")
        #expect(URLShortener.apiURL(for: "https://example.com", type: .tinyURL)?.absoluteString
                == "https://tinyurl.com/api-create.php?url=https%3A%2F%2Fexample.com")
    }

    @Test func typeNamesMatchCSharpEnum() {
        #expect(URLShortenerType.isgd.rawValue == "ISGD")
        #expect(URLShortenerType(rawValue: "TINYURL") == .tinyURL)
    }
}
