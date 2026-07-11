// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Multi-step token/password hosts: ownCloud/Nextcloud (WebDAV PUT + OCS public
// share), Seafile (upload-link + shared-link), Pushbullet (upload-request +
// S3 form post + push).

import Foundation
import SharedKit

func basicAuthHeader(_ user: String, _ password: String) -> String {
    "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
}

func checkedSend(_ request: URLRequest, step: String) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await UploadHTTP.data(for: request)
    let http = response as? HTTPURLResponse
    let status = http?.statusCode ?? 0
    guard (200..<300).contains(status), let http else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw UploadError.httpError(statusCode: status, message: "\(step): \(body.prefix(200))")
    }
    return (data, http)
}

// MARK: - ownCloud / Nextcloud

public enum OwnCloudUploader {
    public static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        guard !config.ownCloudHost.isEmpty, !config.ownCloudUsername.isEmpty, !config.ownCloudPassword.isEmpty else {
            throw UploadError.missingRequestURL
        }
        var request = try webdavRequest(file: file, config: config)
        request.httpBody = file.data
        _ = try await checkedSend(request, step: "WebDAV upload")

        guard config.ownCloudCreateShare else {
            // no public share requested; point at the file in the web UI
            return UploadResult(url: URLShortener.fixPrefix(config.ownCloudHost))
        }
        let shareRequest = try shareRequest(fileName: file.fileName, config: config)
        let (data, _) = try await checkedSend(shareRequest, step: "OCS share")
        return UploadResult(url: try parseShareResponse(data))
    }

    static func remotePath(_ config: UploadersConfig, fileName: String) -> String {
        let dir = config.ownCloudPath.isEmpty ? "/" : config.ownCloudPath
        return dir.hasSuffix("/") ? dir + fileName : dir + "/" + fileName
    }

    static func webdavRequest(file: UploadFile, config: UploadersConfig) throws -> URLRequest {
        let host = URLShortener.fixPrefix(config.ownCloudHost)
        let path = remotePath(config, fileName: file.fileName)
        let encoded = path.split(separator: "/").map(AmazonS3Uploader.uriEncoded).joined(separator: "/")
        guard let url = URL(string: host + "/remote.php/webdav/" + encoded) else {
            throw UploadError.invalidRequestURL(host)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(config.ownCloudUsername, config.ownCloudPassword), forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        return request
    }

    static func shareRequest(fileName: String, config: UploadersConfig) throws -> URLRequest {
        let host = URLShortener.fixPrefix(config.ownCloudHost)
        guard let url = URL(string: host + "/ocs/v1.php/apps/files_sharing/api/v1/shares?format=json") else {
            throw UploadError.invalidRequestURL(host)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(config.ownCloudUsername, config.ownCloudPassword), forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        let path = remotePath(config, fileName: fileName)
        // shareType 3 = public link, permissions 1 = read-only
        let encodedPath = URLShortener.queryEncode(path)
        request.httpBody = Data("path=\(encodedPath)&shareType=3&permissions=1".utf8)
        return request
    }

    static func parseShareResponse(_ data: Data) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let ocs = json?["ocs"] as? [String: Any]
        let meta = ocs?["meta"] as? [String: Any]
        let statuscode = meta?["statuscode"] as? Int ?? 0
        guard statuscode == 100 || statuscode == 200,
              let shareURL = (ocs?["data"] as? [String: Any])?["url"] as? String else {
            throw UploadError.httpError(statusCode: 0, message: "OCS share failed: \(meta?["message"] as? String ?? "unknown")")
        }
        return shareURL
    }
}

// MARK: - Seafile

public enum SeafileUploader {
    public static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        guard !config.seafileAPIURL.isEmpty, !config.seafileAuthToken.isEmpty, !config.seafileRepoID.isEmpty else {
            throw UploadError.missingRequestURL
        }
        // 1. ask the server for a one-time upload URL
        let (linkData, _) = try await checkedSend(try uploadLinkRequest(config: config), step: "Seafile upload link")
        let quoted = String(data: linkData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let uploadURLString = quoted.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard let uploadURL = URL(string: uploadURLString) else {
            throw UploadError.invalidRequestURL(uploadURLString)
        }

        // 2. multipart upload to that URL
        let boundary = "----ShareXBoundary\(UUID().uuidString)"
        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "POST"
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.setValue("Token \(config.seafileAuthToken)", forHTTPHeaderField: "Authorization")
        upload.httpBody = SimpleHostUploader.multipartBody(
            fields: [("filename", file.fileName), ("parent_dir", directory(config))],
            fileField: "file", file: file, boundary: boundary
        )
        _ = try await checkedSend(upload, step: "Seafile upload")

        // 3. create a public download link; its URL arrives in the Location header
        let (_, shareResponse) = try await checkedSend(try shareRequest(fileName: file.fileName, config: config), step: "Seafile share")
        guard let location = shareResponse.value(forHTTPHeaderField: "Location"), !location.isEmpty else {
            throw UploadError.emptyResult
        }
        return UploadResult(url: location)
    }

