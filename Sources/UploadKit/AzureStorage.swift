// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Azure Blob Storage PUT with SharedKey authorization. buildRequest is pure
// (date injectable) so the signature is unit-testable, like the S3 uploader.

import CryptoKit
import Foundation
import SharedKit

public enum AzureStorageUploader {
    static let apiVersion = "2016-05-31"

    public static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        let request = try buildRequest(file: file, config: config, date: Date())
        let (data, response) = try await UploadHTTP.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.httpError(statusCode: status, message: String(body.prefix(300)))
        }
        return UploadResult(url: resultURL(path: uploadPath(for: file.fileName, config: config), config: config))
    }

    public static func buildRequest(file: UploadFile, config: UploadersConfig, date: Date) throws -> URLRequest {
        guard !config.azureStorageAccountName.isEmpty, !config.azureStorageAccountAccessKey.isEmpty,
              !config.azureStorageContainer.isEmpty else {
            throw UploadError.missingRequestURL
        }
        guard let key = Data(base64Encoded: config.azureStorageAccountAccessKey) else {
            throw UploadError.httpError(statusCode: 0, message: "Azure access key is not valid base64.")
        }

        let dateString = rfc1123Formatter.string(from: date)
        let path = uploadPath(for: file.fileName, config: config, date: date)
        let environment = config.azureStorageEnvironment.isEmpty ? "blob.core.windows.net" : config.azureStorageEnvironment
        let encodedPath = path.split(separator: "/").map(AmazonS3Uploader.uriEncoded).joined(separator: "/")
        guard let url = URL(string: "https://\(config.azureStorageAccountName).\(environment)/\(config.azureStorageContainer)/\(encodedPath)") else {
            throw UploadError.invalidRequestURL(path)
        }

        var canonicalizedHeaders = "x-ms-blob-type:BlockBlob\nx-ms-date:\(dateString)\nx-ms-version:\(apiVersion)\n"
        if !config.azureStorageCacheControl.isEmpty {
            canonicalizedHeaders = "x-ms-blob-cache-control:\(config.azureStorageCacheControl)\n" + canonicalizedHeaders
        }
        let canonicalizedResource = "/\(config.azureStorageAccountName)/\(config.azureStorageContainer)/\(path)"

        // header order and empty lines follow the SharedKey spec (matches the C# port)
        let stringToSign = [
            "PUT", "", "", String(file.data.count), "", file.mimeType, "", "", "", "", "", "",
            canonicalizedHeaders + canonicalizedResource
        ].joined(separator: "\n")
        let signature = Data(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8),
                                                             using: SymmetricKey(data: key))).base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = file.data
        request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(dateString, forHTTPHeaderField: "x-ms-date")
        request.setValue(apiVersion, forHTTPHeaderField: "x-ms-version")
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        if !config.azureStorageCacheControl.isEmpty {
            request.setValue(config.azureStorageCacheControl, forHTTPHeaderField: "x-ms-blob-cache-control")
        }
        request.setValue("SharedKey \(config.azureStorageAccountName):\(signature)", forHTTPHeaderField: "Authorization")
        return request
    }

    public static func uploadPath(for fileName: String, config: UploadersConfig, date: Date = Date()) -> String {
        let parser = NameParser(.filePath)
        parser.date = date
        var prefix = parser.parse(config.azureStorageUploadPath)
        if !prefix.isEmpty, !prefix.hasSuffix("/") { prefix += "/" }
        return prefix + fileName
    }

    static func resultURL(path: String, config: UploadersConfig) -> String {
        let encodedPath = path.split(separator: "/").map(AmazonS3Uploader.uriEncoded).joined(separator: "/")
        if !config.azureStorageCustomDomain.isEmpty {
            return URLShortener.fixPrefix(config.azureStorageCustomDomain) + "/" + encodedPath
        }
        let environment = config.azureStorageEnvironment.isEmpty ? "blob.core.windows.net" : config.azureStorageEnvironment
        return "https://\(config.azureStorageAccountName).\(environment)/\(config.azureStorageContainer)/\(encodedPath)"
    }

    static let rfc1123Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
