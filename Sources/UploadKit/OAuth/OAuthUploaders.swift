// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// The OAuth2 destination uploaders. Each fetches a bearer token via
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
        case .oneDrive:    return try await OneDriveUploader.upload(file: file, config: config)
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

private extension String {
    var utf8Data: Data { Data(utf8) }
}
