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
    /// `settings` overrides the stored TaskSettings for this run (quick task
    /// presets, before-upload destination change); nil loads from disk.
    static func uploadImage(_ image: CGImage, fileName: String, filePath: String? = nil,
                            format: ImageFileFormat = .png, jpegQuality: Int = 90,
                            settings: TaskSettings? = nil) {
        guard let data = ImageWriter.data(image, format: format, jpegQuality: jpegQuality) else {
            Notifier.notify(title: "Upload failed", body: "Could not encode the image.")
            return
        }
        upload(UploadFile(data: data, fileName: fileName, mimeType: format.mimeType),
               filePath: filePath, settingsOverride: settings)
    }

    /// Uploads an existing file (recordings, GIFs) through the image destination.
    /// ponytail: reuses ImageDestination for all file types; a separate
    /// FileDestination setting can come with the destination long tail (Phase 9).
    static func uploadFile(at url: URL, settings: TaskSettings? = nil) {
        guard let data = try? Data(contentsOf: url) else {
            Notifier.notify(title: "Upload failed", body: "Could not read \(url.lastPathComponent).")
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        upload(UploadFile(data: data, fileName: url.lastPathComponent, mimeType: mime),
               filePath: url.path, settingsOverride: settings)
    }

    enum RoutingError: LocalizedError {
        case noCustomUploader
        case notImplemented(String)

        var errorDescription: String? {
            switch self {
            case .noCustomUploader:
                return "No custom uploader configured. Import a .sxcu in Settings → Custom Uploader."
            case .notImplemented(let destination):
                return "Destination \"\(destination)\" is not implemented yet."
            }
        }
    }

    private static func route(_ file: UploadFile, settings: TaskSettings,
                              config: UploadersConfig) async throws -> (UploadResult, String) {
        switch settings.imageDestination {
        case "AmazonS3":
            return (try await AmazonS3Uploader.upload(file: file, settings: config.amazonS3), "Amazon S3")
        case "BackblazeB2":
            return (try await BackblazeB2Uploader.upload(file: file, config: config), "Backblaze B2")
        case "AzureStorage":
            return (try await AzureStorageUploader.upload(file: file, config: config), "Azure Storage")
        case "OwnCloud":
            return (try await OwnCloudUploader.upload(file: file, config: config), "ownCloud / Nextcloud")
        case "Seafile":
            return (try await SeafileUploader.upload(file: file, config: config), "Seafile")
        case "Pushbullet":
            return (try await PushbulletUploader.upload(file: file, config: config), "Pushbullet")
        case "CustomImageUploader":
            guard let item = CustomUploaderStore.load(named: config.activeCustomUploader) else {
                throw RoutingError.noCustomUploader
            }
            return (try await CustomUploaderService.upload(file: file, with: item), item.displayName)
        default:
            guard let destination = SimpleHostDestination(rawValue: settings.imageDestination) else {
                throw RoutingError.notImplemented(settings.imageDestination)
            }
            return (try await SimpleHostUploader.upload(file: file, destination: destination, config: config),
                    destination.displayName)
        }
    }

    private static func upload(_ file: UploadFile, filePath: String?,
                               settingsOverride: TaskSettings? = nil, isRetry: Bool = false) {
        let settings = settingsOverride ?? TaskSettings.load()

        // C# WorkerTask: the before-upload window intercepts every upload
        // source (captures, recordings, files) right before dispatch
        if !isRetry, settings.afterCaptureJob.contains(.showBeforeUploadWindow) {
            Task {
                guard var chosen = await BeforeUploadWindow.present(
                    fileName: file.fileName, previewData: file.data, settings: settings) else { return }
                chosen.afterCaptureJob.remove(.showBeforeUploadWindow)
                upload(file, filePath: filePath, settingsOverride: chosen)
            }
            return
        }

        let config = UploadersConfig.load()
        let entryID = UploadTaskCenter.shared.begin(fileName: file.fileName, host: settings.imageDestination)
        let reporter = UploadProgressReporter { sent, expected in
            Task { @MainActor in
                UploadTaskCenter.shared.progress(entryID, sent: sent, expected: expected)
            }
        }

        Task {
            do {
                let (result, hostName) = try await UploadProgressReporter.$current.withValue(reporter) {
                    try await route(file, settings: settings, config: config)
                }
                if let filePath {
                    await MainActor.run {
                        HistoryStore.shared.updateUploadURLs(
                            filePath: filePath, host: hostName, url: result.url,
                            thumbnailURL: result.thumbnailURL, deletionURL: result.deletionURL
                        )
                    }
                }
                await MainActor.run {
                    UploadTaskCenter.shared.finish(entryID, state: .completed(url: result.url))
                }
                try await afterUpload(result, settings: settings)
            } catch {
                // misconfiguration won't fix itself in one second; only
                // transport/host failures earn the retry
                if !isRetry, ApplicationConfig.load().retryUpload, !(error is RoutingError) {
                    NSLog("Upload failed (%@); retrying once", error.localizedDescription)
                    await MainActor.run {
                        UploadTaskCenter.shared.finish(entryID, state: .retrying)
                    }
                    try? await Task.sleep(for: .seconds(1))
                    await MainActor.run {
                        upload(file, filePath: filePath, settingsOverride: settingsOverride, isRetry: true)
                    }
                    return
                }
                await MainActor.run {
                    UploadTaskCenter.shared.finish(entryID, state: .failed(message: error.localizedDescription))
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

        if tasks.contains(.copyURLToClipboard), !finalURL.isEmpty {
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

        Notifier.notify(title: "Upload complete", body: finalURL,
                        sound: settings.playSoundAfterUpload, url: finalURL)
    }
}
