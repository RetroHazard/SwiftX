// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import CaptureKit
import HistoryKit
import SharedKit
import UniformTypeIdentifiers
import UploadKit

@MainActor
enum UploadCoordinator {
    static func uploadImage(_ image: CGImage, fileName: String, filePath: String? = nil) {
        guard let data = ImageWriter.pngData(image) else {
            Notifier.notify(title: "Upload failed", body: "Could not encode the image.")
            return
        }
        upload(UploadFile(data: data, fileName: fileName, mimeType: "image/png"), filePath: filePath)
    }

    /// Uploads an existing file (recordings, GIFs) through the image destination.
    /// ponytail: reuses ImageDestination for all file types; a separate
    /// FileDestination setting can come with the destination long tail (Phase 9).
    static func uploadFile(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            Notifier.notify(title: "Upload failed", body: "Could not read \(url.lastPathComponent).")
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        upload(UploadFile(data: data, fileName: url.lastPathComponent, mimeType: mime), filePath: url.path)
    }

    private static func upload(_ file: UploadFile, filePath: String?) {
        let config = UploadersConfig.load()
        let settings = TaskSettings.load()

        Task {
            do {
                let result: UploadResult
                let hostName: String
                switch settings.imageDestination {
                case "AmazonS3":
                    result = try await AmazonS3Uploader.upload(file: file, settings: config.amazonS3)
                    hostName = "Amazon S3"
                case "CustomImageUploader":
                    guard let item = CustomUploaderStore.load(named: config.activeCustomUploader) else {
                        await MainActor.run {
                            Notifier.notify(title: "Upload", body: "No custom uploader configured. Import a .sxcu from the ShareX menu.")
                        }
                        return
                    }
                    result = try await CustomUploaderService.upload(file: file, with: item)
                    hostName = item.displayName
                default:
                    await MainActor.run {
                        Notifier.notify(title: "Upload", body: "Destination \"\(settings.imageDestination)\" is not implemented yet.")
                    }
                    return
                }
                if let filePath {
                    await MainActor.run {
                        HistoryStore.shared.updateUploadURLs(
                            filePath: filePath, host: hostName, url: result.url,
                            thumbnailURL: result.thumbnailURL, deletionURL: result.deletionURL
                        )
                    }
                }
                try await afterUpload(result, settings: settings)
            } catch {
                await MainActor.run {
                    Notifier.notify(title: "Upload failed", body: error.localizedDescription)
                }
            }
        }
    }

    private static func afterUpload(_ result: UploadResult, settings: TaskSettings) async throws {
        let tasks = settings.afterUploadJob
        var finalURL = result.url

        if tasks.contains(.useURLShortener) {
            let type = URLShortenerType(rawValue: settings.urlShortenerDestination) ?? .isgd
            do {
                finalURL = try await URLShortener.shorten(result.url, type: type)
            } catch {
                Notifier.notify(title: "URL shortener failed", body: error.localizedDescription)
            }
        }

        if tasks.contains(.copyURLToClipboard) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(finalURL, forType: .string)
        }
        if tasks.contains(.openURL), let url = URL(string: finalURL) {
            NSWorkspace.shared.open(url)
        }
        if tasks.contains(.shareURL) {
            let service = URLSharingService(rawValue: settings.urlSharingServiceDestination) ?? .email
            if let url = service.shareURL(for: finalURL) {
                NSWorkspace.shared.open(url)
            }
        }

        let pending = tasks.subtracting([.copyURLToClipboard, .openURL, .useURLShortener, .shareURL])
        if !pending.isEmpty {
            NSLog("AfterUploadTasks not implemented yet: %@", pending.nameString)
        }

        Notifier.notify(title: "Upload complete", body: finalURL)
    }
}
