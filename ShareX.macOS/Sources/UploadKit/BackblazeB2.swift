// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Backblaze B2 native API: authorize -> resolve bucket ID -> get upload URL ->
// upload. B2 documents that upload URLs go stale, so failed uploads retry with
// a fresh URL.

import CryptoKit
import Foundation
import SharedKit

public enum BackblazeB2Uploader {
    struct Authorization: Decodable {
        let accountId: String
        let apiUrl: String
        let downloadUrl: String
        let authorizationToken: String
        let allowed: Allowed?
        struct Allowed: Decodable { let bucketId: String? }
    }

    public static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        guard !config.b2ApplicationKeyId.isEmpty, !config.b2ApplicationKey.isEmpty, !config.b2BucketName.isEmpty else {
            throw UploadError.missingRequestURL
        }

        let auth = try await authorize(config: config)
        let bucketId: String
        if let restricted = auth.allowed?.bucketId {
            bucketId = restricted
        } else {
            bucketId = try await bucketID(auth: auth, name: config.b2BucketName)
        }
        let path = destinationPath(fileName: file.fileName, uploadPath: config.b2UploadPath)

        // ponytail: 3 tries with a fresh upload URL each time covers the
        // documented stale-URL failures; exponential backoff if it ever matters
        var lastError: Error = UploadError.emptyResult
        for _ in 0..<3 {
            do {
                let (uploadURL, token) = try await uploadTarget(auth: auth, bucketId: bucketId)
                let request = uploadRequest(uploadURL: uploadURL, token: token, file: file, destinationPath: path)
                let (data, response) = try await UploadHTTP.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    lastError = UploadError.httpError(statusCode: status,
                                                      message: String((String(data: data, encoding: .utf8) ?? "").prefix(200)))
                    continue
                }
                return UploadResult(url: fileURL(downloadUrl: auth.downloadUrl, bucket: config.b2BucketName,
                                                 path: path, config: config))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Pure pieces (testable offline)

    public static func destinationPath(fileName: String, uploadPath: String, date: Date = Date()) -> String {
        let parser = NameParser(.filePath)
        parser.date = date
        var prefix = parser.parse(uploadPath)
        if !prefix.isEmpty, !prefix.hasSuffix("/") { prefix += "/" }
        return prefix + fileName
    }

    public static func uploadRequest(uploadURL: URL, token: String, file: UploadFile, destinationPath: String) -> URLRequest {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.httpBody = file.data
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(encodedPath(destinationPath), forHTTPHeaderField: "X-Bz-File-Name")
        request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(Insecure.SHA1.hash(data: file.data).map { String(format: "%02x", $0) }.joined(),
                         forHTTPHeaderField: "X-Bz-Content-Sha1")
        return request
    }

    public static func fileURL(downloadUrl: String, bucket: String, path: String, config: UploadersConfig) -> String {
        let encoded = encodedPath(path)
        if config.b2UseCustomUrl, !config.b2CustomUrl.isEmpty {
            return URLShortener.fixPrefix(config.b2CustomUrl) + "/" + encoded
        }
        return "\(downloadUrl)/file/\(bucket)/\(encoded)"
    }

    /// Percent-encodes each path segment, keeping "/" separators (B2 requires this).
    static func encodedPath(_ path: String) -> String {
        path.split(separator: "/").map(AmazonS3Uploader.uriEncoded).joined(separator: "/")
    }

    // MARK: - API calls

    static func authorize(config: UploadersConfig) async throws -> Authorization {
        var request = URLRequest(url: URL(string: "https://api.backblazeb2.com/b2api/v1/b2_authorize_account")!)
        let credentials = Data("\(config.b2ApplicationKeyId):\(config.b2ApplicationKey)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return try await send(request, as: Authorization.self, step: "B2 authorize")
    }

    static func bucketID(auth: Authorization, name: String) async throws -> String {
        struct Response: Decodable {
            let buckets: [Bucket]
            struct Bucket: Decodable { let bucketId: String, bucketName: String }
        }
        var request = URLRequest(url: URL(string: auth.apiUrl + "/b2api/v1/b2_list_buckets")!)
        request.httpMethod = "POST"
        request.setValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["accountId": auth.accountId, "bucketName": name])
        let response = try await send(request, as: Response.self, step: "B2 list buckets")
        guard let bucket = response.buckets.first(where: { $0.bucketName == name }) else {
            throw UploadError.httpError(statusCode: 0, message: "B2 bucket \"\(name)\" not found.")
        }
        return bucket.bucketId
    }

    static func uploadTarget(auth: Authorization, bucketId: String) async throws -> (URL, String) {
        struct Response: Decodable { let uploadUrl: String, authorizationToken: String }
        var request = URLRequest(url: URL(string: auth.apiUrl + "/b2api/v1/b2_get_upload_url")!)
        request.httpMethod = "POST"
        request.setValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["bucketId": bucketId])
        let response = try await send(request, as: Response.self, step: "B2 get upload URL")
        guard let url = URL(string: response.uploadUrl) else {
            throw UploadError.invalidRequestURL(response.uploadUrl)
        }
        return (url, response.authorizationToken)
    }

    static func send<T: Decodable>(_ request: URLRequest, as type: T.Type, step: String) async throws -> T {
        let (data, response) = try await UploadHTTP.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.httpError(statusCode: status, message: "\(step): \(body.prefix(200))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
