// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// The six OAuth2 destination uploaders. Each fetches a bearer token via
// OAuthSession (which enforces the configured/authenticated gate) and then
// speaks the host's upload + public-link API.
//
// ponytail: these request mappings follow each host's documented v3/v2 API but
// are UNTESTED until real app credentials exist — the gate keeps them dormant.
// Expect to verify/adjust each against the live API when you connect an account
// (no chunked/resumable uploads, no progress reporting yet).

import Foundation
import SharedKit

public enum OAuthUploaderRegistry {
    public static func upload(id: OAuthProviderID, file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        switch id {
        case .googleDrive: return try await GoogleDriveUploader.upload(file: file, config: config)
        case .youTube:     return try await YouTubeUploader.upload(file: file, config: config)
        case .dropbox:     return try await DropboxUploader.upload(file: file, config: config)
        case .oneDrive:    return try await OneDriveUploader.upload(file: file, config: config)
        case .box:         return try await BoxUploader.upload(file: file, config: config)
        case .imgur:       return try await ImgurUploader.upload(file: file, config: config)
        }
    }
}

// MARK: - Google Drive

enum GoogleDriveUploader {
    static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        let token = try await OAuthSession.validAccessToken(for: .googleDrive, config: config)
        let boundary = "----SwiftXBoundary\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: ["name": file.fileName])
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8Data)
        body.append(metadata)
        body.append("\r\n--\(boundary)\r\nContent-Type: \(file.mimeType)\r\n\r\n".utf8Data)
        body.append(file.data)
        body.append("\r\n--\(boundary)--\r\n".utf8Data)

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, _) = try await checkedSend(request, step: "Google Drive upload")
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let fileID = json?["id"] as? String else { throw UploadError.emptyResult }

        // make it link-shareable, then return the browser link
        var perm = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)/permissions")!)
        perm.httpMethod = "POST"
        perm.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        perm.setValue("application/json", forHTTPHeaderField: "Content-Type")
        perm.httpBody = try JSONSerialization.data(withJSONObject: ["role": "reader", "type": "anyone"])
        _ = try? await checkedSend(perm, step: "Google Drive share")

        let link = json?["webViewLink"] as? String ?? "https://drive.google.com/file/d/\(fileID)/view"
        return UploadResult(url: link)
    }
}

// MARK: - YouTube

enum YouTubeUploader {
    static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        let token = try await OAuthSession.validAccessToken(for: .youTube, config: config)
        let title = (file.fileName as NSString).deletingPathExtension
        let snippet: [String: Any] = ["snippet": ["title": title], "status": ["privacyStatus": "unlisted"]]

        // 1. start a resumable session; the upload URL comes back in Location
        var start = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        start.httpMethod = "POST"
        start.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.setValue("\(file.data.count)", forHTTPHeaderField: "X-Upload-Content-Length")
        start.setValue(file.mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: snippet)
        let (_, startResponse) = try await checkedSend(start, step: "YouTube session")
        guard let uploadURL = startResponse.value(forHTTPHeaderField: "Location").flatMap(URL.init) else {
            throw UploadError.emptyResult
        }

        // 2. PUT the bytes in one shot (ponytail: single request, no chunking)
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        put.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        put.httpBody = file.data
        let (data, _) = try await checkedSend(put, step: "YouTube upload")
        let id = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["id"] as? String ?? ""
        guard !id.isEmpty else { throw UploadError.emptyResult }
        return UploadResult(url: "https://youtu.be/\(id)")
    }
}

// MARK: - Dropbox

enum DropboxUploader {
    static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        let token = try await OAuthSession.validAccessToken(for: .dropbox, config: config)
        let path = "/\(file.fileName)"
        let apiArg = try JSONSerialization.data(withJSONObject: ["path": path, "mode": "add", "autorename": true])

