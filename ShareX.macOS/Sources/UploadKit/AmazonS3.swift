// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Amazon S3 (and S3-compatible) uploads with AWS Signature Version 4.
// buildRequest is pure (date injectable) so signing is fully unit-testable.

import CryptoKit
import Foundation
import SharedKit

public enum AmazonS3Error: LocalizedError {
    case incompleteSettings
    case invalidEndpoint(String)

    public var errorDescription: String? {
        switch self {
        case .incompleteSettings:
            return "Amazon S3 requires access key, secret key, region and bucket."
        case .invalidEndpoint(let endpoint):
            return "Invalid S3 endpoint: \(endpoint)"
        }
    }
}

public enum AmazonS3Uploader {
    public static func upload(file: UploadFile, settings: AmazonS3Settings) async throws -> UploadResult {
        let request = try buildRequest(file: file, settings: settings, date: Date())
        let (data, urlResponse) = try await UploadHTTP.data(for: request)
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.httpError(statusCode: status, message: String(body.prefix(300)))
        }
        var result = UploadResult()
        result.url = publicURL(for: request.url!, settings: settings)
        return result
    }

    // MARK: - Request building (pure)

    public static func buildRequest(file: UploadFile, settings: AmazonS3Settings, date: Date) throws -> URLRequest {
        guard !settings.accessKeyID.isEmpty, !settings.secretAccessKey.isEmpty,
              !settings.region.isEmpty, !settings.bucket.isEmpty else {
            throw AmazonS3Error.incompleteSettings
        }

        let host = settings.endpoint.isEmpty
            ? "\(settings.bucket).s3.\(settings.region).amazonaws.com"
            : settings.endpoint
        let key = objectKey(for: file.fileName, settings: settings, date: date)
        let encodedPath = "/" + key.split(separator: "/").map(uriEncoded).joined(separator: "/")

        guard let url = URL(string: "https://\(host)\(encodedPath)") else {
            throw AmazonS3Error.invalidEndpoint(host)
        }

        let amzDate = Self.amzDateFormatter.string(from: date)
        let shortDate = String(amzDate.prefix(8))
        let payloadHash = SHA256.hash(data: file.data).hexString

        var headers = [
            ("host", host),
            ("x-amz-acl", "public-read"),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzDate)
        ]
        headers.sort { $0.0 < $1.0 }
        let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = headers.map(\.0).joined(separator: ";")

        let canonicalRequest = [
            "PUT", encodedPath, "", canonicalHeaders, signedHeaders, payloadHash
        ].joined(separator: "\n")

        let scope = "\(shortDate)/\(settings.region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256", amzDate, scope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        ].joined(separator: "\n")

        let signature = hmacSHA256(
            key: signingKey(secret: settings.secretAccessKey, date: shortDate, region: settings.region, service: "s3"),
            data: Data(stringToSign.utf8)
        ).hexString

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = file.data
        request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("public-read", forHTTPHeaderField: "x-amz-acl")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(settings.accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    public static func objectKey(for fileName: String, settings: AmazonS3Settings, date: Date = Date()) -> String {
        let parser = NameParser(.filePath)
        parser.date = date
        var prefix = parser.parse(settings.objectPrefix)
        if !prefix.isEmpty, !prefix.hasSuffix("/") {
            prefix += "/"
        }
        return prefix + fileName
    }

    static func publicURL(for requestURL: URL, settings: AmazonS3Settings) -> String {
        requestURL.absoluteString
    }

    // MARK: - SigV4 primitives

    /// HMAC chain: AWS4+secret -> date -> region -> service -> "aws4_request"
    static func signingKey(secret: String, date: String, region: String, service: String) -> Data {
        var key = hmacSHA256(key: Data("AWS4\(secret)".utf8), data: Data(date.utf8))
        key = hmacSHA256(key: key, data: Data(region.utf8))
        key = hmacSHA256(key: key, data: Data(service.utf8))
        key = hmacSHA256(key: key, data: Data("aws4_request".utf8))
        return key
    }

    static func hmacSHA256(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    /// RFC 3986 encoding as required by SigV4 canonical URIs.
    static func uriEncoded(_ component: Substring) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String(component).addingPercentEncoding(withAllowedCharacters: unreserved) ?? String(component)
    }

    static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