    static func directory(_ config: UploadersConfig) -> String {
        var dir = config.seafilePath.isEmpty ? "/" : config.seafilePath
        if !dir.hasSuffix("/") { dir += "/" }
        return dir
    }

    static func uploadLinkRequest(config: UploadersConfig) throws -> URLRequest {
        let api = URLShortener.fixPrefix(config.seafileAPIURL)
        guard let url = URL(string: "\(api)/repos/\(config.seafileRepoID)/upload-link/?format=json") else {
            throw UploadError.invalidRequestURL(api)
        }
        var request = URLRequest(url: url)
        request.setValue("Token \(config.seafileAuthToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func shareRequest(fileName: String, config: UploadersConfig) throws -> URLRequest {
        let api = URLShortener.fixPrefix(config.seafileAPIURL)
        guard let url = URL(string: "\(api)/repos/\(config.seafileRepoID)/file/shared-link/") else {
            throw UploadError.invalidRequestURL(api)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Token \(config.seafileAuthToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let path = directory(config) + fileName
        request.httpBody = Data("p=\(URLShortener.queryEncode(path))&share_type=download".utf8)
        return request
    }
}

// MARK: - Pushbullet

public enum PushbulletUploader {
    struct UploadRequest: Decodable {
        let uploadUrl: String
        let fileUrl: String
        let fileType: String
        let data: [String: String]

        enum CodingKeys: String, CodingKey {
            case uploadUrl = "upload_url", fileUrl = "file_url", fileType = "file_type", data
        }
    }

    public static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        guard !config.pushbulletAPIKey.isEmpty else { throw UploadError.missingRequestURL }
        let auth = basicAuthHeader(config.pushbulletAPIKey, "")

        // 1. request an upload slot (returns pre-signed S3 form fields)
        var slotRequest = URLRequest(url: URL(string: "https://api.pushbullet.com/v2/upload-request")!)
        slotRequest.httpMethod = "POST"
        slotRequest.setValue(auth, forHTTPHeaderField: "Authorization")
        slotRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        slotRequest.httpBody = try JSONSerialization.data(withJSONObject: ["file_name": file.fileName, "file_type": file.mimeType])
        let (slotData, _) = try await checkedSend(slotRequest, step: "Pushbullet upload request")
        let slot = try JSONDecoder().decode(UploadRequest.self, from: slotData)

        // 2. post the file to the pre-signed URL; form fields must precede the file
        guard let uploadURL = URL(string: slot.uploadUrl) else { throw UploadError.invalidRequestURL(slot.uploadUrl) }
        let boundary = "----ShareXBoundary\(UUID().uuidString)"
        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "POST"
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.httpBody = SimpleHostUploader.multipartBody(fields: slot.data.sorted { $0.key < $1.key },
                                                           fileField: "file", file: file, boundary: boundary)
        _ = try await checkedSend(upload, step: "Pushbullet file upload")

        // 3. push the file
        // ponytail: no device_iden -> pushes to all of the account's devices;
        // a device picker can come with a fuller Pushbullet integration
        var push = URLRequest(url: URL(string: "https://api.pushbullet.com/v2/pushes")!)
        push.httpMethod = "POST"
        push.setValue(auth, forHTTPHeaderField: "Authorization")
        push.setValue("application/json", forHTTPHeaderField: "Content-Type")
        push.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "file", "file_name": file.fileName, "file_url": slot.fileUrl,
            "file_type": slot.fileType, "body": "Sent via SwiftX"
        ])
        let (pushData, _) = try await checkedSend(push, step: "Pushbullet push")
        let iden = ((try? JSONSerialization.jsonObject(with: pushData)) as? [String: Any])?["iden"] as? String ?? ""
        return UploadResult(url: iden.isEmpty ? slot.fileUrl : "https://www.pushbullet.com/pushes?push_iden=\(iden)")
    }
}
