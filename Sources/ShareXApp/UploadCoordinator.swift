// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import CaptureKit
import SharedKit
import UploadKit

@MainActor
enum UploadCoordinator {
    static func uploadImage(_ image: CGImage, fileName: String) {
        guard let data = ImageWriter.pngData(image) else {
            Notifier.notify(title: "Upload failed", body: "Could not encode the image.")
            return
        }

        let config = UploadersConfig.load()
        let settings = TaskSettings.load()
        let file = UploadFile(data: data, fileName: fileName, mimeType: "image/png")

        Task {
            do {
                let result: UploadResult
                switch settings.imageDestination {
                case "AmazonS3":
                    result = try await AmazonS3Uploader.upload(file: file, settings: config.amazonS3)
                case "CustomImageUploader":
                    guard let item = CustomUploaderStore.load(named: config.activeCustomUploader) else {
                        await MainActor.run {
                            Notifier.notify(title: "Upload", body: "No custom uploader configured. Import a .sxcu from the ShareX menu.")
                        }
                        return
                    }
                    result = try await CustomUploaderService.upload(file: file, with: item)
                default:
                    await MainActor.run {
                        Notifier.notify(title: "Upload", body: "Destination \"\(settings.imageDestination)\" is not implemented yet.")
                    }
                    return
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

        let pending = tasks.subtracting([.copyURLToClipboard, .openURL, .useURLShortener])
        if !pending.isEmpty {
            NSLog("AfterUploadTasks not implemented yet: %@", pending.nameString)
        }

        Notifier.notify(title: "Upload complete", body: finalURL)
    }
}
