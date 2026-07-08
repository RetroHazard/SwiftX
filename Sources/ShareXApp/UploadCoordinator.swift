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
        guard let item = CustomUploaderStore.load(named: config.activeCustomUploader) else {
            Notifier.notify(title: "Upload", body: "No destination configured. Import a custom uploader (.sxcu) from the ShareX menu.")
            return
        }

        let file = UploadFile(data: data, fileName: fileName, mimeType: "image/png")
        Task {
            do {
                let result = try await CustomUploaderService.upload(file: file, with: item)
                await MainActor.run { afterUpload(result) }
            } catch {
                await MainActor.run {
                    Notifier.notify(title: "Upload failed", body: error.localizedDescription)
                }
            }
        }
    }

    private static func afterUpload(_ result: UploadResult) {
        let tasks = TaskSettings.load().afterUploadJob

        if tasks.contains(.copyURLToClipboard) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(result.url, forType: .string)
        }
        if tasks.contains(.openURL), let url = URL(string: result.url) {
            NSWorkspace.shared.open(url)
        }

        let pending = tasks.subtracting([.copyURLToClipboard, .openURL])
        if !pending.isEmpty {
            NSLog("AfterUploadTasks not implemented yet: %@", pending.nameString)
        }

        Notifier.notify(title: "Upload complete", body: result.url)
    }
}