        var upload = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        upload.httpMethod = "POST"
        upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        upload.setValue(String(data: apiArg, encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upload.httpBody = file.data
        _ = try await checkedSend(upload, step: "Dropbox upload")

        // create (or fetch existing) shared link
        var share = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings")!)
        share.httpMethod = "POST"
        share.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        share.setValue("application/json", forHTTPHeaderField: "Content-Type")
        share.httpBody = try JSONSerialization.data(withJSONObject: ["path": path])
        let (data, _) = try await checkedSend(share, step: "Dropbox share")
        guard let url = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["url"] as? String else {
            throw UploadError.emptyResult
        }
        // ?dl=1 serves the file directly instead of the preview page
        return UploadResult(url: url.replacingOccurrences(of: "?dl=0", with: "?dl=1"))
    }
}

// MARK: - OneDrive (Microsoft Graph)

enum OneDriveUploader {
    static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        let token = try await OAuthSession.validAccessToken(for: .oneDrive, config: config)
        let encoded = file.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.fileName

        // simple PUT upload (ponytail: fine up to ~250 MB; larger needs an
        // upload session)
        var put = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive/root:/\(encoded):/content")!)
        put.httpMethod = "PUT"
        put.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        put.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        put.httpBody = file.data
        let (data, _) = try await checkedSend(put, step: "OneDrive upload")
        guard let itemID = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["id"] as? String else {
            throw UploadError.emptyResult
        }

        var link = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive/items/\(itemID)/createLink")!)
        link.httpMethod = "POST"
        link.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        link.setValue("application/json", forHTTPHeaderField: "Content-Type")
        link.httpBody = try JSONSerialization.data(withJSONObject: ["type": "view", "scope": "anonymous"])
        let (linkData, _) = try await checkedSend(link, step: "OneDrive share")
        let json = (try? JSONSerialization.jsonObject(with: linkData)) as? [String: Any]
        let url = (json?["link"] as? [String: Any])?["webUrl"] as? String
        return UploadResult(url: url ?? "https://onedrive.live.com")
    }
}

// MARK: - Box

enum BoxUploader {
    static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        let token = try await OAuthSession.validAccessToken(for: .box, config: config)
        let attributes = try JSONSerialization.data(withJSONObject: ["name": file.fileName, "parent": ["id": "0"]])
        let boundary = "----SwiftXBoundary\(UUID().uuidString)"
        let body = SimpleHostUploader.multipartBody(
            fields: [("attributes", String(data: attributes, encoding: .utf8) ?? "{}")],
            fileField: "file", file: file, boundary: boundary)

        var upload = URLRequest(url: URL(string: "https://upload.box.com/api/2.0/files/content")!)
        upload.httpMethod = "POST"
        upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.httpBody = body
        let (data, _) = try await checkedSend(upload, step: "Box upload")
        let entries = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["entries"] as? [[String: Any]]
        guard let fileID = entries?.first?["id"] as? String else { throw UploadError.emptyResult }

        var share = URLRequest(url: URL(string: "https://api.box.com/2.0/files/\(fileID)")!)
        share.httpMethod = "PUT"
        share.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        share.setValue("application/json", forHTTPHeaderField: "Content-Type")
        share.httpBody = try JSONSerialization.data(withJSONObject: ["shared_link": ["access": "open"]])
        let (shareData, _) = try await checkedSend(share, step: "Box share")
        let sharedLink = ((try? JSONSerialization.jsonObject(with: shareData)) as? [String: Any])?["shared_link"] as? [String: Any]
        return UploadResult(url: sharedLink?["url"] as? String ?? "https://app.box.com/file/\(fileID)")
    }
}

// MARK: - Imgur

enum ImgurUploader {
    static func upload(file: UploadFile, config: UploadersConfig) async throws -> UploadResult {
        let token = try await OAuthSession.validAccessToken(for: .imgur, config: config)
        let boundary = "----SwiftXBoundary\(UUID().uuidString)"
        let body = SimpleHostUploader.multipartBody(fields: [], fileField: "image", file: file, boundary: boundary)

        var request = URLRequest(url: URL(string: "https://api.imgur.com/3/image")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, _) = try await checkedSend(request, step: "Imgur upload")
        let payload = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [String: Any]
        guard let link = payload?["link"] as? String else { throw UploadError.emptyResult }
        var result = UploadResult(url: link)
        if let hash = payload?["deletehash"] as? String {
            result.deletionURL = "https://imgur.com/delete/\(hash)"
        }
        return result
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
