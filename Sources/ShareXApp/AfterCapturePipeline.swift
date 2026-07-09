// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Runs the configured AfterCaptureTasks chain on a captured image.
// Unimplemented flags log and no-op until their phase lands (editor,
// effects, OCR, upload, ...).

import AppKit
import CaptureKit
import EditorKit
import HistoryKit
import SharedKit

@MainActor
enum AfterCapturePipeline {
    static let implemented: AfterCaptureTasks = [
        .annotateImage, .copyImageToClipboard, .pinToScreen, .sendImageToPrinter,
        .saveImageToFile, .saveImageToFileWithDialog, .saveThumbnailImageToFile,
        .performActions, .copyFileToClipboard, .copyFilePathToClipboard, .copyFolderPathToClipboard,
        .showInExplorer, .uploadImageToHost, .deleteFile
    ]

    static func run(image capturedImage: CGImage, processName: String? = nil, windowTitle: String? = nil) async {
        let settings = TaskSettings.load()
        let config = ApplicationConfig.load()
        let tasks = settings.afterCaptureJob

        var image = capturedImage
        if tasks.contains(.annotateImage) {
            // C# behavior: the task waits for the editor; Cancel aborts the whole task
            guard let edited = await ImageEditorPresenter.present(image: image) else { return }
            image = edited
        }

        if tasks.contains(.copyImageToClipboard) {
            ImageWriter.copyToClipboard(image)
        }

        if tasks.contains(.pinToScreen) {
            PinnedWindows.pin(image)
        }

        let format = ImageWriter.effectiveFormat(
            named: settings.imageFormat,
            autoUseJPEG: settings.imageAutoUseJPEG, autoUseJPEGSize: settings.imageAutoUseJPEGSize,
            width: image.width, height: image.height
        )
        var savedURL: URL?

        if tasks.contains(.saveImageToFile) {
            let url = SavePath.screenshotURL(
                config: config, task: settings,
                windowTitle: windowTitle, processName: processName,
                width: image.width, height: image.height,
                fileExtension: format.fileExtension
            )
            do {
                try ImageWriter.write(image, to: url, format: format, jpegQuality: settings.imageJPEGQuality)
                savedURL = url
                Notifier.captureSaved(url)
            } catch {
                presentError(error)
            }
        }

        if tasks.contains(.saveImageToFileWithDialog) {
            let panel = NSSavePanel()
            panel.directoryURL = config.screenshotsFolder
            panel.nameFieldStringValue = savedURL?.lastPathComponent
                ?? SavePath.screenshotURL(config: config, task: settings, processName: processName,
                                          fileExtension: format.fileExtension).lastPathComponent
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try ImageWriter.write(image, to: url, format: format, jpegQuality: settings.imageJPEGQuality)
                    savedURL = url
                } catch {
                    presentError(error)
                }
            }
        }

        if tasks.contains(.saveThumbnailImageToFile),
           let thumb = ImageWriter.thumbnail(image, width: settings.thumbnailWidth,
                                             height: settings.thumbnailHeight,
                                             onlyIfLarger: settings.thumbnailCheckSize) {
            let base = savedURL ?? SavePath.screenshotURL(
                config: config, task: settings,
                windowTitle: windowTitle, processName: processName,
                width: image.width, height: image.height,
                fileExtension: format.fileExtension
            )
            let name = base.deletingPathExtension().lastPathComponent + settings.thumbnailName
            let url = base.deletingLastPathComponent()
                .appendingPathComponent(name).appendingPathExtension(format.fileExtension)
            do {
                try ImageWriter.write(thumb, to: url, format: format, jpegQuality: settings.imageJPEGQuality)
            } catch {
                presentError(error)
            }
        }

        // actions run before anything references the file, so the pipeline
        // continues with the action's output (C# order: actions precede upload)
        if tasks.contains(.performActions), let inputURL = savedURL {
            do {
                savedURL = try await ExternalProgramRunner.runAll(settings.externalPrograms, on: inputURL)
            } catch {
                Notifier.notify(title: "Action failed", body: error.localizedDescription)
            }
        }

        if let savedURL {
            var historyItem = HistoryItem()
            historyItem.fileName = savedURL.lastPathComponent
            historyItem.filePath = savedURL.path
            historyItem.type = "Image"
            historyItem.host = "File"
            HistoryStore.shared.append(historyItem)

            if tasks.contains(.copyFileToClipboard) {
                // file reference, not pixels: pasting in Finder/Slack attaches the file
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([savedURL as NSURL])
            }
            if tasks.contains(.copyFilePathToClipboard) {
                copyString(savedURL.path)
            }
            if tasks.contains(.copyFolderPathToClipboard) {
                copyString(savedURL.deletingLastPathComponent().path)
            }
            if tasks.contains(.showInExplorer) {
                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
            }
        }

        if tasks.contains(.uploadImageToHost) {
            if let savedURL {
                // reuse the encoded file so bytes, name and MIME type all agree
                UploadCoordinator.uploadFile(at: savedURL)
            } else {
                let fileName = SavePath.screenshotURL(config: config, task: settings, processName: processName,
                                                      fileExtension: format.fileExtension).lastPathComponent
                UploadCoordinator.uploadImage(image, fileName: fileName,
                                              format: format, jpegQuality: settings.imageJPEGQuality)
            }
        }

        if tasks.contains(.sendImageToPrinter) {
            printImage(image)
        }

        // last: the upload path has already read the file's bytes by now.
        // Trash instead of C#'s permanent delete - recoverable mistakes only.
        if tasks.contains(.deleteFile), let savedURL {
            try? FileManager.default.trashItem(at: savedURL, resultingItemURL: nil)
        }

        let pending = tasks.subtracting(implemented)
        if !pending.isEmpty {
            NSLog("AfterCaptureTasks not implemented yet: %@", pending.nameString)
        }
    }

    private static func printImage(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: .zero)
        let view = NSImageView(frame: NSRect(origin: .zero, size: nsImage.size))
        view.image = nsImage
        view.imageScaling = .scaleProportionallyDown
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        NSApp.activate(ignoringOtherApps: true)
        NSPrintOperation(view: view, printInfo: info).run()
    }

    private static func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "After-capture task failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// Floating always-on-top image windows ("Pin to screen").
/// Drag to move, double-click to close.
@MainActor
enum PinnedWindows {
    private static var panels: [NSPanel] = []

    static func pin(_ cgImage: CGImage) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        pin(NSImage(cgImage: cgImage, size: size))
    }

    static func pin(_ image: NSImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        var size = image.size
        if let screen = NSScreen.main {
            let maxSize = NSSize(width: screen.visibleFrame.width * 0.6, height: screen.visibleFrame.height * 0.6)
            let ratio = min(1, maxSize.width / size.width, maxSize.height / size.height)
            size = NSSize(width: size.width * ratio, height: size.height * ratio)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces]

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let doubleClick = NSClickGestureRecognizer(target: panel, action: #selector(NSPanel.close))
        doubleClick.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(doubleClick)
        panel.contentView = imageView

        panel.center()
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    static func pinFromClipboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            Notifier.notify(title: "Pin to screen", body: "No image on the clipboard.")
            return
        }
        pin(image)
    }

    static func closeAll() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}
